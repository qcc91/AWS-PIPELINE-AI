locals {
  workgroup_name  = "insurance-${var.environment}-bi"
  query_results   = "s3://${var.control_bucket_name}/athena-results/"
  data_source_arn = "arn:aws:quicksight:${var.aws_region}:${coalesce(var.quicksight_account_id, var.account_id)}:datasource/${var.quicksight_data_source_id}"
}

resource "aws_athena_workgroup" "bi" {
  name = local.workgroup_name
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    result_configuration {
      output_location = local.query_results
      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = var.kms_key_arn
      }
    }
  }
  tags = merge(var.tags, { Purpose = "bi-athena" })
}

resource "aws_athena_named_query" "fact_claim" {
  name      = "insurance-${var.environment}-bi-fact-claim"
  database  = var.gold_database_name
  workgroup = aws_athena_workgroup.bi.name
  query     = file("${path.module}/../../../sql/bi/fact_claim.sql")
}

resource "aws_athena_named_query" "claim_daily_summary" {
  name      = "insurance-${var.environment}-bi-claim-daily-summary"
  database  = var.gold_database_name
  workgroup = aws_athena_workgroup.bi.name
  query     = file("${path.module}/../../../sql/bi/claim_daily_summary.sql")
}

resource "aws_quicksight_data_source" "athena" {
  count          = var.enable_quicksight ? 1 : 0
  aws_account_id = var.quicksight_account_id
  data_source_id = var.quicksight_data_source_id
  name           = "insurance-${var.environment}-athena"
  type           = "ATHENA"
  ssl_properties {
    disable_ssl = false
  }
  parameters {
    athena {
      work_group = aws_athena_workgroup.bi.name
    }
  }
  permission {
    principal = var.quicksight_user_arn
    actions   = ["quicksight:DescribeDataSource", "quicksight:DescribeDataSourcePermissions", "quicksight:PassDataSource"]
  }
  tags = var.tags
}

resource "aws_quicksight_data_set" "fact_claim" {
  count          = var.enable_quicksight ? 1 : 0
  aws_account_id = var.quicksight_account_id
  data_set_id    = "insurance-${var.environment}-fact-claim"
  name           = "${var.environment} fact claim"
  import_mode    = "DIRECT_QUERY"
  physical_table_map {
    physical_table_map_id = "fact_claim"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena[0].arn
      catalog         = "AwsDataCatalog"
      schema          = var.gold_database_name
      name            = "fact_claim"
      input_columns {
        name = "claim_id"
        type = "STRING"
      }
      input_columns {
        name = "claim_status"
        type = "STRING"
      }
      input_columns {
        name = "claim_amount"
        type = "DECIMAL"
      }
      input_columns {
        name = "approved_amount"
        type = "DECIMAL"
      }
      input_columns {
        name = "submitted_at"
        type = "DATETIME"
      }
      input_columns {
        name = "currency_code"
        type = "STRING"
      }
    }
  }
  permissions {
    principal = var.quicksight_user_arn
    actions   = ["quicksight:DescribeDataSet", "quicksight:DescribeDataSetPermissions", "quicksight:PassDataSet", "quicksight:UpdateDataSet"]
  }
  tags = var.tags
}

output "athena_workgroup_name" {
  description = "Encrypted V1 BI Athena workgroup name."
  value       = aws_athena_workgroup.bi.name
}
output "fact_claim_named_query_id" {
  description = "Named-query ID for the Gold claim fact."
  value       = aws_athena_named_query.fact_claim.id
}
output "claim_daily_summary_named_query_id" {
  description = "Named-query ID for the Gold daily claim summary."
  value       = aws_athena_named_query.claim_daily_summary.id
}
output "quicksight_enabled" {
  description = "Whether optional QuickSight resources are enabled."
  value       = var.enable_quicksight
}
