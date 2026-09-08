output "database_names" {
  description = "Map of bronze, silver, gold, and control database names."
  value = {
    for layer, database in aws_glue_catalog_database.layer : layer => database.name
  }
}

output "database_location_uris" {
  description = "Map of the four distinct Glue database S3 locations."
  value       = local.database_locations
}
