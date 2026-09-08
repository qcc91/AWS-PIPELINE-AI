output "terraform_execution_role_arn" {
  description = "ARN of the Terraform execution role."
  value       = aws_iam_role.terraform_execution.arn
}

output "lakeformation_registration_role_arn" {
  description = "ARN of the Lake Formation data-location registration role."
  value       = aws_iam_role.lakeformation_registration.arn
}
