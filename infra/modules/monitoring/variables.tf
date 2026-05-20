# infra/modules/monitoring/variables.tf
variable "project"              { type = string }
variable "aws_region"           { type = string }
variable "alert_email"          { type = string }
variable "lambda_function_name" { type = string }
variable "glue_job_name"        { type = string }
variable "bronze_bucket"        { type = string }
variable "silver_bucket"        { type = string }
variable "gold_bucket"          { type = string }
variable "athena_workgroup"     { type = string }