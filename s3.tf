# Additional provider configuration for region your controlshift platform lives within.
provider "aws" {
  alias  = "controlshift"
  region = var.controlshift_aws_region
}

resource "aws_s3_bucket" "manifest" {
  provider = aws.controlshift
  bucket = var.manifest_bucket_name

  tags = {
    Name = "ControlShift puts import manifests here"
  }
}

# Ownership controls block is required to support ACLs.
resource "aws_s3_bucket_ownership_controls" "manifest" {
  provider = aws.controlshift
  bucket = aws_s3_bucket.manifest.id
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "manifest" {
  provider = aws.controlshift
  bucket = aws_s3_bucket.manifest.id

  # expire the ingested manifests after 5 days after they have been processed to save disk space while providing enough
  # time to analyze things that might have gone wrong.
  rule {
    id = "expire-manifests"
    status = "Enabled"

    expiration {
      days = 5
    }

    # Best practice: filter is now required inside the rule block
    filter {}
  }
}

resource "aws_s3_bucket_acl" "manifest" {
  provider = aws.controlshift
  depends_on = [aws_s3_bucket_ownership_controls.manifest]

  bucket = aws_s3_bucket.manifest.id
  acl    = "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "manifest" {
  provider = aws.controlshift
  bucket = aws_s3_bucket.manifest.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
