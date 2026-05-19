# infra/modules/ec2/variables.tf
variable "project"          { type = string }
variable "public_subnet_id" { type = string }
variable "ec2_sg_id"        { type = string }
variable "public_key_path"  {
  type    = string
  default = "~/.ssh/urbanpulse.pub"
}

# NEW — needed for git clone in user_data
variable "github_username" {
  type        = string
}

variable "github_repo" {
  type        = string
  }