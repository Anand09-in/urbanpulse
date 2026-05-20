# ── SNS Topic — all alerts go here ────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ──────────────────────────────────────────────────────────────────
# LAMBDA ALARMS
# ──────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project}-lambda-errors"
  alarm_description   = "Lambda ingestion function errored"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.lambda_function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.project}-lambda-duration"
  alarm_description   = "Lambda running close to 5min timeout"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  dimensions          = { FunctionName = var.lambda_function_name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 240000   # 4 min — warns before 5min timeout
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ──────────────────────────────────────────────────────────────────
# GLUE JOB ALARMS
# ──────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "glue_failed" {
  alarm_name          = "${var.project}-glue-job-failed"
  alarm_description   = "Glue ETL job failed"
  namespace           = "Glue"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  dimensions          = { JobName = var.glue_job_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "glue_duration" {
  alarm_name          = "${var.project}-glue-job-duration"
  alarm_description   = "Glue job taking longer than expected"
  namespace           = "Glue"
  metric_name         = "glue.driver.aggregate.elapsedTime"
  dimensions          = { JobName = var.glue_job_name }
  statistic           = "Maximum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 2700000   # 45 minutes in ms
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ──────────────────────────────────────────────────────────────────
# S3 BRONZE FRESHNESS ALARM
# Fires if no new objects land in Bronze after 26 hours
# ──────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "bronze_not_updated" {
  alarm_name          = "${var.project}-bronze-not-updated"
  alarm_description   = "No new data in Bronze S3 — ingestion may have failed"
  namespace           = "AWS/S3"
  metric_name         = "NumberOfObjects"
  dimensions = {
    BucketName  = var.bronze_bucket
    StorageType = "AllStorageTypes"
  }
  statistic           = "Average"
  period              = 86400     # check daily
  evaluation_periods  = 1
  threshold           = 3         # bronze should always have > 3 objects
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ──────────────────────────────────────────────────────────────────
# ATHENA ALARM — cost safety
# ──────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "athena_data_scanned" {
  alarm_name          = "${var.project}-athena-high-scan"
  alarm_description   = "Athena scanning unusually large amounts — check queries"
  namespace           = "AWS/Athena"
  metric_name         = "DataScannedInBytes"
  dimensions          = { WorkGroup = var.athena_workgroup }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 5368709120   # 5GB per hour
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ──────────────────────────────────────────────────────────────────
# CLOUDWATCH DASHBOARD
# ──────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "urbanpulse" {
  dashboard_name = "${var.project}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1 — Lambda
      {
        type       = "metric"
        x = 0
        y = 0
        width = 8
        height = 6
        properties = {
          title   = "Lambda — Invocations & Errors"
          view    = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName",
             var.lambda_function_name, { stat = "Sum", color = "#2ca02c" }],
            ["AWS/Lambda", "Errors",      "FunctionName",
             var.lambda_function_name, { stat = "Sum", color = "#d62728" }],
          ]
          period = 300
          region = var.aws_region
        }
      },
      {
        type       = "metric"
        x = 8
        y = 0
        width = 8
        height = 6
        properties = {
          title   = "Lambda — Duration (ms)"
          view    = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName",
             var.lambda_function_name,
             { stat = "Maximum", color = "#ff7f0e" }],
            ["AWS/Lambda", "Duration", "FunctionName",
             var.lambda_function_name,
             { stat = "Average", color = "#1f77b4" }],
          ]
          period = 300
          region = var.aws_region
        }
      },
      {
        type       = "alarm"
        x = 16
        y = 0
        width = 8
        height = 6
        properties = {
          title  = "Active Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.lambda_errors.arn,
            aws_cloudwatch_metric_alarm.lambda_duration.arn,
            aws_cloudwatch_metric_alarm.glue_failed.arn,
            aws_cloudwatch_metric_alarm.glue_duration.arn,
            aws_cloudwatch_metric_alarm.bronze_not_updated.arn,
            aws_cloudwatch_metric_alarm.athena_data_scanned.arn,
          ]
        }
      },
      # Row 2 — Glue
      {
        type       = "metric"
        x = 0
        y = 6
        width = 12
        height = 6
        properties = {
          title   = "Glue — Job Run Status"
          view    = "timeSeries"
          metrics = [
            ["Glue", "glue.driver.aggregate.numCompletedTasks",
             "JobName", var.glue_job_name,
             { stat = "Sum", color = "#2ca02c", label = "Completed" }],
            ["Glue", "glue.driver.aggregate.numFailedTasks",
             "JobName", var.glue_job_name,
             { stat = "Sum", color = "#d62728", label = "Failed" }],
          ]
          period = 300
          region = var.aws_region
        }
      },
      {
        type       = "metric"
        x = 12
        y = 6
        width = 12
        height = 6
        properties = {
          title   = "Athena — Data Scanned (Bytes)"
          view    = "timeSeries"
          metrics = [
            ["AWS/Athena", "DataScannedInBytes",
             "WorkGroup", var.athena_workgroup,
             { stat = "Sum", color = "#9467bd" }],
          ]
          period = 3600
          region = var.aws_region
        }
      },
      # Row 3 — S3
      {
        type       = "metric"
        x = 0
        y = 12
        width = 24
        height = 6
        properties = {
          title   = "S3 — Object Count per Medallion Layer"
          view    = "timeSeries"
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName",
             var.bronze_bucket, "StorageType", "AllStorageTypes",
             { stat = "Average", color = "#cd7f32", label = "Bronze" }],
            ["AWS/S3", "NumberOfObjects", "BucketName",
             var.silver_bucket, "StorageType", "AllStorageTypes",
             { stat = "Average", color = "#c0c0c0", label = "Silver" }],
            ["AWS/S3", "NumberOfObjects", "BucketName",
             var.gold_bucket, "StorageType", "AllStorageTypes",
             { stat = "Average", color = "#ffd700", label = "Gold" }],
          ]
          period = 86400
          region = var.aws_region
        }
      },
    ]
  })
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.urbanpulse.dashboard_name}"
}

output "sns_topic_arn" { value = aws_sns_topic.alerts.arn }