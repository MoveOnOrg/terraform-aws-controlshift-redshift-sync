data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "invoker_lambda_role" {
  name = "ControlShiftInvokerLambdaRole"
  description = "Used by the controlshift-webhook-handler-invoker Lambda for asynchronously invoking the receiver lambda with the db replication data from ControlShift"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "receiver_lambda_role" {
  name = "ReceiverLambdaRole"
  description = "Used by the controlshift-webhook-handler Lambda for receiving db replication data from ControlShift"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "invoker_execution_policy" {
  # allow the lambda to write cloudwatch logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # allow the lambda to invoke the receiver lambda
  statement {
    effect = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "receiver_execution_policy" {
  # allow the lambda to write cloudwatch logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # allow the receiver lambda to enqueue work
  statement {
    effect = "Allow"
    actions = ["sqs:SendMessage"]
    resources = ["arn:aws:sqs:${var.aws_region}:*:${aws_sqs_queue.receiver_queue.name}",
                 "arn:aws:sqs:${var.aws_region}:*:${aws_sqs_queue.receiver_queue_glue.name}"]
  }
}

resource "aws_iam_role_policy" "lambda_receiver" {
  name = "AllowsReceiverExecution"
  role = aws_iam_role.receiver_lambda_role.id
  policy = data.aws_iam_policy_document.receiver_execution_policy.json
}

resource "aws_iam_role" "api_gateway_role" {
  name = "APIGatewayRole"
  description = "Used by the Controlshift API Gateway webhook endpoint for CloudWatch logging"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume_role.json
}

data "aws_iam_policy_document" "gateway_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "gateway_cloudwatch_logging" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "loader_lambda_role" {
  name_prefix = "LoaderLambdaRole"
  description = "Used by the controlshift-redshift-loader Lambda for processing db replication data from ControlShift into Redshift"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy" "lambda_loads_tables" {
  name_prefix = "AllowsLoaderExecution"
  role = aws_iam_role.loader_lambda_role.id
  policy = data.aws_iam_policy_document.loader_execution_policy.json
}

data "aws_iam_policy_document" "loader_execution_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:ListTables",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem"
    ]
    resources = [
      aws_dynamodb_table.loader_config.arn,
      aws_dynamodb_table.batches.arn,
      aws_dynamodb_table.processed_files.arn
    ]
  }

  # Apparently, the KMS resource needs to be *
  statement {
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:Decrypt"
    ]
    resources = [
      aws_kms_key.lambda_config.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:Get*",
      "s3:Put*",
      "s3:List*",
    ]
    resources = [
      aws_s3_bucket.manifest.arn,
      "${aws_s3_bucket.manifest.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::agra-data-exports-${var.controlshift_environment}",
      "arn:aws:s3:::agra-data-exports-${var.controlshift_environment}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "sns:GetEndpointAttributes",
      "sns:GetSubscriptionAttributes",
      "sns:GetTopicAttributes",
      "sns:ListTopics",
      "sns:Publish",
      "sns:Subscribe",
      "sns:Unsubscribe"
    ]
    resources = [
      aws_sns_topic.success_sns_topic.arn,
      aws_sns_topic.failure_sns_topic.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # allow lambda to be wired up to the queue. These are the minimum permissions for the SQS Lambda Executor.
  statement {
    effect = "Allow"
    actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = ["arn:aws:sqs:${var.aws_region}:*:${aws_sqs_queue.receiver_queue.name}"]
  }

  statement {
    effect = "Allow"
    actions = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "run_glue_job_execution_policy" {
  # allow the lambda to write cloudwatch logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # allow the lambda to enqueue work
  statement {
    effect = "Allow"
    actions = [ "glue:StartJobRun" ]
    resources = [ aws_glue_job.signatures_full.arn ]
  }
}

resource "aws_iam_role_policy" "lambda_run_glue_job" {
  name = "AllowsRunGlueJobExecution"
  role = aws_iam_role.run_glue_job_lambda_role.id
  policy = data.aws_iam_policy_document.run_glue_job_execution_policy.json
}

resource "aws_iam_role" "run_glue_job_lambda_role" {
  name = "RunGlueJobLambdaRole"
  description = "Used by the controlshift-run-glue-job Lambda for triggering AWS Glue job once the crawler finishes"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "run_glue_crawler_execution_policy" {
  # allow the lambda to write cloudwatch logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # allow the lambda to enqueue work
  statement {
    effect = "Allow"
    actions = [ "glue:StartCrawler" ]
    resources = [ aws_glue_crawler.signatures_crawler.arn ]
  }

  # allow glue lambda to be wired up to the queue. These are the minimum permissions for the SQS Lambda Executor.
  statement {
    effect = "Allow"
    actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = ["arn:aws:sqs:${var.aws_region}:*:${aws_sqs_queue.receiver_queue_glue.name}"]
  }
}

resource "aws_iam_role_policy" "lambda_run_glue_crawler" {
  name = "AllowsRunGlueCrawlerExecution"
  role = aws_iam_role.run_glue_crawler_lambda_role.id
  policy = data.aws_iam_policy_document.run_glue_crawler_execution_policy.json
}

resource "aws_iam_role" "run_glue_crawler_lambda_role" {
  name = "RunGlueCrawlerLambdaRole"
  description = "Used by the controlshift-run-glue-crawler Lambda for triggering AWS Glue crawler when a new signatures table full data export is available."
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}
