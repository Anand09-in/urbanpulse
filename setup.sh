cat > setup.sh << 'EOF'
#!/bin/bash
set -e

echo "==> Setting up UrbanPulse Airflow on EC2..."
mkdir -p ~/urbanpulse/{dags,logs,plugins}
cd ~/urbanpulse

# .env file
cat > .env << ENV
AIRFLOW_UID=50000
AIRFLOW_GID=0
AWS_DEFAULT_REGION=ap-south-1
_AIRFLOW_WWW_USER_USERNAME=admin
_AIRFLOW_WWW_USER_PASSWORD=admin
ENV

echo "==> Stopping old containers if any..."
docker compose down 2>/dev/null || true

echo "==> Starting Airflow services..."
docker compose up -d 

echo "==> Done. Airflow starting at port 8080"
EOF

chmod +x setup.sh