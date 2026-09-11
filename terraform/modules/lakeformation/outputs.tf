output "registered_location_arns" {
  description = "Map of the two explicitly registered Lake Formation S3 locations."
  value = {
    for name, resource in aws_lakeformation_resource.location : name => resource.arn
  }
}

output "database_metadata_permission_matrix" {
  description = "Database-level metadata permission scope; no table, column, or SELECT grants are created."
  value = {
    DataEngineer   = sort(keys(local.data_engineer_databases))
    Analyst        = ["gold"]
    MLEngineer     = sort(keys(local.ml_engineer_databases))
    RAGApplication = []
  }
}

output "tag_contract" {
  description = "Validated integration tags; current Lake Formation settings, registrations, and grants do not expose tags."
  value       = var.tags
}

output "table_select_permission_matrix" {
  description = "Explicit V3 table SELECT grants."
  value = {
    Analyst        = sort(tolist(var.analyst_gold_tables))
    MLEngineer     = sort(tolist(var.ml_gold_tables))
    RAGApplication = []
  }
}
