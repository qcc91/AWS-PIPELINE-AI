locals {
  trail_name     = "insurance-${var.environment}-management-trail"
  trail_arn      = "arn:aws:cloudtrail:ap-southeast-2:${var.account_id}:trail/${local.trail_name}"
  log_group_name = "/insurance/${var.environment}/cloudtrail/audit"
  log_group_arn  = "arn:aws:logs:ap-southeast-2:${var.account_id}:log-group:${local.log_group_name}"
  topic_name     = "insurance-${var.environment}-critical-alerts"
  topic_arn      = "arn:aws:sns:ap-southeast-2:${var.account_id}:${local.topic_name}"
}

resource "aws_kms_key" "audit" {
  description             = "${var.environment} audit, CloudTrail, CloudWatch Logs, and SNS encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      var.allow_root_for_v1 ? [{ Sid = "EnableV1RootScopedAccess", Effect = "Allow", Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }, Action = ["kms:CancelKeyDeletion", "kms:CreateAlias", "kms:DeleteAlias", "kms:DescribeKey", "kms:DisableKey", "kms:DisableKeyRotation", "kms:EnableKey", "kms:EnableKeyRotation", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListGrants", "kms:ListKeyPolicies", "kms:ListResourceTags", "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion", "kms:TagResource", "kms:UntagResource", "kms:UpdateAlias", "kms:UpdateKeyDescription", "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:ReEncryptFrom", "kms:ReEncryptTo"], Resource = "*" }] : [],
      [
        for role_index, role_arn in var.kms_admin_role_arns : {
          Sid    = "AllowAuditKeyAdministrator${role_index}"
          Effect = "Allow"
          Principal = {
            AWS = role_arn
          }
          Action = [
            "kms:CancelKeyDeletion",
            "kms:CreateGrant",
            "kms:DescribeKey",
            "kms:DisableKey",
            "kms:DisableKeyRotation",
            "kms:EnableKey",
            "kms:EnableKeyRotation",
            "kms:GetKeyPolicy",
            "kms:GetKeyRotationStatus",
            "kms:ListGrants",
            "kms:ListKeyPolicies",
            "kms:ListResourceTags",
            "kms:PutKeyPolicy",
            "kms:RevokeGrant",
            "kms:ScheduleKeyDeletion",
            "kms:TagResource",
            "kms:UntagResource",
            "kms:UpdateKeyDescription",
          ]
          Resource = "*"
        }
      ],
      [
        {
          Sid    = "AllowCloudTrailGenerateDataKey"
          Effect = "Allow"
          Principal = {
            Service = "cloudtrail.amazonaws.com"
          }
          Action   = "kms:GenerateDataKey*"
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = var.account_id
            }
            ArnEquals = {
              "aws:SourceArn"                            = local.trail_arn
              "kms:EncryptionContext:aws:cloudtrail:arn" = local.trail_arn
            }
          }
        },
        {
          Sid    = "AllowCloudTrailDescribeKey"
          Effect = "Allow"
          Principal = {
            Service = "cloudtrail.amazonaws.com"
          }
          Action   = "kms:DescribeKey"
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = var.account_id
            }
            ArnEquals = {
              "aws:SourceArn" = local.trail_arn
            }
          }
        },
        {
          Sid    = "AllowCloudWatchLogsEncryption"
          Effect = "Allow"
          Principal = {
            Service = "logs.ap-southeast-2.amazonaws.com"
          }
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
            "kms:Encrypt",
            "kms:GenerateDataKey*",
            "kms:ReEncrypt*",
          ]
          Resource = "*"
          Condition = {
            ArnEquals = {
              "kms:EncryptionContext:aws:logs:arn" = local.log_group_arn
            }
          }
        },
        {
          Sid    = "AllowSnsEncryption"
          Effect = "Allow"
          Principal = {
            Service = "sns.amazonaws.com"
          }
          Action = [
            "kms:Decrypt",
            "kms:GenerateDataKey*",
          ]
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = var.account_id
            }
            ArnEquals = {
              "aws:SourceArn" = local.topic_arn
            }
          }
        }
      ],
    )
  })

  tags = merge(var.tags, {
    Purpose = "audit-encryption"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "audit" {
  name          = "alias/insurance/${var.environment}/audit"
  target_key_id = aws_kms_key.audit.key_id
}

resource "aws_s3_bucket" "audit" {
  bucket        = var.bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Purpose = "audit-logs"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket = aws_s3_bucket.audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.audit.arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  depends_on = [aws_s3_bucket_versioning.audit]

  rule {
    id     = "retain-noncurrent-audit-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.audit_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.audit_noncurrent_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.audit.arn,
          "${aws_s3_bucket.audit.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowCloudTrailBucketAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.audit.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
          ArnEquals = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid    = "AllowCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
          ArnEquals = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "audit" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.audit.arn
  tags              = var.tags
}

resource "aws_iam_role" "cloudtrail_delivery" {
  name = "insurance-${var.environment}-cloudtrail-delivery-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailService"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
          ArnEquals = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudtrail_delivery" {
  name = "write-target-cloudwatch-log-streams"
  role = aws_iam_role.cloudtrail_delivery.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteOnlyTargetLogStreams"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.audit.arn}:log-stream:*"
      }
    ]
  })
}

resource "aws_sns_topic" "alerts" {
  name              = local.topic_name
  kms_master_key_id = aws_kms_key.audit.arn
  tags              = var.tags
}

resource "aws_cloudtrail" "management" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.audit.id
  kms_key_id                    = aws_kms_key.audit.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.audit.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_delivery.arn
  is_multi_region_trail         = false
  include_global_service_events = true
  enable_logging                = true

  event_selector {
    read_write_type                  = "All"
    include_management_events        = true
    exclude_management_event_sources = []
  }

  tags = var.tags

  depends_on = [aws_s3_bucket_policy.audit]
}
