data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  bucket_prefix = "${var.name}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
  tags          = merge(var.tags, { SolutionId = var.solution_id })
}

################################################################################
# Access log bucket (S3 server access logs + CloudFront standard logs)
################################################################################

resource "aws_s3_bucket" "logs" {
  bucket        = "${local.bucket_prefix}-logs"
  force_destroy = !var.enable_deletion_protection

  tags = local.tags
}

# CloudFront standard (legacy) logging writes with ACLs, so ownership must allow ObjectWriter.
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  bucket = aws_s3_bucket.logs.id
  acl    = "log-delivery-write"

  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_log_retention_in_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.tls_only["logs"].json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

################################################################################
# Scenarios bucket (test scripts, results, start signals, JMeter bundle)
################################################################################

resource "aws_s3_bucket" "scenarios" {
  bucket        = "${local.bucket_prefix}-scenarios"
  force_destroy = !var.enable_deletion_protection

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "scenarios" {
  bucket = aws_s3_bucket.scenarios.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "scenarios" {
  bucket = aws_s3_bucket.scenarios.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scenarios" {
  bucket = aws_s3_bucket.scenarios.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "scenarios" {
  bucket = aws_s3_bucket.scenarios.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_logging" "scenarios" {
  bucket = aws_s3_bucket.scenarios.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "scenarios-bucket-access/"
}

# The console uploads scripts and reads results directly from the browser.
resource "aws_s3_bucket_cors_configuration" "scenarios" {
  count = length(var.console_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.scenarios.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "HEAD"]
    allowed_origins = var.console_origins
    expose_headers  = ["ETag"]
  }
}

resource "aws_s3_bucket_policy" "scenarios" {
  bucket = aws_s3_bucket.scenarios.id
  policy = data.aws_iam_policy_document.tls_only["scenarios"].json

  depends_on = [aws_s3_bucket_public_access_block.scenarios]
}

data "aws_iam_policy_document" "tls_only" {
  for_each = {
    logs      = aws_s3_bucket.logs.arn
    scenarios = aws_s3_bucket.scenarios.arn
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value, "${each.value}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# JMeter + plugins bundle; the load tester downloads it for jmeter and "simple" tests.
# Replaces the upstream CopyJMeterBundle custom resource.
resource "aws_s3_object" "jmeter_bundle" {
  bucket      = aws_s3_bucket.scenarios.id
  key         = "frameworks/jmeter/jmeter-bundle.tgz"
  source      = var.jmeter_bundle_path
  source_hash = filemd5(var.jmeter_bundle_path)

  tags = local.tags

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.scenarios]
}

################################################################################
# DynamoDB tables
################################################################################

resource "aws_dynamodb_table" "scenarios" {
  name                        = "${var.name}-scenarios"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "testId"
  deletion_protection_enabled = var.enable_deletion_protection

  attribute {
    name = "testId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = local.tags
}

resource "aws_dynamodb_table" "history" {
  name                        = "${var.name}-history"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "testId"
  range_key                   = "testRunId"
  deletion_protection_enabled = var.enable_deletion_protection

  attribute {
    name = "testId"
    type = "S"
  }

  attribute {
    name = "testRunId"
    type = "S"
  }

  attribute {
    name = "startTime"
    type = "S"
  }

  global_secondary_index {
    name               = local.history_gsi_name
    projection_type    = "INCLUDE"
    non_key_attributes = ["testRunId", "endTime", "status", "results"]

    key_schema {
      attribute_name = "testId"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "startTime"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = local.tags
}

# DevOps Agent integration tables (agent spaces and investigations).
resource "aws_dynamodb_table" "agent_spaces" {
  name                        = "${var.name}-agent-spaces"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "id"
  deletion_protection_enabled = var.enable_deletion_protection

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = local.tags
}

resource "aws_dynamodb_table" "investigations" {
  name                        = "${var.name}-investigations"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "testId"
  range_key                   = "testRunId#investigationId"
  deletion_protection_enabled = var.enable_deletion_protection

  attribute {
    name = "testId"
    type = "S"
  }

  attribute {
    name = "testRunId#investigationId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = local.tags
}

locals {
  history_gsi_name = "testId-startTime-index"
}
