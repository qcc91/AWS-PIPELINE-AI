resource "aws_cloudwatch_log_group" "proof" {
  name              = "/aws/insurance-cicd-proof/${var.environment}"
  retention_in_days = 30

  tags = {
    Project             = "aws-insurance-data-ai-platform"
    Environment         = var.environment
    ManagedBy           = "terraform"
    Purpose             = "v4b-deployment-proof"
    SourceRevision      = var.source_revision
    PipelineExecutionId = var.pipeline_execution_id
  }

  lifecycle {
    prevent_destroy = true
  }
}
