# ── KMS key for all bucket encryption ─────────────────────────────
resource "aws_kms_key" "urbanpulse" {
  description             = "UrbanPulse S3 encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "urbanpulse" {
  name          = "alias/urbanpulse-s3"
  target_key_id = aws_kms_key.urbanpulse.key_id
}

# ── Reusable local for bucket config ──────────────────────────────
locals {
  buckets = {
    bronze  = "${var.project}-bronze"
    silver  = "${var.project}-silver"
    gold    = "${var.project}-gold"
    scripts = "${var.project}-scripts"
    athena  = "${var.project}-athena-results"
  }
}

# ── Create all 5 buckets ──────────────────────────────────────────
resource "aws_s3_bucket" "buckets" {
  for_each      = local.buckets
  bucket        = each.value
  force_destroy = true
}

# ── Versioning on bronze + silver + gold only ─────────────────────
resource "aws_s3_bucket_versioning" "versioning" {
  for_each = { for k, v in local.buckets : k => v
               if contains(["bronze","silver","gold"], k) }
  bucket   = aws_s3_bucket.buckets[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── KMS encryption on all buckets ─────────────────────────────────
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.buckets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.urbanpulse.arn
    }
    bucket_key_enabled = true
  }
}

# ── Block all public access on all buckets ─────────────────────────
resource "aws_s3_bucket_public_access_block" "block" {
  for_each                = local.buckets
  bucket                  = aws_s3_bucket.buckets[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Lifecycle: Bronze raw files → Glacier after 90 days ───────────
resource "aws_s3_bucket_lifecycle_configuration" "bronze_lifecycle" {
  bucket = aws_s3_bucket.buckets["bronze"].id

  rule {
    id     = "archive-raw-to-glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    filter { prefix = "" }
  }
}

# ── Lifecycle: Athena results expire after 30 days ─────────────────
resource "aws_s3_bucket_lifecycle_configuration" "athena_lifecycle" {
  bucket = aws_s3_bucket.buckets["athena"].id

  rule {
    id     = "expire-athena-results"
    status = "Enabled"
    expiration { days = 30 }
    filter { prefix = "" }
  }
}

# ── Upload Zone Lookup reference file ─────────────────────────────
resource "aws_s3_object" "zone_lookup" {
  bucket = aws_s3_bucket.buckets["bronze"].id
  key    = "reference/taxi_zone_lookup.csv"
  source = "${path.module}/../../../data/taxi_zone_lookup.csv"
  etag   = filemd5("${path.module}/../../../data/taxi_zone_lookup.csv")
}

# ── Outputs used by Lambda + Glue modules ─────────────────────────
output "bronze_bucket"  { value = aws_s3_bucket.buckets["bronze"].id }
output "silver_bucket"  { value = aws_s3_bucket.buckets["silver"].id }
output "gold_bucket"    { value = aws_s3_bucket.buckets["gold"].id }
output "scripts_bucket" { value = aws_s3_bucket.buckets["scripts"].id }
output "athena_bucket"  { value = aws_s3_bucket.buckets["athena"].id }
output "kms_key_arn"    { value = aws_kms_key.urbanpulse.arn }