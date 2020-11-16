data "archive_file" "invoker_zip" {
  type        = "zip"
  source_file = "${path.module}/receiver/invoker.js"
  output_path = "${path.module}/receiver/invoker.zip"
}

data "archive_file" "receiver_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/receiver.js"
  output_path = "${path.module}/lambdas/receiver.zip"
}

resource "aws_lambda_function" "invoker_lambda" {
  filename = data.archive_file.invoker_zip.output_path
  function_name = "controlshift-webhook-handler-invoker"
  role          = aws_iam_role.invoker_lambda_role.arn
  handler       = "invoker.handler"
  runtime       = "nodejs10.x"
  timeout       = 30
  source_code_hash = filebase64sha256(data.archive_file.invoker_zip.output_path)

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.receiver.bucket
    }
  }
}

resource "aws_lambda_function" "receiver_lambda" {
  filename = data.archive_file.receiver_zip.output_path
  function_name = "controlshift-webhook-handler"
  role          = aws_iam_role.receiver_lambda_role.arn
  handler       = "receiver.handler"
  runtime       = "nodejs10.x"
  memory_size   = 256
  timeout       = var.receiver_timeout
  source_code_hash = data.archive_file.receiver_zip.output_base64sha256

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.receiver_queue.id
      GLUE_SQS_QUEUE_URL = aws_sqs_queue.receiver_queue_glue.id
    }
  }
}

resource "aws_api_gateway_rest_api" "receiver" {
  name = "controlshift-webhook-receiver"
  description = "Receives ControlShift webhooks and dumps them onto an SQS queue"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.receiver.id
  parent_id   = aws_api_gateway_rest_api.receiver.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "request_method" {
  rest_api_id   = aws_api_gateway_rest_api.receiver.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.receiver.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.request_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "receiver" {
  rest_api_id = aws_api_gateway_rest_api.receiver.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.request_method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_templates = {
    "application/json" = ""
  }
  depends_on = [aws_api_gateway_integration.request_method_integration]
}

resource "aws_api_gateway_integration" "request_method_integration" {
  rest_api_id = aws_api_gateway_rest_api.receiver.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = "POST"
  type        = "AWS_PROXY"
  uri         = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.invoker_lambda.arn}/invocations"
  # AWS lambdas can only be invoked with the POST method
  integration_http_method = "POST"
}

# The * part allows invocation from any stage within API Gateway REST API.
resource "aws_lambda_permission" "allow_api_gateway" {
  function_name = aws_lambda_function.invoker_lambda.function_name
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.receiver.execution_arn}/*/POST/webhook"
}

# for now, there is only one deployment
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.request_method_integration]

  rest_api_id = aws_api_gateway_rest_api.receiver.id
  stage_name  = "production"
}

resource "aws_sqs_queue" "receiver_queue" {
  name = "controlshift-received-webhooks"
  visibility_timeout_seconds = 900
}

resource "aws_sqs_queue" "receiver_queue_glue" {
  name = "controlshift-received-webhooks-glue"
  visibility_timeout_seconds = 900
}

# there is no formal way to associate this resource, beyond ensuring the name matches.
resource "aws_cloudwatch_log_group" "api_gateway_log_retention" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.receiver.id}/${aws_api_gateway_deployment.deployment.stage_name}"
  retention_in_days = 5
}
