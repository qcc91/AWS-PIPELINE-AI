locals {
  data_location_object_arns = [
    for bucket_arn in var.data_location_bucket_arns : "${bucket_arn}/*"
  ]
}

resource "aws_iam_role" "terraform_execution" {
  name                 = "insurance-${var.environment}-terraform-execution-role"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowApprovedSameAccountRoles"
        Effect = "Allow"
        Principal = {
          AWS = var.trusted_role_arns
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "terraform_execution" {
  name = "phase1-read-and-pass-registration-role"
  role = aws_iam_role.terraform_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "ReadUnscopedServiceMetadata"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
      {
        Sid = "InspectApprovedDataLocations"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketVersioning",
          "s3:GetEncryptionConfiguration",
          "s3:ListBucket",
        ]
        Resource = var.data_location_bucket_arns
      },
      {
        Sid = "InspectApprovedDataKeys"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
        ]
        Resource = var.data_kms_key_arns
      },
      {
        Sid      = "PassLakeFormationRegistrationRoleOnly"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.lakeformation_registration.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "lakeformation.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "lakeformation_registration" {
  name                 = "insurance-${var.environment}-lakeformation-registration-role"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLakeFormationService"
        Effect = "Allow"
        Principal = {
          Service = "lakeformation.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "lakeformation_registration" {
  name = "approved-data-location-access"
  role = aws_iam_role.lakeformation_registration.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "ListApprovedDataLocationBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
        ]
        Resource = var.data_location_bucket_arns
      },
      {
        Sid = "ReadWriteApprovedDataLocationObjects"
        Effect = "Allow"
        Action = [
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = local.data_location_object_arns
      },
      {
        Sid = "UseApprovedDataKeys"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
        ]
        Resource = var.data_kms_key_arns
      }
    ]
  })
}
