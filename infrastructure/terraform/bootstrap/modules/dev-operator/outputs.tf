output "user_name" {
  value = aws_iam_user.operator.name
}

output "user_arn" {
  value = aws_iam_user.operator.arn
}

output "operator_role_arn" {
  value = aws_iam_role.operator.arn
}

output "terraform_execution_role_arn" {
  value = aws_iam_role.terraform_execution.arn
}
