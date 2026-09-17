output "role_arns" {
  value = {
    Operator                  = var.operator_role_arn
    TerraformExecution        = var.terraform_execution_role_arn
    DataEngineer              = aws_iam_role.data_engineer.arn
    Analyst                   = aws_iam_role.analyst.arn
    MLEngineer                = aws_iam_role.ml_engineer.arn
    RAGApplication            = aws_iam_role.rag_application.arn
    LakeFormationRegistration = aws_iam_role.lakeformation_registration.arn
  }
}
