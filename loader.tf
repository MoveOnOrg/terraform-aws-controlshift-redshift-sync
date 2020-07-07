resource "aws_lambda_function" "loader" {
  s3_bucket = "awslabs-code-${var.aws_region}"
  s3_key = "LambdaRedshiftLoader/AWSLambdaRedshiftLoader-2.7.0.zip"
  function_name = "controlshift-redshift-loader"
  role          = aws_iam_role.loader_lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs10.x"
  memory_size   = 512
  timeout       = 900
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.loader.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.receiver.arn
}

resource "aws_s3_bucket_notification" "notifications" {
  bucket = aws_s3_bucket.receiver.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.loader.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "incremental"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.loader.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "full"
  }
}

resource "aws_sns_topic" "success_sns_topic" {
  depends_on = [aws_lambda_function.loader]

  name = var.success_topic_name
  policy = data.aws_iam_policy_document.success_sns_notification_policy.json
}

resource "aws_sns_topic" "failure_sns_topic" {
  depends_on = [aws_lambda_function.loader]

  name = var.failure_topic_name
  policy = data.aws_iam_policy_document.failure_sns_notification_policy.json
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
      "arn:aws:sns:*:*:${var.success_topic_name}",
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
      "arn:aws:sns:*:*:${var.failure_topic_name}",
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
