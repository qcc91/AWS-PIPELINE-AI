module "deployment_proof" {
  source = "../modules/deployment-proof"

  environment           = "prod"
  source_revision       = var.source_revision
  pipeline_execution_id = var.pipeline_execution_id
}
