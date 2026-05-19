# infra/modules/networking/variables.tf
variable "project"     { type = string }
variable "aws_region"  { type = string }
variable "my_ip_cidr"  {
  type        = string
  description = "Your local IP in CIDR format e.g. 122.172.84.221/32"
  default = "122.172.84.221/32"
}