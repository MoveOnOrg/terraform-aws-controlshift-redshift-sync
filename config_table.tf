resource "aws_dynamodb_table" "loader_config" {
  name  = "LambdaRedshiftBatchLoadConfig"
  billing_mode = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 5

  attribute {
    name = "s3Prefix"
    type = "S"
  }

  hash_key = "s3Prefix"
}

resource "aws_dynamodb_table_item" "load_config_full_items" {
  /*for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"]])*/
  for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"] if table["table"]["name"] != "signatures"])

  table_name = aws_dynamodb_table.loader_config.name
  hash_key   = aws_dynamodb_table.loader_config.hash_key

  item = data.template_file.loader_config_full_item[each.key].rendered

  lifecycle {
    ignore_changes = [
      # Ignore changes to item so that the Lambda updating the currentBatch does not conflict with terraform generated values.
      # Otherwise Terraform will overwrite these values and the loader will become confused and try to re-load the first batch.
      #
      # A side effect of this, is that if you would actually like to change the loader configuration you must
      # manually delete all of the configs in DynamoDB

      item
    ]
  }
}

data "template_file" "loader_config_full_item" {
  /*for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"]])*/
  for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"] if table["table"]["name"] != "signatures"])

  template = "${file("${path.module}/config_item.json")}"
  vars = {
    kind = "full"
    bulk_data_table = each.key
    redshift_endpoint = data.aws_redshift_cluster.sync_data_target.endpoint
    redshift_database_name: var.redshift_database_name
    redshift_port = data.aws_redshift_cluster.sync_data_target.port
    redshift_username = var.redshift_username
    redshift_password = aws_kms_ciphertext.redshift_password.ciphertext_blob
    schema = var.redshift_schema
    s3_bucket = "agra-data-exports-${var.controlshift_environment}"
    manifest_bucket = aws_s3_bucket.manifest.bucket
    manifest_prefix = var.manifest_prefix
    failed_manifest_prefix = var.failed_manifest_prefix
    success_topic_arn = aws_sns_topic.success_sns_topic.arn
    failure_topic_arn = aws_sns_topic.failure_sns_topic.arn
    current_batch = random_id.current_batch.b64_url
    column_list = data.http.column_list[each.key].body
    truncate_target = true
  }
}

resource "aws_dynamodb_table_item" "load_config_incremental_items" {
  for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"]])

  table_name = aws_dynamodb_table.loader_config.name
  hash_key   = aws_dynamodb_table.loader_config.hash_key

  item = data.template_file.loader_config_incremental_item[each.key].rendered

  lifecycle {
    ignore_changes = [
      # Ignore changes to item so that the Lambda updating the currentBatch does not conflict with terraform generated values.
      # Otherwise Terraform will overwrite these values and the loader will become confused and try to re-load the first batch.
      #
      # A side effect of this, is that if you would actually like to change the loader configuration you must
      # manually delete all of the configs in DynamoDB

      item
    ]
  }
}

data "template_file" "loader_config_incremental_item" {
  for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"]])

  template = "${file("${path.module}/config_item.json")}"
  vars = {
    kind = "incremental"
    bulk_data_table = each.key
    redshift_endpoint = data.aws_redshift_cluster.sync_data_target.endpoint
    redshift_database_name: var.redshift_database_name
    redshift_port = data.aws_redshift_cluster.sync_data_target.port
    redshift_username = var.redshift_username
    redshift_password = aws_kms_ciphertext.redshift_password.ciphertext_blob
    schema = var.redshift_schema
    s3_bucket = "agra-data-exports-${var.controlshift_environment}"
    manifest_bucket = aws_s3_bucket.manifest.bucket
    manifest_prefix = var.manifest_prefix
    failed_manifest_prefix = var.failed_manifest_prefix
    success_topic_arn = aws_sns_topic.success_sns_topic.arn
    failure_topic_arn = aws_sns_topic.failure_sns_topic.arn
    current_batch = random_id.current_batch.b64_url
    column_list = data.http.column_list[each.key].body
    truncate_target = false
  }
}

resource "random_id" "current_batch" {
  byte_length = 16
}

resource "aws_kms_ciphertext" "redshift_password" {
  key_id = aws_kms_key.lambda_config.key_id
  context = {
    module = "AWSLambdaRedshiftLoader",
    region = var.aws_region
  }
  plaintext = var.redshift_password
}

resource "aws_kms_alias" "lambda_alias" {
  name = "alias/LambaRedshiftLoaderKey"
  target_key_id = aws_kms_key.lambda_config.key_id
}

resource "aws_kms_key" "lambda_config" {
  description = "Controlshift Lambda Redshift Loader Master Encryption Key"
  is_enabled  = true
}

data "http" "bulk_data_schemas" {
  url = "https://${var.controlshift_hostname}/api/bulk_data/schema.json"
}

data "http" "column_list" {
  for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"]])

  url = "https://${var.controlshift_hostname}/api/bulk_data/schema/columns?table=${each.key}"
}
