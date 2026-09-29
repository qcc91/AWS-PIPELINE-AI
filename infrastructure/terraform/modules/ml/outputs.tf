output "sagemaker_role_arn" {
  description = "On-demand SageMaker execution role ARN."
  value       = aws_iam_role.sagemaker.arn
}
output "model_package_group_name" {
  description = "Claim-fraud model package group name."
  value       = aws_sagemaker_model_package_group.claim_fraud.model_package_group_name
}
output "xgboost_version" {
  description = "AWS-published XGBoost framework version."
  value       = var.xgboost_version
}
output "postprocess_job_name" {
  description = "Glue job that materializes Gold claim_risk Iceberg output."
  value       = aws_glue_job.postprocess.name
}
output "postprocess_role_arn" {
  description = "Claim-risk Glue postprocess execution role ARN."
  value       = aws_iam_role.postprocess.arn
}

output "pipeline_name" {
  description = "Terraform-managed SageMaker Pipeline visible in the SageMaker Pipelines console."
  value       = aws_sagemaker_pipeline.claim_risk.pipeline_name
}

output "pipeline_arn" {
  description = "Claim-risk SageMaker Pipeline ARN."
  value       = aws_sagemaker_pipeline.claim_risk.arn
}

output "feature_group_name" {
  description = "Offline-only claim-risk Feature Group name."
  value       = aws_sagemaker_feature_group.claim_risk.feature_group_name
}

output "feature_group_arn" {
  description = "Offline-only claim-risk Feature Group ARN."
  value       = aws_sagemaker_feature_group.claim_risk.arn
}

output "feature_group_offline_store_uri" {
  description = "Resolved S3 location where Feature Store persists offline Parquet records."
  value       = aws_sagemaker_feature_group.claim_risk.offline_store_config[0].s3_storage_config[0].resolved_output_s3_uri
}

output "feature_store_role_arn" {
  description = "Least-privilege role used by SageMaker to persist offline feature records."
  value       = aws_iam_role.feature_store.arn
}

output "mlflow_tracking_role_arn" {
  description = "Least-privilege service role for the Managed MLflow artifact store."
  value       = aws_iam_role.mlflow_tracking.arn
}

output "mlflow_tracking_server_name" {
  description = "Small DEV Managed MLflow tracking server name."
  value       = aws_sagemaker_mlflow_tracking_server.claim_risk.tracking_server_name
}

output "mlflow_tracking_server_arn" {
  description = "Small DEV Managed MLflow tracking server ARN."
  value       = aws_sagemaker_mlflow_tracking_server.claim_risk.arn
}

output "mlflow_tracking_server_url" {
  description = "Managed MLflow tracking URL used by authenticated MLflow clients."
  value       = aws_sagemaker_mlflow_tracking_server.claim_risk.tracking_server_url
}
