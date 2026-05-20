# infra/modules/glue/variables.tf
variable "project"        { type = string }
variable "glue_role_arn"  { type = string }
variable "bronze_bucket"  { type = string }
variable "silver_bucket"  { type = string }
variable "gold_bucket"    { type = string }
variable "scripts_bucket" { type = string }