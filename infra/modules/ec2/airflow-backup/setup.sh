cat > ~/urbanpulse/setup.sh << 'SETUP'
#!/bin/bash
set -e

echo "==> Creating folder structure..."
mkdir -p ~/urbanpulse/{dags,logs,plugins,config}
cd ~/urbanpulse

echo "==> Writing .env..."
cat > .env << ENV
AIRFLOW_UID=50000
AIRFLOW_GID=0
AWS_DEFAULT_REGION=ap-south-1
_AIRFLOW_WWW_USER_USERNAME=admin
_AIRFLOW_WWW_USER_PASSWORD=admin
ENV

echo "==> Writing docker-compose.yml..."
cat > docker-compose.yml << 'COMPOSE'
version: '3.8'

x-airflow-common: &airflow-common
  image: apache/airflow:2.9.0
  env_file: .env
  environment:
    AIRFLOW__CORE__EXECUTOR: LocalExecutor
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
    AIRFLOW__CORE__LOAD_EXAMPLES: 'false'
    AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION: 'false'
    AIRFLOW__API__AUTH_BACKENDS: airflow.api.auth.backend.basic_auth,airflow.api.auth.backend.session
    AIRFLOW__SCHEDULER__DAG_DIR_LIST_INTERVAL: '30'
    AWS_DEFAULT_REGION: ap-south-1
    _PIP_ADDITIONAL_REQUIREMENTS: "apache-airflow-providers-amazon==8.19.0"
  volumes:
    - ./dags:/opt/airflow/dags
    - ./logs:/opt/airflow/logs
    - ./plugins:/opt/airflow/plugins
  user: "50000:0"
  depends_on:
    postgres:
      condition: service_healthy

services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "airflow"]
      interval: 10s
      timeout: 5s
      retries: 5

  airflow-init:
    <<: *airflow-common
    user: "0:0"
    entrypoint: /bin/bash
    command:
      - -c
      - |
        pip install apache-airflow-providers-amazon==8.19.0 --quiet
        airflow db migrate
        airflow users create \
          --username admin \
          --firstname Urban \
          --lastname Pulse \
          --role Admin \
          --email admin@urbanpulse.dev \
          --password admin
        echo "==> Airflow init complete"

  airflow-webserver:
    <<: *airflow-common
    command: webserver
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
    restart: always
    

  airflow-scheduler:
    <<: *airflow-common
    command: scheduler
    restart: always

volumes:
  postgres_data:
COMPOSE

echo "==> Stopping any old containers..."
docker compose down -v 2>/dev/null || true

echo "==> Running airflow-init (DB migrate + user create)..."
docker compose up airflow-init --exit-code-from airflow-init

echo "==> Starting Airflow..."
docker compose up -d airflow-webserver airflow-scheduler

echo ""
echo "==> Waiting for Airflow to be ready..."
for i in {1..20}; do
  if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
    echo "==> Airflow is UP at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
    echo "    Login: admin / admin"
    break
  fi
  echo "    Waiting... ($i/20)"
  sleep 10
done
SETUP

chmod +x ~/urbanpulse/setup.sh
bash ~/urbanpulse/setup.sh