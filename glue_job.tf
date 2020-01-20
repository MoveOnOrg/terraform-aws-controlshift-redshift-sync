resource "aws_glue_catalog_database" "catalog_db" {
  name = "controlshift_${var.controlshift_environment}"
}

locals {
  signatures_s3_path = "s3://agra-data-exports-${var.controlshift_environment}/${var.controlshift_organization_slug}/full/signatures"
}

resource "aws_glue_catalog_table" "signatures" {
  name = "signatures"
  database_name = aws_glue_catalog_database.catalog_db.name

  storage_descriptor {
    location = local.signatures_s3_path
  }
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

data "template_file" "signatures_script" {
  template = file("${path.module}/templates/signatures_job.py.tpl")
  vars = {
    database_name = aws_glue_catalog_database.catalog_db.name
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

resource "aws_iam_role_policy_attachment" "redshift_full_access" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRedshiftFullAccess"
}

resource "aws_iam_role_policy" "controlshift_data_export_bucket_access" {
  name = "AllowsCrossAccountAccessToControlShiftDataExportBucket"
  role = aws_iam_role.glue_service_role.id
  policy = data.aws_iam_policy_document.controlshift_data_export_bucket.json
}

# TODO: Use more restrictive permissions (?)
data "aws_iam_policy_document" "controlshift_data_export_bucket" {
  statement {
    effect = "Allow"
    actions = [ "s3:*" ]
    resources = [
      "arn:aws:s3:::agra-data-exports-${var.controlshift_environment}/${var.controlshift_organization_slug}/*"
    ]
  }
}

resource "aws_glue_connection" "redshift_connection" {
  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:redshift://${var.redshift_dns_name}:${var.redshift_port}/${var.redshift_database_name}"
    PASSWORD            = "${var.redshift_username}"
    USERNAME            = "${var.redshift_password}"
  }

  name = "controlshift_${var.controlshift_environment}_data_sync"
}

# TODO: give glue_service_role some permissions as currently held by
#       AWSGlueServiceRole-ManualTest

resource "aws_glue_job" "signatures_full" {
  name = "cs-${var.controlshift_environment}-signatures-full"
  connections = [ aws_glue_connection.redshift_connection ]
  glue_version = "1.0"
  default_arguments = { "--TempDir": "s3://${aws_s3_bucket.glue_resources.bucket}/${var.controlshift_environment}/temp" }

  role_arn = aws_iam_role.glue_service_role.arn

  command {
    script_location = "s3://${aws_s3_bucket.glue_resources.bucket}/${var.controlshift_environment}/signatures_job.py"
    python_version = "3"
  }
}
