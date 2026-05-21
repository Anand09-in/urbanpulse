#!/bin/bash
set -e

echo "==> Setting up UrbanPulse Airflow on EC2..."
mkdir -p ~/urbanpulse/{logs,plugins}
cd ~/urbanpulse

cat > .env << ENV
AIRFLOW_UID=50000
AIRFLOW_GID=0
AWS_DEFAULT_REGION=ap-south-1
_AIRFLOW_WWW_USER_USERNAME=admin
_AIRFLOW_WWW_USER_PASSWORD=admin
ENV

echo "==> Stopping old containers if any..."
docker-compose down 2>/dev/null || true

echo "==> Initialising Airflow DB and admin user..."
docker-compose run --rm airflow-init

echo "==> Starting Airflow services..."
docker-compose up -d airflow-webserver airflow-scheduler

echo "==> Done. Airflow will be ready at :8080 in ~60s"
