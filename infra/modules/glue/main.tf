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