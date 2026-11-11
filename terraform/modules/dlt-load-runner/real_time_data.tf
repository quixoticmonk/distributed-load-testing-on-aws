################################################################################
# Real-time data publisher
# Subscribes to the ECS task log group and publishes live metrics to IoT Core
# in the hub region, where the web console listens over MQTT/WSS.
################################################################################

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "real_time_data_publisher" {
  name_prefix        = "${substr(var.name, 0, 24)}-rtdp-"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = local.tags
}

data "aws_iam_policy_document" "real_time_data_publisher" {
  statement {
    actions   = ["iot:Publish"]
    resources = ["arn:${data.aws_partition.current.partition}:iot:${var.main_region}:${data.aws_caller_identity.current.account_id}:topic/dlt/*"]
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.real_time_data_publisher.arn}:*"]
  }
}

resource "aws_iam_role_policy" "real_time_data_publisher" {
  name   = "IoTPolicy"
  role   = aws_iam_role.real_time_data_publisher.id
  policy = data.aws_iam_policy_document.real_time_data_publisher.json
}

resource "aws_cloudwatch_log_group" "real_time_data_publisher" {
  name              = "/aws/lambda/${var.name}-real-time-data-publisher"
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

resource "aws_lambda_function" "real_time_data_publisher" {
  function_name    = "${var.name}-real-time-data-publisher"
  description      = "Real time data publisher"
  role             = aws_iam_role.real_time_data_publisher.arn
  filename         = var.real_time_data_publisher_zip
  source_code_hash = filebase64sha256(var.real_time_data_publisher_zip)
  handler          = "index.handler"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]
  timeout          = 180

  environment {
    variables = {
      IOT_ENDPOINT = "https://${var.iot_endpoint}"
      MAIN_REGION  = var.main_region
      SOLUTION_ID  = var.solution_id
      VERSION      = var.solution_version
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.real_time_data_publisher.name
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.real_time_data_publisher]
}

resource "aws_lambda_permission" "real_time_data_publisher" {
  statement_id   = "AllowCloudWatchLogsInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.real_time_data_publisher.arn
  principal      = "logs.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "${aws_cloudwatch_log_group.tasks.arn}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "real_time_data" {
  name            = "${var.name}-live-metrics"
  log_group_name  = aws_cloudwatch_log_group.tasks.name
  filter_pattern  = "\"INFO: Current:\" \"live=true\""
  destination_arn = aws_lambda_function.real_time_data_publisher.arn

  depends_on = [aws_lambda_permission.real_time_data_publisher]
}
