# GitHub's OIDC provider — allows GitHub Actions to
# assume AWS roles without storing any access keys
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint (stable, won't change)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM role that GitHub Actions assumes via OIDC
resource "aws_iam_role" "github_actions" {
  name = "${var.project}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # Only YOUR repo can assume this role
            "token.actions.githubusercontent.com:sub" : "repo:${var.github_username}/${var.github_repo}:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# What GitHub Actions is allowed to do
resource "aws_iam_role_policy" "github_actions_policy" {
  name = "github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject",
                  "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::urbanpulse-tf-state-798644229089",
          "arn:aws:s3:::urbanpulse-tf-state-798644229089/*"
        ]
      },
      {
        Sid    = "DeployScripts"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::urbanpulse-scripts",
          "arn:aws:s3:::urbanpulse-scripts/*"
        ]
      },
      {
        Sid    = "ManageInfra"
        Effect = "Allow"
        Action = [
          "lambda:*", "glue:*", "athena:*",
          "s3:*", "iam:*", "ec2:*",
          "logs:*", "events:*", "sqs:*",
          "sns:*", "cloudwatch:*",
          "kms:Describe*", "kms:List*", "kms:Get*",
          "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext",
          "kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*", "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}