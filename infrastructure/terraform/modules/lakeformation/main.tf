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
  data_location_principals = merge(
    { data_engineer = var.data_engineer_role_arn },
    var.pipeline_role_arns,
  )
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

  # AWS may return an additional aggregate ALL token for an otherwise exact
  # grant. Runtime grant-matrix tests remain authoritative for least privilege.
  lifecycle { ignore_changes = [permissions] }
}

resource "aws_lakeformation_permissions" "analyst_gold_database" {
  principal   = var.analyst_role_arn
  permissions = ["DESCRIBE"]

  database {
    name = var.database_names["gold"]
  }

  lifecycle { ignore_changes = [permissions] }
}

resource "aws_lakeformation_permissions" "ml_engineer_database" {
  for_each = local.ml_engineer_databases

  principal   = var.ml_engineer_role_arn
  permissions = ["DESCRIBE"]

  database {
    name = each.value
  }

  lifecycle { ignore_changes = [permissions] }
}

resource "aws_lakeformation_permissions" "data_engineer_tables" {
  for_each = local.data_engineer_databases

  principal   = var.data_engineer_role_arn
  permissions = ["ALL"]

  table {
    database_name = each.value
    wildcard      = true
  }

  lifecycle { ignore_changes = [permissions] }
}

resource "aws_lakeformation_permissions" "analyst_gold_tables" {
  for_each = var.analyst_gold_tables

  principal   = var.analyst_role_arn
  permissions = ["DESCRIBE", "SELECT"]

  table {
    database_name = var.database_names["gold"]
    name          = each.value
  }

  lifecycle { ignore_changes = [permissions] }
}

resource "aws_lakeformation_permissions" "ml_gold_tables" {
  for_each = var.ml_gold_tables

  principal   = var.ml_engineer_role_arn
  permissions = ["DESCRIBE", "SELECT"]

  table {
    database_name = var.database_names["gold"]
    name          = each.value
  }

  lifecycle { ignore_changes = [permissions] }
}

resource "aws_lakeformation_permissions" "data_location" {
  # Keys are configuration-time constants even though role ARNs are provider
  # outputs, so Terraform can construct these instances during planning.
  for_each = local.data_location_principals

  principal   = each.value
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = var.lakehouse_location_arn
  }

  lifecycle { ignore_changes = [permissions] }
}

# Hybrid-access opt-ins make Lake Formation authoritative for the V3 personas
# while preserving IAM-compatible V2 pipeline roles during the V3 migration.
resource "aws_lakeformation_opt_in" "analyst_gold_tables" {
  for_each = var.analyst_gold_tables

  principal {
    data_lake_principal_identifier = var.analyst_role_arn
  }
  resource_data {
    table {
      database_name = var.database_names["gold"]
      name          = each.value
    }
  }

  depends_on = [aws_lakeformation_permissions.analyst_gold_tables]

  # AWS returns the account catalog ID even when it is omitted from the
  # configuration. Ignore only that computed normalization field; table and
  # principal changes remain managed through the keyed resource instance.
  lifecycle {
    ignore_changes = [resource_data[0].table[0].catalog_id]
  }
}

resource "aws_lakeformation_opt_in" "ml_gold_tables" {
  for_each = var.ml_gold_tables

  principal {
    data_lake_principal_identifier = var.ml_engineer_role_arn
  }
  resource_data {
    table {
      database_name = var.database_names["gold"]
      name          = each.value
    }
  }

  depends_on = [aws_lakeformation_permissions.ml_gold_tables]

  lifecycle {
    ignore_changes = [resource_data[0].table[0].catalog_id]
  }
}
