locals {
  registered_locations = {
    lakehouse = var.lakehouse_location_arn
    control   = var.control_location_arn
  }

  data_engineer_databases = var.database_names
  ml_engineer_databases = {
    silver = var.database_names["silver"]
    gold   = var.database_names["gold"]
  }
}

resource "aws_lakeformation_resource" "location" {
  for_each = local.registered_locations

  arn                     = each.value
  role_arn                = var.data_access_role_arn
  use_service_linked_role = false
}

resource "aws_lakeformation_data_lake_settings" "this" {
  admins = var.admin_role_arns
}

resource "aws_lakeformation_permissions" "data_engineer_database" {
  for_each = local.data_engineer_databases

  principal   = var.data_engineer_role_arn
  permissions = ["ALTER", "CREATE_TABLE", "DESCRIBE"]

  database {
    name = each.value
  }
}

resource "aws_lakeformation_permissions" "analyst_gold_database" {
  principal   = var.analyst_role_arn
  permissions = ["DESCRIBE"]

  database {
    name = var.database_names["gold"]
  }
}

resource "aws_lakeformation_permissions" "ml_engineer_database" {
  for_each = local.ml_engineer_databases

  principal   = var.ml_engineer_role_arn
  permissions = ["DESCRIBE"]

  database {
    name = each.value
  }
}
