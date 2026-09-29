locals {
  mlflow_tracking_server_name = "insurance-${var.environment}-claim-risk"
  mlflow_artifact_prefix      = "mlflow"
}

resource "aws_iam_role" "mlflow_tracking" {
  name = "insurance-${var.environment}-claim-risk-mlflow-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SageMakerManagedMlflowOnly"
      Effect    = "Allow"
      Principal = { Service = "sagemaker.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = merge(var.tags, { Purpose = "claim-risk-managed-mlflow" })

  lifecycle {
    prevent_destroy = true
  }
}
resource "aws_iam_role_policy" "mlflow_tracking" {
  name = "claim-risk-mlflow-artifacts"
  role = aws_iam_role.mlflow_tracking.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ControlBucketLocation"
        Effect   = "Allow"
        Action   = "s3:GetBucketLocation"
        Resource = local.control_arn
      },
      {
        Sid      = "ListOnlyMlflowArtifacts"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = local.control_arn
        Condition = {
          StringLike = {
            "s3:prefix" = [local.mlflow_artifact_prefix, "${local.mlflow_artifact_prefix}/*"]
          }
        }
      },
      {
        Sid    = "UseOnlyMlflowArtifacts"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
        ]
        Resource = "${local.control_arn}/${local.mlflow_artifact_prefix}/*"
      },
      {
        Sid      = "UsePlatformKeyOnlyThroughS3"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_sagemaker_mlflow_tracking_server" "claim_risk" {
  tracking_server_name         = local.mlflow_tracking_server_name
  tracking_server_size         = "Small"
  artifact_store_uri           = "s3://${var.control_bucket_name}/${local.mlflow_artifact_prefix}"
  role_arn                     = aws_iam_role.mlflow_tracking.arn
  automatic_model_registration = false
  tags = merge(var.tags, {
    AmazonDataZoneProject   = var.unified_studio_project_id
    Purpose                 = "claim-risk-managed-mlflow"
    ProjectUserTagManagedBy = "Terraform"
    ProjectUserTagWorkload  = "insurance-claim-risk"
  })

  depends_on = [aws_iam_role_policy.mlflow_tracking]

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = var.environment == "dev"
      error_message = "Managed MLflow is authorized only in DEV."
    }
  }
}
