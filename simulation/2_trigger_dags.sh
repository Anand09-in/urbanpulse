#!/bin/bash
# Script 2: Trigger one Airflow DAG run per month (2023-01 to 2025-12).
# Waits for each run to complete before triggering the next.
# Run AFTER 1_bulk_ingest_bronze.sh finishes.
# Takes ~6-10 hours depending on Glue + dbt duration per run.

AIRFLOW_URL="http://43.205.149.168:8080"
DAG_ID="urbanpulse_daily_pipeline"
AIRFLOW_USER="admin"
AIRFLOW_PASS="admin"
LOG="/tmp/dag_trigger_$(date +%Y%m%d_%H%M%S).log"
POLL_INTERVAL=60    # seconds between state checks
TIMEOUT=2700        # 45 min max per DAG run

echo "========================================" | tee -a "$LOG"
echo "DAG Trigger Simulation: 2023-01 to 2025-12" | tee -a "$LOG"
echo "Started: $(date)" | tee -a "$LOG"
echo "Airflow: $AIRFLOW_URL" | tee -a "$LOG"
echo "Log: $LOG" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"

wait_for_dag() {
  local run_id="$1"
  local elapsed=0
  # URL-encode the + sign in the run_id for the API call
  local encoded_id
  encoded_id=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${run_id}', safe=''))")

  while [ $elapsed -lt $TIMEOUT ]; do
    state=$(curl -s \
      -u "${AIRFLOW_USER}:${AIRFLOW_PASS}" \
      "${AIRFLOW_URL}/api/v1/dags/${DAG_ID}/dagRuns/${encoded_id}" \
      | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)

    echo "  [$(date '+%H:%M:%S')] state=${state}" | tee -a "$LOG"

    case "$state" in
      success) return 0 ;;
      failed)  echo "  DAG run FAILED" | tee -a "$LOG"; return 1 ;;
    esac

    sleep $POLL_INTERVAL
    elapsed=$((elapsed + POLL_INTERVAL))
  done

  echo "  TIMEOUT after ${TIMEOUT}s — moving on" | tee -a "$LOG"
  return 1
}

TOTAL=36
COUNT=0
PASSED=0
FAILED=0

for year in 2023 2024 2025; do
  for month_num in $(seq 1 12); do
    month=$(printf "%02d" $month_num)
    COUNT=$((COUNT + 1))
    logical_date="${year}-${month}-01T00:00:00Z"

    echo "" | tee -a "$LOG"
    echo "[$(date '+%H:%M:%S')] ($COUNT/$TOTAL) Triggering DAG for ${year}-${month}..." | tee -a "$LOG"

    response=$(curl -s -X POST \
      "${AIRFLOW_URL}/api/v1/dags/${DAG_ID}/dagRuns" \
      -H "Content-Type: application/json" \
      -u "${AIRFLOW_USER}:${AIRFLOW_PASS}" \
      -d "{\"logical_date\": \"${logical_date}\"}")

    echo "  Response: $response" | tee -a "$LOG"

    # Handle 409 Conflict (run already exists)
    if echo "$response" | grep -q '"status":409'; then
      echo "  SKIP — DAG run for ${logical_date} already exists" | tee -a "$LOG"
      continue
    fi

    run_id=$(echo "$response" | grep -o '"dag_run_id":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$run_id" ]; then
      echo "  ERROR — could not get dag_run_id, skipping" | tee -a "$LOG"
      FAILED=$((FAILED + 1))
      continue
    fi

    echo "  run_id: $run_id" | tee -a "$LOG"
    echo "  Waiting for completion (poll every ${POLL_INTERVAL}s, timeout ${TIMEOUT}s)..." | tee -a "$LOG"

    if wait_for_dag "$run_id"; then
      PASSED=$((PASSED + 1))
      echo "  SUCCESS" | tee -a "$LOG"
    else
      FAILED=$((FAILED + 1))
      echo "  Moving on despite failure..." | tee -a "$LOG"
    fi

    # Brief pause between runs
    sleep 30
  done
done

echo "" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"
echo "Simulation complete: $(date)" | tee -a "$LOG"
echo "Results: $PASSED passed, $FAILED failed out of $TOTAL" | tee -a "$LOG"
echo "========================================" | tee -a "$LOG"
