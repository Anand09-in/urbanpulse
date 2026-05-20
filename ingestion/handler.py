import boto3
import logging
import os
import urllib.request
import urllib.error
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

TLC_BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data"
BRONZE_BUCKET = os.environ.get("BRONZE_BUCKET", "urbanpulse-bronze")

SOURCES = {
    "yellow": "yellow_tripdata_{year}-{month}.parquet",
    "green":  "green_tripdata_{year}-{month}.parquet",
    "fhv":    "fhv_tripdata_{year}-{month}.parquet",
}


def get_target_period(event: dict) -> tuple[str, str]:
    if "year" in event and "month" in event:
        return event["year"], event["month"]

    # Default: previous month (TLC publishes with ~2 month lag)
    today = datetime.utcnow().replace(day=1) - timedelta(days=1)
    return str(today.year), str(today.month).zfill(2)


def download_to_bronze(url: str, dest_key: str) -> dict:
    # HEAD check first — avoids downloading a file that doesn't exist yet
    try:
        urllib.request.urlopen(urllib.request.Request(url, method="HEAD"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            logger.warning(f"File not found: {url}")
            return {"source": url, "status": "not_found"}
        raise

    # Stream directly from HTTPS into S3 — no disk I/O
    with urllib.request.urlopen(url) as response:
        s3.upload_fileobj(
            response,
            BRONZE_BUCKET,
            dest_key,
            ExtraArgs={"ServerSideEncryption": "aws:kms"},
        )

    logger.info(f"Uploaded: {url} → s3://{BRONZE_BUCKET}/{dest_key}")
    return {"source": url, "status": "success"}


def handler(event, context):
    year, month = get_target_period(event)
    logger.info(f"Starting ingestion for {year}-{month}")

    results = []

    for taxi_type, filename_template in SOURCES.items():
        filename = filename_template.format(year=year, month=month)
        url = f"{TLC_BASE_URL}/{filename}"
        dest_key = f"year={year}/month={month}/source={taxi_type}/data.parquet"
        result = download_to_bronze(url, dest_key)
        result["taxi_type"] = taxi_type
        results.append(result)

    success = [r for r in results if r["status"] == "success"]
    failed  = [r for r in results if r["status"] != "success"]

    logger.info(f"Ingestion complete: {len(success)} success, {len(failed)} not found")

    return {
        "statusCode": 200,
        "period": f"{year}-{month}",
        "results": results,
        "summary": {
            "success": len(success),
            "not_found": len(failed),
        }
    }
