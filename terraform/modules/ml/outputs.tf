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
