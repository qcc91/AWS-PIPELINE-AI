module "deployment_proof" {
  source = "../modules/deployment-proof"

  environment           = "dev"
  source_revision       = var.source_revision
  pipeline_execution_id = var.pipeline_execution_id
}
