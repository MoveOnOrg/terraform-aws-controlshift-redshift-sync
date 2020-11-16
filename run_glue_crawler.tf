data "archive_file" "run_glue_crawler_zip" {
  type        = "zip"
  
  source_file = "${path.module}/lambdas/run-glue-crawler.js"
  output_path = "${path.module}/lambdas/run-glue-crawler.zip"
}

resource "aws_lambda_function" "glue_crawler_lambda" {
  filename = data.archive_file.run_glue_crawler_zip.output_path
  function_name = "controlshift-run-glue-crawler"
  role          = aws_iam_role.run_glue_crawler_lambda_role.arn
  handler       = "run-glue-crawler.handler"
  runtime       = "nodejs12.x"
  timeout       = 60
  source_code_hash = data.archive_file.run_glue_crawler_zip.output_base64sha256

  environment {
    variables = {
      GLUE_CRAWLER_NAME = aws_glue_crawler.signatures_crawler.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "run_crawler_on_new_data_export_task" {
  event_source_arn = aws_sqs_queue.receiver_queue_glue.arn
  function_name    = aws_lambda_function.glue_crawler_lambda.arn
  batch_size = 1
}
