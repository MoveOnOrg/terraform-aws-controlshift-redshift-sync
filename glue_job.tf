resource "aws_glue_catalog_database" "catalog_db" {
  name = "controlshift_${var.controlshift_environment}"
}

locals {
  signatures_s3_path = "s3://agra-data-exports-${var.controlshift_environment}/${var.controlshift_organization_slug}/full/signatures"
  signatures_table_index = index(local.parsed_bulk_data_schemas.tables.*.table.name, "signatures")
  signatures_table_columns = local.parsed_bulk_data_schemas.tables[local.signatures_table_index].table.columns
}

resource "aws_glue_crawler" "signatures_crawler" {
  database_name = aws_glue_catalog_database.catalog_db.name
  name = "${var.controlshift_environment}_full_signatures"
  role = aws_iam_role.glue_service_role.arn

  s3_target {
    path = local.signatures_s3_path
  }
}

resource "aws_s3_bucket" "glue_resources" {
  bucket = var.glue_scripts_bucket_name
}

resource "aws_s3_bucket_acl" "glue_resources" {
  bucket = aws_s3_bucket.glue_resources.id
  acl    = "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "glue_resources" {
  bucket = aws_s3_bucket.glue_resources.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

locals {
  # Unsupported column types read from CSV files: all of these will be read as 'string'
  unsupported_input_column_types = [
    "boolean",
    "character varying.*",
    "decimal.*",
    "hstore",
    "jsonb",
    "numeric.*",
    "timestamp"
  ]

  # Unsupported columnt types for Redshift: these will be replaced by the mapped type
  unsupported_output_column_types = {
    "hstore" = "character varying"
    "jsonb" = "character varying"
    "numeric\\(3,2\\)" = "decimal(3,2)"
    "timestamp without time zone" = "timestamp"
  }

  signatures_script = templatefile("${path.module}/templates/signatures_job.py.tftpl", {
    catalog_database_name = aws_glue_catalog_database.catalog_db.name
    unsupported_input_column_types = local.unsupported_input_column_types
    unsupported_output_column_types = local.unsupported_output_column_types
    redshift_database_name = var.redshift_database_name
    redshift_schema = var.redshift_schema
    redshift_connection_name = aws_glue_connection.redshift_connection.name
    signatures_table_columns = local.signatures_table_columns
  })
}

resource "aws_s3_object" "signatures_script" {
  bucket = aws_s3_bucket.glue_resources.id
  key = "${var.controlshift_environment}/signatures_job.py"
  acl = "private"

  content = local.signatures_script
}

resource "aws_iam_role" "glue_service_role" {
  name = "AWSGlueServiceRole"
  description = "Used by the AWS Glue jobs to insert data into redshift"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json
}

data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "glue_resources" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "controlshift_data_export_bucket_access" {
  name = "AllowsCrossAccountAccessToControlShiftDataExportBucket"
  role = aws_iam_role.glue_service_role.id
  policy = data.aws_iam_policy_document.controlshift_data_export_bucket.json
}

resource "aws_iam_role_policy" "controlshift_glue_scripts_bucket_access" {
  name = "AllowsAccessToGlueScriptsBucket"
  role = aws_iam_role.glue_service_role.id
  policy = data.aws_iam_policy_document.controlshift_glue_scripts_bucket.json
}

data "aws_iam_policy_document" "controlshift_data_export_bucket" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::agra-data-exports-${var.controlshift_environment}/${var.controlshift_organization_slug}/*"
    ]
  }
}

data "aws_iam_policy_document" "controlshift_glue_scripts_bucket" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::${var.glue_scripts_bucket_name}/*",
      "arn:aws:s3:::${var.glue_scripts_bucket_name}"
    ]
  }
}

resource "aws_glue_connection" "redshift_connection" {
  name = "controlshift_${var.controlshift_environment}_data_sync"

  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:redshift://${data.aws_redshift_cluster.sync_data_target.endpoint}:${data.aws_redshift_cluster.sync_data_target.port}/${var.redshift_database_name}"
    PASSWORD            = var.redshift_password
    USERNAME            = var.redshift_username
    JDBC_ENFORCE_SSL    = false
  }

  physical_connection_requirements {
    availability_zone = var.glue_physical_connection_requirements.availability_zone
    security_group_id_list = var.glue_physical_connection_requirements.security_group_id_list
    subnet_id = var.glue_physical_connection_requirements.subnet_id
  }
}

resource "aws_glue_job" "signatures_full" {
  name = "cs-${var.controlshift_environment}-signatures-full"
  connections = [ aws_glue_connection.redshift_connection.name ]
  glue_version = "3.0"
  default_arguments = {
    "--TempDir": "s3://${aws_s3_bucket.glue_resources.bucket}/${var.controlshift_environment}/temp",
    "--job-bookmark-option": "job-bookmark-disable",
    "--job-language": "python"
  }

  role_arn = aws_iam_role.glue_service_role.arn

  command {
    script_location = "s3://${aws_s3_bucket.glue_resources.bucket}/${var.controlshift_environment}/signatures_job.py"
    python_version = "3"
  }
}


resource "aws_sns_topic" "glue_job_success" {
  depends_on = [ aws_glue_job.signatures_full ]
  name = var.success_topic_name_for_run_glue_job_lambda
  policy = data.aws_iam_policy_document.sns_notification_policy_for_successful_run_glue_job.json
}

data "aws_iam_policy_document" "sns_notification_policy_for_successful_run_glue_job" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [ "events.amazonaws.com" ]
    }
    actions = [
      "SNS:Publish"
    ]
    resources = [
      "arn:aws:sns:*:*:${var.success_topic_name_for_run_glue_job_lambda}"
    ]
  }
}

resource "aws_cloudwatch_event_rule" "successful_glue_job_run" {
  name        = "successful-glue-job-run"
  description = "Glue Job finished successfully"

  event_pattern = <<PATTERN
{
  "source": [
    "aws.glue"
  ],
  "detail-type": [
    "Glue Job State Change"
  ],
  "detail": {
    "state": [
      "SUCCEEDED"
    ]
  }
}
PATTERN
}

resource "aws_cloudwatch_event_target" "notify_successful_glue_job" {
  rule      = aws_cloudwatch_event_rule.successful_glue_job_run.name
  target_id = "notify-successful-glue-job-run"
  arn       = aws_sns_topic.glue_job_success.arn
}

resource "aws_sns_topic" "glue_job_failure" {
  depends_on = [ aws_glue_job.signatures_full ]
  name = var.failure_topic_name_for_run_glue_job_lambda
  policy = data.aws_iam_policy_document.sns_notification_policy_for_failed_run_glue_job.json
}

data "aws_iam_policy_document" "sns_notification_policy_for_failed_run_glue_job" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [ "events.amazonaws.com" ]
    }
    actions = [
      "SNS:Publish"
    ]
    resources = [
      "arn:aws:sns:*:*:${var.failure_topic_name_for_run_glue_job_lambda}"
    ]
  }
}

resource "aws_cloudwatch_event_rule" "failed_glue_job_run" {
  name        = "failed-glue-job-run"
  description = "Glue Job finished with failure"

  event_pattern = <<PATTERN
{
  "source": [
    "aws.glue"
  ],
  "detail-type": [
    "Glue Job State Change"
  ],
  "detail": {
    "state": [
      "FAILED", "TIMEOUT"
    ]
  }
}
PATTERN
}

resource "aws_cloudwatch_event_target" "notify_failed_glue_job" {
  rule      = aws_cloudwatch_event_rule.failed_glue_job_run.name
  target_id = "notify-failed-glue-job-run"
  arn       = aws_sns_topic.glue_job_failure.arn
}


data "aws_vpc" "main" {
  id = var.vpc_id
}

data "aws_route_tables" "all_route_tables" {
  vpc_id = data.aws_vpc.main.id
}

# Glue jobs require a VPC endpoint for connecting to S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = data.aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
}

resource "aws_vpc_endpoint_route_table_association" "s3" {
  count = length(data.aws_route_tables.all_route_tables.ids)

  route_table_id  = tolist(data.aws_route_tables.all_route_tables.ids)[count.index]
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}
