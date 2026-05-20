terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "urbanpulse-tf-state-798644229089"
    key            = "infra/terraform.tfstate"
    region         = "ap-south-1"
    use_lockfile   = true
    encrypt        = true
    profile        = "urbanpulse"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      project     = "urbanpulse"
      environment = var.environment
      managed_by  = "terraform"
    }
  }
}

module "networking" {
  source      = "./modules/networking"
  project     = var.project
  aws_region  = var.aws_region
  my_ip_cidr  = var.my_ip_cidr   # add this to variables.tf
}

module "iam" {
  source      = "./modules/iam"
  project     = var.project
  kms_key_arn = module.s3.kms_key_arn
}

module "ec2" {
  source           = "./modules/ec2"
  project          = var.project
  public_subnet_id = module.networking.public_subnet_a
  ec2_sg_id        = module.networking.ec2_sg_id
  public_key_path  = "~/.ssh/urbanpulse.pub"
  github_username  = var.github_username  
  github_repo      = var.github_repo      
}

module "s3" {
  source     = "./modules/s3"
  project    = var.project
  aws_region = var.aws_region
}

module "lambda" {
  source           = "./modules/lambda"
  project          = var.project
  environment      = var.environment
  lambda_role_arn  = module.iam.lambda_role_arn
  bronze_bucket    = module.s3.bronze_bucket
  kms_key_arn      = module.s3.kms_key_arn
}

module "glue" {
  source         = "./modules/glue"
  project        = var.project
  glue_role_arn  = module.iam.glue_role_arn
  bronze_bucket  = module.s3.bronze_bucket
  silver_bucket  = module.s3.silver_bucket
  gold_bucket    = module.s3.gold_bucket
  scripts_bucket = module.s3.scripts_bucket
  athena_bucket  = module.s3.athena_bucket   # NEW
  kms_key_arn    = module.s3.kms_key_arn     # NEW
}

module "oidc" {
  source          = "./modules/oidc"
  project         = var.project
  github_username = var.github_username
  github_repo     = var.github_repo
}