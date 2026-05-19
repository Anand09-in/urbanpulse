variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "urbanpulse"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "urbanpulse"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR, e.g. 203.0.113.5/32"
  type        = string
    default     = "122.172.84.221/32"
}

# NEW — needed for git clone in user_data
variable "github_username" {
  type        = string
  description = "Your GitHub username e.g. johndoe"
    default     = "Anand09-in"
}

variable "github_repo" {
  type        = string
  description = "Repo name e.g. urbanpulse"
  default     = "urbanpulse"
}