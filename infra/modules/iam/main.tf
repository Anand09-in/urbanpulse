# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_s3" {
  name   = "lambda-s3-policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:HeadObject", "s3:PutObject", "s3:CopyObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::urbanpulse-bronze",
          "arn:aws:s3:::urbanpulse-bronze/*",
          "arn:aws:s3:::nyc-tlc",
          "arn:aws:s3:::nyc-tlc/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = "arn:aws:sqs:*:*:${var.project}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# Glue execution role
resource "aws_iam_role" "glue_role" {
  name = "${var.project}-glue-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  name   = "glue-s3-policy"
  role   = aws_iam_role.glue_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::urbanpulse-bronze", "arn:aws:s3:::urbanpulse-bronze/*",
        "arn:aws:s3:::urbanpulse-silver", "arn:aws:s3:::urbanpulse-silver/*",
        "arn:aws:s3:::urbanpulse-gold",   "arn:aws:s3:::urbanpulse-gold/*",
        "arn:aws:s3:::urbanpulse-scripts","arn:aws:s3:::urbanpulse-scripts/*"
      ]
    },
    {
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      Resource = var.kms_key_arn
    }]
  })
}

output "lambda_role_arn" { value = aws_iam_role.lambda_role.arn }
output "glue_role_arn"   { value = aws_iam_role.glue_role.arn }