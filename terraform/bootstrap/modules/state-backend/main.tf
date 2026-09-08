locals {
  bucket_name = "${var.org_short}-insurance-${var.environment}-tfstate-${var.account_short}"
  key_alias   = "alias/insurance/${var.environment}/terraform-state"

  tags = {
    Project            = "aws-insurance-data-ai"
    Environment        = var.environment
    Owner              = "platform"
    ManagedBy          = "terraform"
    CostCenter         = "insurance-data-ai"
    DataClassification = "restricted"
  }
}

resource "aws_kms_key" "state" {
  count                   = var.create_resources ? 1 : 0
  description             = "Terraform state encryption for ${var.environment}; customer managed."
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [for role_index, role_arn in var.kms_admin_role_arns : {
        Sid       = "AllowStateAdmin${role_index}"
        Effect    = "Allow"
        Principal = { AWS = role_arn }
        Action    = ["kms:PutKeyPolicy", "kms:DescribeKey", "kms:EnableKey", "kms:DisableKey", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:TagResource", "kms:UntagResource"]
        Resource  = "*"
      }],
      [
        for role_index, role_arn in var.terraform_role_arns : {
          Sid    = "AllowTerraformRole${role_index}"
          Effect = "Allow"
          Principal = {
            AWS = role_arn
          }
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
            "kms:Encrypt",
            "kms:GenerateDataKey",
          ]
          Resource = "*"
        }
      ],
    )
  })

  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "state" {
  count         = var.create_resources ? 1 : 0
  name          = local.key_alias
  target_key_id = aws_kms_key.state[0].key_id
}

resource "aws_s3_bucket" "state" {
  count         = var.create_resources ? 1 : 0
  bucket        = local.bucket_name
  force_destroy = false
  tags          = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  count  = var.create_resources ? 1 : 0
  bucket = aws_s3_bucket.state[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  count  = var.create_resources ? 1 : 0
  bucket = aws_s3_bucket.state[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  count                   = var.create_resources ? 1 : 0
  bucket                  = aws_s3_bucket.state[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  count  = var.create_resources ? 1 : 0
  bucket = aws_s3_bucket.state[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.state[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  count  = var.create_resources ? 1 : 0
  bucket = aws_s3_bucket.state[0].id

  depends_on = [aws_s3_bucket_versioning.state]

  rule {
    id     = "retain-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  count  = var.create_resources ? 1 : 0
  bucket = aws_s3_bucket.state[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state[0].arn,
          "${aws_s3_bucket.state[0].arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "DenyIncorrectExplicitEncryption"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.state[0].arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
          Null = {
            "s3:x-amz-server-side-encryption" = "false"
          }
        }
      },
      {
        Sid       = "DenyIncorrectExplicitKmsKey"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.state[0].arn}/*"
        Condition = {
          ArnNotEquals = {
            "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.state[0].arn
          }
          Null = {
            "s3:x-amz-server-side-encryption-aws-kms-key-id" = "false"
          }
        }
      }
    ]
  })
}
