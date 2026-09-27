terraform {
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

locals {
  pipeline_name              = "insurance-${var.environment}-claim-risk"
  pipeline_code_uri          = "s3://${var.control_bucket_name}/artifacts/ml/pipeline"
  pipeline_base_uri          = "s3://${var.control_bucket_name}/ml/pipeline"
  pipeline_definition_script = abspath("${path.module}/../../../../workloads/ml/pipeline/pipeline_definition.py")
}

# Python owns the ML workflow semantics. Terraform supplies environment-specific
# control-plane values and registers the resulting native SageMaker definition.
data "external" "claim_risk_pipeline_definition" {
  program = ["python", local.pipeline_definition_script]

  query = {
    aws_region               = var.aws_region
    athena_workgroup_name    = var.athena_workgroup_name
    code_uri                 = local.pipeline_code_uri
    definition_sha256        = filesha256(local.pipeline_definition_script)
    gold_database_name       = var.gold_database_name
    glue_job_name            = aws_glue_job.postprocess.name
    kms_key_arn              = var.kms_key_arn
    model_package_group_name = aws_sagemaker_model_package_group.claim_fraud.model_package_group_name
    output_prefix            = local.pipeline_base_uri
    processing_image_uri     = var.processing_image_uri
    role_arn                 = aws_iam_role.sagemaker.arn
    xgboost_image_uri        = var.xgboost_image_uri
  }
}

resource "aws_sagemaker_pipeline" "claim_risk" {
  pipeline_name         = local.pipeline_name
  pipeline_display_name = "Insurance-${upper(var.environment)}-Claim-Risk"
  pipeline_description  = "Prepare, train, evaluate, register, batch-score, publish and validate claim risk."
  role_arn              = aws_iam_role.sagemaker.arn
  pipeline_definition   = data.external.claim_risk_pipeline_definition.result.pipeline_definition
  tags = merge(var.tags, {
    AmazonDataZoneProject   = var.unified_studio_project_id
    Purpose                 = "claim-risk-managed-ml-pipeline"
    ProjectUserTagManagedBy = "Terraform"
    ProjectUserTagWorkload  = "insurance-claim-risk"
  })

  depends_on = [
    aws_iam_role_policy.sagemaker,
    aws_s3_object.pipeline_asset,
    aws_sagemaker_model_package_group.claim_fraud,
  ]
}
