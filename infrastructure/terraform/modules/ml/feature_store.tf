locals {
  feature_store_base_uri      = "s3://${var.control_bucket_name}/ml/feature-store"
  feature_store_contract_path = abspath("${path.module}/../../../../workloads/ml/claim_risk.py")
  feature_store_schema_script = abspath("${path.module}/../../../../workloads/ml/pipeline/feature_store_schema.py")
  feature_store_definitions   = jsondecode(data.external.claim_risk_feature_schema.result.feature_definitions)
}

data "external" "claim_risk_feature_schema" {
  program = ["python", local.feature_store_schema_script]
  query = {
    adapter_sha256  = filesha256(local.feature_store_schema_script)
    contract_sha256 = filesha256(local.feature_store_contract_path)
  }
}

resource "aws_iam_role" "feature_store" {
  name = "insurance-${var.environment}-claim-risk-feature-store-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "sagemaker.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = merge(var.tags, { Purpose = "claim-risk-offline-feature-store" })
}

resource "aws_iam_role_policy" "feature_store" {
  name = "claim-risk-offline-feature-store"
  role = aws_iam_role.feature_store.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InspectOfflineStoreBucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = local.control_arn
      },
      {
        Sid      = "PersistOfflineFeatureRecords"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:PutObjectAcl"]
        Resource = "${local.control_arn}/ml/feature-store/*"
      },
      {
        Sid      = "EncryptOfflineFeatureRecords"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      },
      {
        Sid    = "MaintainFeatureStoreCatalogMetadata"
        Effect = "Allow"
        Action = ["glue:CreateTable", "glue:GetDatabase", "glue:GetTable", "glue:UpdateTable"]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${var.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${var.account_id}:database/insurance_${var.environment}_control",
          "arn:aws:glue:${var.aws_region}:${var.account_id}:table/insurance_${var.environment}_control/*",
        ]
      },
    ]
  })
}

resource "aws_sagemaker_feature_group" "claim_risk" {
  feature_group_name             = local.feature_group_name
  record_identifier_feature_name = "claim_id"
  event_time_feature_name        = "event_time"
  role_arn                       = aws_iam_role.feature_store.arn
  description                    = "Offline-only, leakage-safe features used by the insurance claim-risk XGBoost workload."

  dynamic "feature_definition" {
    for_each = local.feature_store_definitions
    content {
      feature_name = feature_definition.value.feature_name
      feature_type = feature_definition.value.feature_type
    }
  }

  offline_store_config {
    disable_glue_table_creation = false
    table_format                = "Glue"

    data_catalog_config {
      catalog    = "AwsDataCatalog"
      database   = "insurance_${var.environment}_control"
      table_name = "claim_risk_features_offline"
    }

    s3_storage_config {
      s3_uri     = local.feature_store_base_uri
      kms_key_id = var.kms_key_arn
    }
  }

  tags = merge(var.tags, {
    AmazonDataZoneProject   = var.unified_studio_project_id
    Purpose                 = "claim-risk-offline-feature-store"
    ProjectUserTagManagedBy = "Terraform"
    ProjectUserTagWorkload  = "insurance-claim-risk"
  })

  depends_on = [aws_iam_role_policy.feature_store]
}
