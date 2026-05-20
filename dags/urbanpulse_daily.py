from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.amazon.aws.operators.lambda_function import LambdaInvokeFunctionOperator
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.amazon.aws.operators.glue_crawler import GlueCrawlerOperator
from airflow.providers.amazon.aws.operators.athena import AthenaOperator
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.utils.trigger_rule import TriggerRule
import boto3
import logging

logger = logging.getLogger(__name__)

default_args = {
    "owner": "urbanpulse",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
    "email_on_retry": False,
}


def check_bronze_freshness(**context):
    """
    Verifies Bronze S3 was updated in the last 26 hours.
    Fails the DAG early before running expensive Glue jobs.
    """
    s3 = boto3.client("s3", region_name="ap-south-1")
    bucket = "urbanpulse-bronze"

    response = s3.list_objects_v2(
        Bucket=bucket,
        Prefix=f"year={context['execution_date'].strftime('%Y')}/"
               f"month={context['execution_date'].strftime('%m')}/",
    )

    if "Contents" not in response:
        raise ValueError(
            f"Bronze S3 has no data for "
            f"{context['execution_date'].strftime('%Y-%m')}. "
            f"Ingestion may have failed."
        )

    latest = max(
        obj["LastModified"] for obj in response["Contents"]
    )
    age_hours = (
        datetime.now(latest.tzinfo) - latest
    ).total_seconds() / 3600

    logger.info(f"Bronze last updated: {latest} ({age_hours:.1f}h ago)")

    if age_hours > 26:
        raise ValueError(
            f"Bronze data is stale — last updated {age_hours:.1f}h ago. "
            f"Expected update within 26h."
        )

    logger.info("Bronze freshness check passed")


def notify_pipeline_success(**context):
    """Log pipeline completion metrics for monitoring."""
    logger.info(
        f"UrbanPulse pipeline completed successfully. "
        f"Period: {context['execution_date'].strftime('%Y-%m')}"
    )


with DAG(
    dag_id="urbanpulse_daily_pipeline",
    description="NYC TLC Bronze → Silver → Gold → Athena validation",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 6 * * *",
    catchup=False,
    tags=["urbanpulse", "production"],
) as dag:

    # ── Task 0: Check Bronze freshness before anything runs ────────
    check_freshness = PythonOperator(
        task_id="check_bronze_freshness",
        python_callable=check_bronze_freshness,
    )

    # ── Task 1: Ingest NYC TLC data to Bronze ──────────────────────
    ingest_bronze = LambdaInvokeFunctionOperator(
        task_id="ingest_nyc_tlc_to_bronze",
        function_name="urbanpulse-ingest",
        payload='{"year":"{{ execution_date.strftime(\'%Y\') }}",'
                '"month":"{{ execution_date.strftime(\'%m\') }}"}',
        aws_conn_id="aws_default",
    )

    # ── Task 2: Glue ETL Bronze → Silver ──────────────────────────
    bronze_to_silver = GlueJobOperator(
        task_id="glue_bronze_to_silver",
        job_name="urbanpulse-bronze-to-silver",
        script_args={
            "--year":  "{{ execution_date.strftime('%Y') }}",
            "--month": "{{ execution_date.strftime('%m') }}",
        },
        aws_conn_id="aws_default",
        wait_for_completion=True,
    )

    # ── Task 3: Update Glue Data Catalog schema ────────────────────
    run_crawler = GlueCrawlerOperator(
        task_id="run_glue_crawler",
        config={"Name": "urbanpulse-silver-crawler"},
        aws_conn_id="aws_default",
        wait_for_completion=True,
    )

    # ── Task 4: dbt run + test (Silver → Gold) ─────────────────────
    run_dbt = BashOperator(
        task_id="run_dbt_models",
        bash_command=(
            "cd /opt/airflow/dbt/urbanpulse && "
            "dbt run  --profiles-dir . && "
            "dbt test --profiles-dir ."
        ),
    )

    # ── Task 5: Validate Gold row counts via Athena ────────────────
    validate_gold = AthenaOperator(
        task_id="validate_gold_layer",
        query="""
            SELECT
                COUNT(*) AS row_count,
                SUM(trip_count) AS total_trips
            FROM urbanpulse_gold.mart_zone_hourly_demand
            WHERE year  = '{{ execution_date.strftime('%Y') }}'
              AND month = '{{ execution_date.strftime('%m') }}'
        """,
        database="urbanpulse_gold",
        output_location="s3://urbanpulse-athena-results/validation/",
        aws_conn_id="aws_default",
    )

    # ── Task 6: Log success ────────────────────────────────────────
    pipeline_success = PythonOperator(
        task_id="pipeline_success",
        python_callable=notify_pipeline_success,
        trigger_rule=TriggerRule.ALL_SUCCESS,
    )

    # ── Pipeline order ─────────────────────────────────────────────
    (
        check_freshness
        >> ingest_bronze
        >> bronze_to_silver
        >> run_crawler
        >> run_dbt
        >> validate_gold
        >> pipeline_success
    )