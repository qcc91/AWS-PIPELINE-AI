locals {
  database_locations = {
    bronze  = "${trimsuffix(var.lakehouse_location_uri, "/")}/bronze/"
    silver  = "${trimsuffix(var.lakehouse_location_uri, "/")}/silver/"
    gold    = "${trimsuffix(var.lakehouse_location_uri, "/")}/gold/"
    control = "${trimsuffix(var.control_location_uri, "/")}/"
  }
}

resource "aws_glue_catalog_database" "layer" {
  for_each = local.database_locations

  name         = "insurance_${var.environment}_${each.key}"
  description  = "${each.key} Iceberg catalog database"
  location_uri = each.value

  tags = merge(var.tags, {
    Layer = each.key
  })
}
