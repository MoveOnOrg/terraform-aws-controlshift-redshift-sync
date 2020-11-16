resource "aws_lambda_function" "loader" {
  s3_bucket = local.lambda_buckets[var.aws_region]
  s3_key = "LambdaRedshiftLoader/AWSLambdaRedshiftLoader-2.7.8.zip"
  function_name = "controlshift-redshift-loader"
  role          = aws_iam_role.loader_lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  timeout       = 900

  vpc_config {
    subnet_ids         = concat(var.lambda_loader_subnet_ids, list(""))
    security_group_ids = concat(var.lambda_loader_security_group_ids, list(""))
  }

  environment {
    variables = {
      "DEBUG" = "true"
      "CONTROLSHIFT_AWS_REGION" = var.controlshift_aws_region
    }
  }
}

resource "aws_lambda_event_source_mapping" "process_task" {
  event_source_arn = aws_sqs_queue.receiver_queue.arn
  function_name    = aws_lambda_function.loader.arn
  batch_size = 1
  depends_on = [aws_iam_role_policy.lambda_loads_tables]
}

resource "aws_sns_topic" "success_sns_topic" {
  depends_on = [aws_lambda_function.loader]

  name = var.success_topic_name
  policy = data.aws_iam_policy_document.success_sns_notification_policy.json
}

data "aws_iam_policy_document" "success_sns_notification_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "SNS:Publish",
    ]
    resources = [
      "arn:aws:sns:*:*:${var.success_topic_name}"
    ]
    condition {
      test      = "ArnLike"
      variable  = "aws:SourceArn"
      values    = [
        aws_lambda_function.loader.arn,
      ]
    }
  }
}

resource "aws_sns_topic" "failure_sns_topic" {
  depends_on = [aws_lambda_function.loader]

  name = var.failure_topic_name
  policy = data.aws_iam_policy_document.failure_sns_notification_policy.json
}

data "aws_iam_policy_document" "failure_sns_notification_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "SNS:Publish",
    ]
    resources = [
      "arn:aws:sns:*:*:${var.failure_topic_name}"
    ]
    condition {
      test      = "ArnLike"
      variable  = "aws:SourceArn"
      values    = [
        aws_lambda_function.loader.arn,
      ]
    }
  }
}
