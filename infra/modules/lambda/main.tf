# Zip the handler code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../ingestion/handler.py"
  output_path = "${path.module}/lambda_handler.zip"
}

resource "aws_lambda_function" "ingest" {
  function_name    = "${var.project}-ingest"
  role             = var.lambda_role_arn
  handler          = "handler.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 300   # 5 min — large Parquet files can be slow
  memory_size      = 256

  environment {
    variables = {
      BRONZE_BUCKET  = var.bronze_bucket
      NYC_TLC_BUCKET = "nyc-tlc"
      ENVIRONMENT    = var.environment
    }
  }

  kms_key_arn = var.kms_key_arn

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project}-ingest"
  retention_in_days = 30
}

# ── EventBridge rule: 1st of every month at 06:00 UTC ─────────────
resource "aws_cloudwatch_event_rule" "monthly_ingest" {
  name                = "${var.project}-monthly-ingest"
  description         = "Trigger NYC TLC ingestion on 1st of month"
  schedule_expression = "cron(0 6 1 * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.monthly_ingest.name
  target_id = "UrbanPulseLambdaTarget"
  arn       = aws_lambda_function.ingest.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly_ingest.arn
}

# ── SQS dead-letter queue for failed invocations ──────────────────
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${var.project}-ingest-dlq"
  message_retention_seconds = 1209600  # 14 days
}

resource "aws_lambda_function_event_invoke_config" "ingest_invoke" {
  function_name = aws_lambda_function.ingest.function_name

  destination_config {
    on_failure {
      destination = aws_sqs_queue.lambda_dlq.arn
    }
  }

  maximum_retry_attempts = 2
}

output "lambda_function_name" { value = aws_lambda_function.ingest.function_name }
output "lambda_function_arn"  { value = aws_lambda_function.ingest.arn }
output "dlq_url"              { value = aws_sqs_queue.lambda_dlq.url }