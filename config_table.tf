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

resource "aws_dynamodb_table_item" "load_signatures" {
  for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"]])

  table_name = aws_dynamodb_table.loader_config.name
  hash_key   = aws_dynamodb_table.loader_config.hash_key

  item = data.template_file.loader_config_item[each.key].rendered
}

data "template_file" "loader_config_item" {
  for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"]])

  template = "${file("${path.module}/config_item.json")}"
  vars = {
    bulk_data_table = each.key
    redshift_endpoint = var.redshift_dns_name
    redshift_database_name: var.redshift_database_name
    redshift_port = var.redshift_port
    redshift_username = var.redshift_username
    redshift_password = aws_kms_ciphertext.redshift_password.ciphertext_blob
    s3_bucket = aws_s3_bucket.receiver.bucket
    manifest_bucket = aws_s3_bucket.manifest.bucket
    manifest_prefix = var.manifest_prefix
    failed_manifest_prefix = var.failed_manifest_prefix
    current_batch = random_id.current_batch.b64_url
    column_list = data.http.column_list[each.key].body
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
  description = "Lambda Redshift Loader Master Encryption Key"
  is_enabled  = true
}

data "http" "bulk_data_schemas" {
  url = "https://${var.controlshift_hostname}/api/bulk_data/schema.json"
}

data "http" "column_list" {
  for_each = toset([for table in jsondecode(data.http.bulk_data_schemas.body)["tables"] : table["table"]["name"]])

  url = "https://${var.controlshift_hostname}/api/bulk_data/schema/columns?table=${each.key}"
}
