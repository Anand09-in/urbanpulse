# ── Upload PySpark scripts to S3 ──────────────────────────────────
resource "aws_s3_object" "bronze_to_silver_script" {
  bucket = var.scripts_bucket
  key    = "glue/bronze_to_silver.py"
  source = "${path.module}/../../../transform/bronze_to_silver.py"
  etag   = filemd5("${path.module}/../../../transform/bronze_to_silver.py")
}

# ── Glue Job: Bronze → Silver ─────────────────────────────────────
resource "aws_glue_job" "bronze_to_silver" {
  name         = "${var.project}-bronze-to-silver"
  role_arn     = var.glue_role_arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  number_of_workers = 2          # 2 DPU — stays within free tier

  command {
    script_location = "s3://${var.scripts_bucket}/glue/bronze_to_silver.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "false"
    "--bronze_bucket"                    = var.bronze_bucket
    "--silver_bucket"                    = var.silver_bucket
    "--year"                             = "2026"
    "--month"                            = "01"
    "--TempDir"    = "s3://${var.scripts_bucket}/glue/tmp/"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  timeout = 60   # 60 minutes max
}

# ── Glue Crawler: Silver ───────────────────────────────────────────
resource "aws_glue_crawler" "silver_crawler" {
  name          = "${var.project}-silver-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.silver_db.name

  s3_target {
    path = "s3://${var.silver_bucket}/trips/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })
}

# ── Glue Databases ────────────────────────────────────────────────
resource "aws_glue_catalog_database" "silver_db" {
  name        = "${var.project}_silver"
  description = "UrbanPulse silver layer — cleaned NYC TLC trips"
}

resource "aws_glue_catalog_database" "gold_db" {
  name        = "${var.project}_gold"
  description = "UrbanPulse gold layer — dbt aggregated marts"
}

# ── CloudWatch Log Group for Glue ─────────────────────────────────
resource "aws_cloudwatch_log_group" "glue_logs" {
  name              = "/aws-glue/jobs/${var.project}"
  retention_in_days = 30
}

output "bronze_to_silver_job_name" { value = aws_glue_job.bronze_to_silver.name }
output "silver_crawler_name"       { value = aws_glue_crawler.silver_crawler.name }
output "silver_db_name"            { value = aws_glue_catalog_database.silver_db.name }
output "gold_db_name"              { value = aws_glue_catalog_database.gold_db.name }


# ── Gold Crawler ───────────────────────────────────────────────────
resource "aws_glue_crawler" "gold_crawler" {
  name          = "${var.project}-gold-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.gold_db.name

  catalog_target {
    database_name = aws_glue_catalog_database.gold_db.name
    tables = [
      "mart_zone_hourly_demand",
      "mart_fare_analysis",
      "mart_payment_trends",
      "mart_borough_comparison",
    ]
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

# ── Athena Workgroup ───────────────────────────────────────────────
resource "aws_athena_workgroup" "urbanpulse" {
  name        = "${var.project}-wg"
  description = "UrbanPulse analytics workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.athena_bucket}/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn  = var.kms_key_arn
      }
    }

    # Safety cap — stops runaway queries on free tier
    bytes_scanned_cutoff_per_query = 1073741824  # 1GB max per query
  }
}

# ── Athena Named Queries — saved in console for portfolio ──────────
resource "aws_athena_named_query" "peak_demand_zones" {
  name      = "01_peak_demand_zones"
  workgroup = aws_athena_workgroup.urbanpulse.name
  database  = aws_glue_catalog_database.gold_db.name
  query     = file("${path.module}/../../../analytics/01_peak_demand_zones.sql")
}

resource "aws_athena_named_query" "fare_anomaly" {
  name      = "02_fare_anomaly_detection"
  workgroup = aws_athena_workgroup.urbanpulse.name
  database  = aws_glue_catalog_database.gold_db.name
  query     = file("${path.module}/../../../analytics/02_fare_anomaly_detection.sql")
}

resource "aws_athena_named_query" "borough_revenue" {
  name      = "03_borough_revenue_matrix"
  workgroup = aws_athena_workgroup.urbanpulse.name
  database  = aws_glue_catalog_database.gold_db.name
  query     = file("${path.module}/../../../analytics/03_borough_revenue_matrix.sql")
}

resource "aws_athena_named_query" "tip_behaviour" {
  name      = "04_tip_behaviour_analysis"
  workgroup = aws_athena_workgroup.urbanpulse.name
  database  = aws_glue_catalog_database.gold_db.name
  query     = file("${path.module}/../../../analytics/04_tip_behaviour_analysis.sql")
}

resource "aws_athena_named_query" "payment_shift" {
  name      = "05_payment_method_shift"
  workgroup = aws_athena_workgroup.urbanpulse.name
  database  = aws_glue_catalog_database.gold_db.name
  query     = file("${path.module}/../../../analytics/05_payment_method_shift.sql")
}

# ── Outputs ────────────────────────────────────────────────────────
output "athena_workgroup"     { value = aws_athena_workgroup.urbanpulse.name }
output "gold_crawler_name"    { value = aws_glue_crawler.gold_crawler.name }