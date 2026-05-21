FROM apache/airflow:2.9.0
USER airflow
RUN pip install --no-cache-dir \
    "dbt-common==1.3.0" \
    "dbt-athena-community==1.8.4" \
    "apache-airflow-providers-amazon==8.19.0" \
    "boto3==1.34.0"
