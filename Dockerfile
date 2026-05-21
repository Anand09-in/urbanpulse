FROM apache/airflow:2.9.0
USER airflow
RUN pip install --no-cache-dir \
    "dbt-core==1.8.9" \
    "dbt-common==1.3.3" \
    "dbt-athena-community==1.8.4" \
    "apache-airflow-providers-amazon==8.19.0" \
    "boto3==1.34.0"
