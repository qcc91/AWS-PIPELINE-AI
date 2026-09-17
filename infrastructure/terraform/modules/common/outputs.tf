output "tags" {
  description = "Canonical tags for all persistent resources."
  value = {
    Project            = "aws-insurance-data-ai"
    Environment        = var.environment
    Owner              = var.owner
    ManagedBy          = "terraform"
    CostCenter         = var.cost_center
    DataClassification = var.data_classification
  }
}
