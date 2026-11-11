data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  tags       = merge(var.tags, { SolutionId = var.solution_id })

  # Federated principal and condition-key prefix differ in GovCloud.
  identity_principal = (
    local.partition != "aws-us-gov" ? "cognito-identity.amazonaws.com" :
    local.region == "us-gov-east-1" ? "cognito-identity.us-gov-east-1.amazonaws.com" :
    "cognito-identity-us-gov.amazonaws.com"
  )

  # Console origins are listed with and without a trailing slash, as upstream does.
  oauth_urls = distinct(concat(
    flatten([for u in var.console_urls : [u, "${u}/"]]),
    var.additional_callback_urls,
  ))

  invite_console_line = length(var.console_urls) > 0 ? "<p>Console: <strong>${var.console_urls[0]}/</strong></p>" : ""
}

################################################################################
# User pool
################################################################################

resource "aws_cognito_user_pool" "this" {
  name                     = "${var.name}-user-pool"
  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = var.enable_deletion_protection ? "ACTIVE" : "INACTIVE"
  user_pool_tier           = var.user_pool_tier

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 1
    }

    recovery_mechanism {
      name     = "verified_email"
      priority = 2
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Welcome to Distributed Load Testing"
      email_message = "<p>Please use the credentials below to login to the Distributed Load Testing console.</p><p>Username: <strong>{username}</strong></p><p>Password: <strong>{####}</strong></p>${local.invite_console_line}"
      sms_message   = "Your username is {username} and temporary password is {####}."
    }
  }

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  dynamic "user_pool_add_ons" {
    # Threat protection needs the PLUS feature plan.
    for_each = var.user_pool_tier == "PLUS" ? [1] : []

    content {
      advanced_security_mode = "ENFORCED"
    }
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Verify your new account"
    email_message        = "The verification code to your new account is {####}"
    sms_message          = "The verification code to your new account is {####}"
  }

  tags = local.tags
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

# Replaces the upstream CognitoUICustomization custom resource (CSS + logo).
resource "aws_cognito_user_pool_ui_customization" "this" {
  user_pool_id = aws_cognito_user_pool_domain.this.user_pool_id
  image_file   = filebase64("${path.module}/assets/dlt-logo.png")
  css = join(" ", [
    ".banner-customizable { background-color: #232f3e; padding: 25px 0px; }",
    ".logo-customizable { max-width: 350px; max-height: 80px; }",
    ".submitButton-customizable { background-color: #ec7211; }",
    ".submitButton-customizable:hover { background-color: #eb5f07; }",
  ])

  depends_on = [aws_cognito_user_pool_client.console]
}

resource "aws_cognito_user_pool_client" "console" {
  name                                 = "${var.name}-userpool-client"
  user_pool_id                         = aws_cognito_user_pool.this.id
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = local.oauth_urls
  logout_urls                          = local.oauth_urls
  enable_token_revocation              = true
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH"]
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  refresh_token_validity               = 1440
  supported_identity_providers         = ["COGNITO"]
  write_attributes                     = ["address", "email", "phone_number"]

  refresh_token_rotation {
    feature                    = "ENABLED"
    retry_grace_period_seconds = 60
  }

  token_validity_units {
    refresh_token = "minutes"
  }

  lifecycle {
    precondition {
      condition     = length(local.oauth_urls) > 0
      error_message = "The console app client needs at least one callback URL. Set console_urls (CloudFront mode sets it for you) or additional_callback_urls."
    }
  }
}

resource "aws_cognito_user" "admin" {
  user_pool_id             = aws_cognito_user_pool.this.id
  username                 = var.admin_name
  desired_delivery_mediums = ["EMAIL"]
  force_alias_creation     = true

  attributes = {
    email          = var.admin_email
    email_verified = "true"
    nickname       = var.admin_name
  }

  lifecycle {
    # Users change their own attributes after first login.
    ignore_changes = [attributes]
  }
}

