output "pipeline_name" { value = aws_codepipeline.deploy.name }
output "codebuild_project_names" { value = { for key, project in aws_codebuild_project.deploy : key => project.name } }
output "connection_arn" { value = local.connection_arn }
output "connection_status_note" { value = var.github_connection_arn == null ? "PENDING until GitHub App console handshake" : "caller supplied existing connection" }
output "state_bucket" { value = var.state_bucket_name }
output "proof_execution_role_arns" { value = { for key, role in aws_iam_role.proof : key => role.arn } }
