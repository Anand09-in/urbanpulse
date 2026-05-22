#!/bin/bash
# Script 1: Invoke Lambda for 3 years of NYC TLC data (2023-01 to 2025-12)
# Run this FIRST — pre-loads all bronze S3 data so DAG freshness checks pass.
# Takes ~3 hours (36 months x 8 min Glue wait).
set -e

FUNCTION_NAME="urbanpulse-ingest"
REGION="ap-south-1"
LOG="/tmp/bulk_ingest_$(date +%Y%m%d_%H%M%S).log"

echo "========================================" | tee -a "$LOG"
echo "Bulk Bronze Ingestion: 2023-01 to 2025-12" | tee -a "$LOG"
echo "Started: $(date)" | tee -a "$LOG"
echo "Log: $LOG" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"

TOTAL=36
COUNT=0

for year in 2023 2024 2025; do
  for month_num in $(seq 1 12); do
    month=$(printf "%02d" $month_num)
    COUNT=$((COUNT + 1))

    echo "" | tee -a "$LOG"
    echo "[$(date '+%H:%M:%S')] ($COUNT/$TOTAL) Invoking Lambda for ${year}-${month}..." | tee -a "$LOG"

    aws lambda invoke \
      --function-name "$FUNCTION_NAME" \
      --payload "{\"year\":\"${year}\",\"month\":\"${month}\"}" \
      --cli-binary-format raw-in-base64-out \
      --region "$REGION" \
      /tmp/lambda_out.json > /dev/null 2>&1

    cat /tmp/lambda_out.json | tee -a "$LOG"

    if grep -q '"errorMessage"' /tmp/lambda_out.json 2>/dev/null; then
      echo "  WARNING: Lambda error for ${year}-${month} — check log" | tee -a "$LOG"
    else
      echo "  OK — Lambda succeeded" | tee -a "$LOG"
    fi

    if [ $COUNT -lt $TOTAL ]; then
      echo "  Waiting 8 min for Glue ETL to complete..." | tee -a "$LOG"
      sleep 480
    fi
  done
done

echo "" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"
echo "Bulk ingestion complete: $(date)" | tee -a "$LOG"
echo "Now run: bash 2_trigger_dags.sh" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"
