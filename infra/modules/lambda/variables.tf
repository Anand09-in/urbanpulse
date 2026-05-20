# infra/modules/lambda/variables.tf
variable "project"          { type = string }
variable "environment"      { type = string }
variable "lambda_role_arn"  { type = string }
variable "bronze_bucket"    { type = string }
variable "kms_key_arn"      { type = string }