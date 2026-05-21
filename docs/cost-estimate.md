# UrbanPulse — AWS cost estimate

Environment: dev | Region: ap-south-1 | Period: monthly

## Free tier usage

| Service | Usage | Free tier limit | Monthly cost |
|---|---|---|---|
| S3 storage | ~2GB across 5 buckets | 5GB | $0.00 |
| S3 requests | ~10K PUT/GET | 20K | $0.00 |
| Lambda invocations | ~35/month | 1M | $0.00 |
| Lambda duration | ~300s @ 256MB | 400K GB-seconds | $0.00 |
| Glue Data Catalog | 4 tables | 1M objects | $0.00 |
| Glue Crawlers | 2 runs/month | included | $0.00 |
| CloudWatch alarms | 6 alarms | 10 alarms free | $0.00 |
| CloudWatch logs | ~500MB | 5GB | $0.00 |
| SQS (DLQ) | <1K msgs/month | 1M msgs | $0.00 |
| EventBridge | 1 rule, 12 events/year | 14M events | $0.00 |
| SNS email alerts | ~5 emails/month | first 1K free | $0.00 |

## Pay-per-use (small amounts)

| Service | Usage | Rate | Monthly cost |
|---|---|---|---|
| EC2 c7i-flex.large | 730 hrs (Airflow host) | free tier | $0.00 |
| Glue ETL | ~2 DPU-hrs/month (G.1X × 2 workers) | $0.44/DPU-hr | ~$0.88 |
| Athena queries | ~50 queries @ 100MB avg | $5/TB | ~$0.03 |
| KMS key | 1 key | $1.00/key/month | $1.00 |
| KMS API calls | ~500 requests | $0/20K free | $0.00 |

## Total estimated monthly cost

| Environment | Cost |
|---|---|
| Dev (current) | **~$1.91/month** |
| Prod (scaled) | ~$45–80/month |

## Cost optimisation decisions made

- Glue instead of EMR (~$80 saving)
- Lambda instead of Kinesis Firehose (~$15 saving)
- S3 native locking instead of DynamoDB (no extra cost)
- S3 lifecycle policy moves Bronze to Glacier after 90 days
- Athena workgroup has 1GB per-query scan limit
- Glue job uses 2 DPU (minimum) not default 10
- Elastic IP free while instance is running (no idle cost)

