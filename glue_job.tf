resource "aws_glue_catalog_database" "catalog_db" {
  name = "controlshift_${var.controlshift_environment}"
}

locals {
  signatures_s3_path = "s3://agra-data-exports-${var.controlshift_environment}/${var.controlshift_organization_slug}/full/signatures"
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
  region = var.aws_region

  acl = "private"
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

data "template_file" "signatures_script" {
  template = file("${path.module}/templates/signatures_job.py.tpl")
  vars = {
    catalog_database_name = aws_glue_catalog_database.catalog_db.name
    redshift_database_name = var.redshift_database_name
    redshift_schema = var.redshift_schema
    redshift_connection_name = aws_glue_connection.redshift_connection.name
  }
}

resource "aws_s3_bucket_object" "signatures_script" {
  bucket = aws_s3_bucket.glue_resources.id
  key = "${var.controlshift_environment}/signatures_job.py"
  acl = "private"

  content = data.template_file.signatures_script.rendered
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

  dynamic "physical_connection_requirements" {
    for_each = var.glue_physical_connection_requirements == null ? [] : list(var.glue_physical_connection_requirements)
    content {
      availability_zone = physical_connection_requirements.value.availability_zone
      security_group_id_list = physical_connection_requirements.value.security_group_id_list
      subnet_id = physical_connection_requirements.value.subnet_id
    }
  }
}

resource "aws_glue_job" "signatures_full" {
  name = "cs-${var.controlshift_environment}-signatures-full"
  connections = [ aws_glue_connection.redshift_connection.name ]
  glue_version = "1.0"
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
