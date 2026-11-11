data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  tags       = merge(var.tags, { SolutionId = var.solution_id })

  cognito_origin = "https://${var.cognito_domain_host}"

  # Upstream CSP plus the Cognito hosted-domain origin on the four directives the
  # UpdateCsp custom resource patches after deploy. Here it is known up front.
  csp = join(" ", [
    "default-src 'self' https://*.amazonaws.com ${local.cognito_origin};",
    "upgrade-insecure-requests;",
    "script-src 'self' https://*.amazonaws.com ${local.cognito_origin};",
    "style-src 'self' 'unsafe-inline' https://*.amazonaws.com;",
    "img-src 'self' data: https://*.amazonaws.com;",
    "font-src 'self' data:;",
    "connect-src 'self' https://*.amazonaws.com wss://*.amazonaws.com ${join(" ", var.csp_connect_src_extra)} ${local.cognito_origin};",
    "frame-src 'self' https://*.amazonaws.com;",
    "frame-ancestors 'self' https://*.amazonaws.com;",
    "object-src 'none';",
    "base-uri 'self';",
    "form-action 'self' https://*.amazonaws.com ${local.cognito_origin};",
  ])

  content_types = {
    css   = "text/css"
    html  = "text/html"
    ico   = "image/x-icon"
    js    = "application/javascript"
    json  = "application/json"
    map   = "application/json"
    png   = "image/png"
    svg   = "image/svg+xml"
    txt   = "text/plain"
    woff  = "font/woff"
    woff2 = "font/woff2"
  }

  webui_files = {
    for f in fileset(var.webui_dir, "**") : f => {
      path         = "${var.webui_dir}/${f}"
      content_type = lookup(local.content_types, reverse(split(".", f))[0], "application/octet-stream")
    }
    if f != "aws-exports.json"
  }

  # Changes when any asset or the runtime config changes; drives the invalidation action.
  release_hash = sha256(join("", concat(
    [for f in sort(keys(local.webui_files)) : filesha256(local.webui_files[f].path)],
    [jsonencode(var.runtime_config)],
  )))
}

################################################################################
# Console bucket (private, served only through CloudFront OAC)
################################################################################

resource "aws_s3_bucket" "console" {
  bucket        = "${var.name}-${local.account_id}-${data.aws_region.current.region}-console"
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "console" {
  bucket = aws_s3_bucket.console.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "console" {
  bucket = aws_s3_bucket.console.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "console" {
  bucket = aws_s3_bucket.console.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "console" {
  bucket = aws_s3_bucket.console.id

  rule {
    id     = "expire-old-releases"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_logging" "console" {
  bucket = aws_s3_bucket.console.id

  target_bucket = var.logs_bucket_id
  target_prefix = "console-bucket-access/"
}

data "aws_iam_policy_document" "console" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.console.arn, "${aws_s3_bucket.console.arn}/*"]

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

  statement {
    sid       = "CloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.console.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }

  # Lets CloudFront return 404 (not 403) for missing keys, which the SPA fallback maps to index.html.
  statement {
    sid       = "CloudFrontList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.console.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "console" {
  bucket = aws_s3_bucket.console.id
  policy = data.aws_iam_policy_document.console.json

  depends_on = [aws_s3_bucket_public_access_block.console]
}

################################################################################
# CloudFront
################################################################################

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-console"
  description                       = "DLT console bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "this" {
  name    = "${var.name}-${data.aws_region.current.region}-rhp"
  comment = "Security headers policy for DLT console"

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      override = true
      value    = "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
    }

    items {
      header   = "Cross-Origin-Resource-Policy"
      override = true
      value    = "same-origin"
    }
  }

  security_headers_config {
    content_security_policy {
      content_security_policy = local.csp
      override                = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 47304000
      include_subdomains         = true
      override                   = true
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  comment             = "Website distribution for the Distributed Load Testing solution"
  default_root_object = "index.html"
  enabled             = true
  http_version        = "http2"
  is_ipv6_enabled     = true
  price_class         = var.price_class
  web_acl_id          = var.web_acl_arn

  origin {
    domain_name              = aws_s3_bucket.console.bucket_regional_domain_name
    origin_id                = "console-bucket"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id
    target_origin_id           = "console-bucket"
    viewer_protocol_policy     = "redirect-to-https"
  }

  # SPA routing: unknown paths return index.html.
  dynamic "custom_error_response" {
    for_each = [403, 404]

    content {
      error_code         = custom_error_response.value
      response_code      = 200
      response_page_path = "/index.html"
    }
  }

  logging_config {
    bucket          = var.logs_bucket_regional_domain_name
    include_cookies = false
    prefix          = "cloudfront-logs/"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

################################################################################
# Assets and runtime config
# Replaces the upstream BucketDeployment and aws-exports custom resources.
################################################################################

resource "aws_s3_object" "webui" {
  for_each = local.webui_files

  bucket       = aws_s3_bucket.console.id
  key          = each.key
  source       = each.value.path
  source_hash  = filemd5(each.value.path)
  content_type = each.value.content_type
  # index.html must not be cached so new hashed bundles are picked up immediately.
  cache_control = each.key == "index.html" ? "no-cache" : "public, max-age=31536000, immutable"

  tags = local.tags
}

resource "aws_s3_object" "aws_exports" {
  bucket        = aws_s3_bucket.console.id
  key           = "aws-exports.json"
  content       = jsonencode(var.runtime_config)
  content_type  = "application/json"
  cache_control = "no-cache"

  tags = local.tags
}

# Terraform action (TF >= 1.14): invalidate CloudFront after assets or config change.
action "aws_cloudfront_create_invalidation" "this" {
  config {
    distribution_id = aws_cloudfront_distribution.this.id
    paths           = ["/*"]
  }
}

resource "terraform_data" "release" {
  input = local.release_hash

  lifecycle {
    action_trigger {
      events  = [after_create, after_update]
      actions = [action.aws_cloudfront_create_invalidation.this]
    }
  }

  depends_on = [aws_s3_object.webui, aws_s3_object.aws_exports]
}