resource "aws_cloudwatch_log_group" "user_pool" {
  name              = "/dlt/${var.name}/cognito"
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

resource "aws_cognito_log_delivery_configuration" "this" {
  user_pool_id = aws_cognito_user_pool.this.id

  log_configurations {
    event_source = "userAuthEvents"
    log_level    = "INFO"

    cloud_watch_logs_configuration {
      log_group_arn = aws_cloudwatch_log_group.user_pool.arn
    }
  }

  log_configurations {
    event_source = "userNotification"
    log_level    = "ERROR"

    cloud_watch_logs_configuration {
      log_group_arn = aws_cloudwatch_log_group.user_pool.arn
    }
  }
}

################################################################################
# Identity pool: browser gets SigV4 credentials for API, S3 and IoT
################################################################################

resource "aws_cognito_identity_pool" "this" {
  identity_pool_name               = "${replace(var.name, "-", "_")}_identity_pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id     = aws_cognito_user_pool_client.console.id
    provider_name = aws_cognito_user_pool.this.endpoint
  }

  tags = local.tags
}

data "aws_iam_policy_document" "identity_trust" {
  for_each = toset(["authenticated", "unauthenticated"])

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.identity_principal]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.identity_principal}:aud"
      values   = [aws_cognito_identity_pool.this.id]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "${local.identity_principal}:amr"
      values   = [each.key]
    }
  }
}

resource "aws_iam_role" "identity" {
  for_each = toset(["authenticated", "unauthenticated"])

  name_prefix        = "${substr(var.name, 0, 24)}-${substr(each.key, 0, 5)}-"
  assume_role_policy = data.aws_iam_policy_document.identity_trust[each.key].json

  tags = local.tags
}

data "aws_iam_policy_document" "authenticated" {
  statement {
    sid       = "InvokeApi"
    actions   = ["execute-api:Invoke"]
    resources = ["${var.api_execution_arn}/${var.api_stage_name}/*"]
  }

  statement {
    sid       = "UserFiles"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.scenarios_bucket_arn}/public/*"]
  }

  statement {
    sid       = "ReadResults"
    actions   = ["s3:GetObject"]
    resources = ["${var.scenarios_bucket_arn}/results/*", "${var.scenarios_bucket_arn}/regional-template/*"]
  }

  statement {
    sid       = "ListScenarios"
    actions   = ["s3:ListBucket"]
    resources = [var.scenarios_bucket_arn]
  }

  # The console attaches the IoT policy to the caller's Cognito identity.
  statement {
    sid       = "IotAttach"
    actions   = ["iot:AttachPolicy"]
    resources = ["*"]
  }

  statement {
    sid       = "IotConnect"
    actions   = ["iot:Connect"]
    resources = ["arn:${local.partition}:iot:${local.region}:${local.account_id}:client/*"]
  }

  statement {
    sid       = "IotSubscribe"
    actions   = ["iot:Subscribe"]
    resources = ["arn:${local.partition}:iot:${local.region}:${local.account_id}:topicfilter/dlt/*"]
  }

  statement {
    sid       = "IotReceive"
    actions   = ["iot:Receive"]
    resources = ["arn:${local.partition}:iot:${local.region}:${local.account_id}:topic/dlt/*"]
  }
}

resource "aws_iam_role_policy" "authenticated" {
  name   = "console-access"
  role   = aws_iam_role.identity["authenticated"].id
  policy = data.aws_iam_policy_document.authenticated.json
}

resource "aws_cognito_identity_pool_roles_attachment" "this" {
  identity_pool_id = aws_cognito_identity_pool.this.id

  roles = {
    authenticated   = aws_iam_role.identity["authenticated"].arn
    unauthenticated = aws_iam_role.identity["unauthenticated"].arn
  }
}

################################################################################
# IoT policy for live test metrics (MQTT over WSS from the browser)
################################################################################

data "aws_iam_policy_document" "iot" {
  statement {
    actions   = ["iot:Connect"]
    resources = ["arn:${local.partition}:iot:${local.region}:${local.account_id}:client/*"]
  }

  statement {
    actions   = ["iot:Subscribe"]
    resources = ["arn:${local.partition}:iot:${local.region}:${local.account_id}:topicfilter/dlt/*"]
  }

  statement {
    actions   = ["iot:Receive"]
    resources = ["arn:${local.partition}:iot:${local.region}:${local.account_id}:topic/dlt/*"]
  }
}

resource "aws_iot_policy" "this" {
  name   = "${var.name}-live-data"
  policy = data.aws_iam_policy_document.iot.json

  tags = local.tags
}
