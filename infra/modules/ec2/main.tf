# Find latest Amazon Linux 2023 AMI automatically
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "airflow" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "c7i-flex.large"  # 2 vCPU, 4GB RAM - free tier eligible
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.ec2_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = aws_key_pair.urbanpulse.key_name

  root_block_device {
    volume_size = 30       # minimum required by Amazon Linux 2023 AMI snapshot
    volume_type = "gp2"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # ── 1. System prerequisites ────────────────────────────────────
    yum update -y
    yum install -y docker git python3-pip curl
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user

    # ── 2. Docker Compose v2 ───────────────────────────────────────
    curl -SL https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64 \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # ── 3. Clone repo as ec2-user ──────────────────────────────────
    sudo -u ec2-user bash << 'USERSCRIPT'
      git clone https://github.com/Anand09-in/urbanpulse.git \
        /home/ec2-user/urbanpulse
      cd /home/ec2-user/urbanpulse

      # ── 4. Run setup.sh from repo ────────────────────────────────
      chmod +x setup.sh
      bash setup.sh
    USERSCRIPT
  EOF


  tags = { Name = "${var.project}-airflow-ec2" }
}

# EC2 needs an IAM instance profile to talk to S3, Glue, Lambda
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.project}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2-airflow-policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*",
          "glue:StartJobRun", "glue:GetJobRun", "glue:StartCrawler", "glue:GetCrawler",
          "lambda:InvokeFunction",
          "athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults",
          "logs:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# SSH key pair — generated locally, public key uploaded to AWS
resource "aws_key_pair" "urbanpulse" {
  key_name   = "${var.project}-keypair"
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_eip" "airflow" {
  instance = aws_instance.airflow.id
  domain   = "vpc"
}

output "ec2_public_ip"   { value = aws_eip.airflow.public_ip }
output "ec2_instance_id" { value = aws_instance.airflow.id }