output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_a" {
  value = module.networking.public_subnet_a
}

output "public_subnet_b" {
  value = module.networking.public_subnet_b
}

output "ec2_sg_id" {
  value = module.networking.ec2_sg_id
}

output "lambda_role_arn" {
  value = module.iam.lambda_role_arn
}

output "glue_role_arn" {
  value = module.iam.glue_role_arn
}

output "ec2_public_ip" {
  value = module.ec2.ec2_public_ip
}

output "ec2_instance_id" {
  value = module.ec2.ec2_instance_id
}


output "bronze_bucket"        { value = module.s3.bronze_bucket }
output "silver_bucket"        { value = module.s3.silver_bucket }
output "gold_bucket"          { value = module.s3.gold_bucket }
output "lambda_function_name" { value = module.lambda.lambda_function_name }
output "dlq_url"              { value = module.lambda.dlq_url }


output "glue_job_name"     { value = module.glue.bronze_to_silver_job_name }
output "silver_crawler"    { value = module.glue.silver_crawler_name }
output "silver_db"         { value = module.glue.silver_db_name }

output "athena_workgroup"  { value = module.glue.athena_workgroup }
output "gold_crawler"      { value = module.glue.gold_crawler_name }