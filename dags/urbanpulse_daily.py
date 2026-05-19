from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.amazon.aws.operators.lambda_function import LambdaInvokeFunctionOperator
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.amazon.aws.operators.glue_crawler import GlueCrawlerOperator
from airflow.providers.amazon.aws.operators.athena import AthenaOperator
from airflow.operators.bash import BashOperator

default_args = {
    "owner": "urbanpulse",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="urbanpulse_daily_pipeline",
    description="NYC TLC → Bronze → Silver → Gold → Athena validation",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 6 * * *",   # 6am UTC daily
    catchup=False,
    tags=["urbanpulse", "production"],
) as dag:

    # Task 1: Lambda copies NYC TLC data to Bronze S3
    ingest_bronze = LambdaInvokeFunctionOperator(
        task_id="ingest_nyc_tlc_to_bronze",
        function_name="urbanpulse-ingest",
        payload='{"year": "{{ execution_date.strftime(\'%Y\') }}", '
                '"month": "{{ execution_date.strftime(\'%m\') }}"}',
        aws_conn_id="aws_default",
    )

    # Task 2: Glue ETL Bronze → Silver
    bronze_to_silver = GlueJobOperator(
        task_id="glue_bronze_to_silver",
        job_name="urbanpulse-bronze-to-silver",
        aws_conn_id="aws_default",
        wait_for_completion=True,
    )

    # Task 3: Glue Crawler updates Data Catalog schema
    run_crawler = GlueCrawlerOperator(
        task_id="run_glue_crawler",
        config={"Name": "urbanpulse-silver-crawler"},
        aws_conn_id="aws_default",
        wait_for_completion=True,
    )

    # Task 4: dbt run (Silver → Gold via dbt-athena)
    run_dbt = BashOperator(
        task_id="run_dbt_models",
        bash_command="cd /opt/airflow/dbt && dbt run --profiles-dir . && dbt test --profiles-dir .",
    )

    # Task 5: Validate Gold layer — row count sanity check
    validate_gold = AthenaOperator(
        task_id="validate_gold_layer",
        query="""
            SELECT COUNT(*) AS row_count
            FROM urbanpulse_gold.mart_zone_hourly_demand
            WHERE trip_month = '{{ execution_date.strftime('%Y-%m') }}'
        """,
        database="urbanpulse_gold",
        output_location="s3://urbanpulse-athena-results/validation/",
        aws_conn_id="aws_default",
    )

    # Pipeline order
    ingest_bronze >> bronze_to_silver >> run_crawler >> run_dbt >> validate_gold