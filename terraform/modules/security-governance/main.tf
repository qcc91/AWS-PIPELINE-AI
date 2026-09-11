locals {
  role_prefix = "insurance-${var.environment}"
  operator_assumable_role_arns = [
    aws_iam_role.terraform_execution.arn,
    aws_iam_role.data_engineer.arn,
    aws_iam_role.analyst.arn,
    aws_iam_role.ml_engineer.arn,
    aws_iam_role.rag_application.arn,
  ]
  operator_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ExistingFederatedOperatorOnly"
      Effect    = "Allow"
      Principal = { AWS = var.operator_trusted_principal_arns }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  persona_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OperatorTemporarySessionsOnly"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.operator.arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  landing_arn     = var.bucket_arns["landing"]
  lakehouse_arn   = var.bucket_arns["lakehouse"]
  control_arn     = var.bucket_arns["control"]
  quarantine_arn  = var.bucket_arns["quarantine"]
  documents_arn   = var.bucket_arns["documents"]
  gold_tables_arn = "arn:aws:glue:${var.aws_region}:${var.account_id}:table/${var.glue_database_names["gold"]}/*"
  catalog_arn     = "arn:aws:glue:${var.aws_region}:${var.account_id}:catalog"
}

resource "aws_iam_role" "operator" {
  name                 = "${local.role_prefix}-operator-role"
  max_session_duration = 3600
  assume_role_policy   = local.operator_trust
  tags                 = merge(var.tags, { Persona = "Operator" })
  lifecycle { prevent_destroy = true }
}

resource "aws_iam_role_policy" "operator" {
  name = "assume-approved-project-roles"
  role = aws_iam_role.operator.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "AssumeApprovedRoles", Effect = "Allow", Action = "sts:AssumeRole", Resource = local.operator_assumable_role_arns },
    { Sid = "ReadOwnIdentity", Effect = "Allow", Action = "sts:GetCallerIdentity", Resource = "*" }
  ] })
}

resource "aws_iam_role" "terraform_execution" {
  name                 = "${local.role_prefix}-terraform-execution-role"
  max_session_duration = 3600
  assume_role_policy   = local.persona_trust
  tags                 = merge(var.tags, { Persona = "TerraformExecution" })
  lifecycle { prevent_destroy = true }
}

resource "aws_iam_role_policy" "terraform_execution" {
  name = "manage-approved-dev-platform"
  role = aws_iam_role.terraform_execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "StateBucket", Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:ListBucket"], Resource = var.state_bucket_arn },
    { Sid = "StateObjects", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${var.state_bucket_arn}/*" },
    { Sid = "StateKey", Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"], Resource = var.state_kms_key_arn },
    { Sid = "ProjectKmsAdministration", Effect = "Allow", Action = ["kms:CreateGrant", "kms:DescribeKey", "kms:EnableKeyRotation", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListGrants", "kms:ListResourceTags", "kms:PutKeyPolicy", "kms:TagResource", "kms:UntagResource", "kms:UpdateKeyDescription"], Resource = [var.platform_kms_key_arn, var.audit_kms_key_arn, var.state_kms_key_arn] },
    { Sid = "ProjectRoleAdministration", Effect = "Allow", Action = ["iam:CreateRole", "iam:DeleteRole", "iam:DeleteRolePolicy", "iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:ListRolePolicies", "iam:PassRole", "iam:PutRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy", "iam:UpdateRole", "iam:UpdateRoleDescription"], Resource = "arn:aws:iam::${var.account_id}:role/${local.role_prefix}-*" },
    { Sid = "ProjectResourceManagement", Effect = "Allow", Action = ["athena:GetNamedQuery", "athena:GetWorkGroup", "athena:ListTagsForResource", "bedrock:GetKnowledgeBase", "cloudtrail:DescribeTrails", "cloudtrail:GetEventSelectors", "cloudtrail:GetTrailStatus", "cloudwatch:ListTagsForResource", "dms:DescribeEndpoints", "dms:DescribeReplicationInstances", "dms:DescribeReplicationSubnetGroups", "dms:DescribeReplicationTasks", "ec2:DescribeAvailabilityZones", "ec2:DescribeRouteTables", "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeVpcEndpoints", "ec2:DescribeVpcs", "events:DescribeRule", "events:ListTagsForResource", "events:ListTargetsByRule", "glue:GetConnection", "glue:GetDatabase", "glue:GetDatabases", "glue:GetJob", "glue:GetTags", "glue:GetTable", "glue:GetTables", "lakeformation:BatchGrantPermissions", "lakeformation:BatchRevokePermissions", "lakeformation:DeregisterResource", "lakeformation:GetDataLakeSettings", "lakeformation:GrantPermissions", "lakeformation:ListPermissions", "lakeformation:ListResources", "lakeformation:PutDataLakeSettings", "lakeformation:RegisterResource", "lakeformation:RevokePermissions", "logs:DescribeLogGroups", "logs:ListTagsForResource", "rds:DescribeDBInstances", "rds:DescribeDBParameterGroups", "rds:DescribeDBSubnetGroups", "s3vectors:GetIndex", "s3vectors:GetVectorBucket", "sagemaker:DescribeModelPackageGroup", "secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy", "secretsmanager:ListSecretVersionIds", "sns:GetTopicAttributes", "sns:ListTagsForResource", "states:DescribeStateMachine", "states:ListTagsForResource", "sts:GetCallerIdentity"], Resource = "*" }
  ] })
}

resource "aws_iam_role" "data_engineer" {
  name                 = "${local.role_prefix}-data-engineer-role"
  max_session_duration = 3600
  assume_role_policy   = local.persona_trust
  tags                 = merge(var.tags, { Persona = "DataEngineer" })
  lifecycle { prevent_destroy = true }
}

resource "aws_iam_role_policy" "data_engineer" {
  name = "operate-approved-data-platform"
  role = aws_iam_role.data_engineer.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "ListProjectData", Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = [local.landing_arn, local.lakehouse_arn, local.control_arn, local.quarantine_arn] },
    { Sid = "OperateProjectData", Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject"], Resource = ["${local.landing_arn}/*", "${local.lakehouse_arn}/*", "${local.control_arn}/*", "${local.quarantine_arn}/*"] },
    { Sid = "UsePlatformKey", Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey", "kms:ReEncryptFrom", "kms:ReEncryptTo"], Resource = var.platform_kms_key_arn },
    { Sid = "RunProjectGlue", Effect = "Allow", Action = ["glue:GetJob", "glue:GetJobRun", "glue:GetJobRuns", "glue:StartJobRun", "glue:StopJobRun"], Resource = [for name in concat(values(var.batch_glue_job_names), values(var.cdc_glue_job_names)) : "arn:aws:glue:${var.aws_region}:${var.account_id}:job/${name}"] },
    { Sid = "CatalogAndGovernance", Effect = "Allow", Action = ["glue:CreateTable", "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:UpdateTable", "lakeformation:GetDataAccess"], Resource = "*" },
    { Sid = "RunPipelines", Effect = "Allow", Action = ["states:DescribeExecution", "states:DescribeStateMachine", "states:ListExecutions", "states:StartExecution"], Resource = [var.batch_state_machine_arn, var.cdc_state_machine_arn, "${replace(var.batch_state_machine_arn, ":stateMachine:", ":execution:")}:*", "${replace(var.cdc_state_machine_arn, ":stateMachine:", ":execution:")}:*"] },
    { Sid = "EngineeringAthena", Effect = "Allow", Action = ["athena:GetQueryExecution", "athena:GetQueryResults", "athena:StartQueryExecution", "athena:StopQueryExecution"], Resource = "arn:aws:athena:${var.aws_region}:${var.account_id}:workgroup/${var.athena_workgroup_name}" },
    { Sid = "ReadDatabaseSecret", Effect = "Allow", Action = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"], Resource = var.rds_secret_arn },
    { Sid = "OperationalVisibility", Effect = "Allow", Action = ["dms:DescribeReplicationTasks", "events:DescribeRule", "events:ListTargetsByRule", "sts:GetCallerIdentity"], Resource = "*" }
  ] })
}

resource "aws_iam_role" "analyst" {
  name                 = "${local.role_prefix}-analyst-role"
  max_session_duration = 3600
  assume_role_policy   = local.persona_trust
  tags                 = merge(var.tags, { Persona = "Analyst" })
  lifecycle { prevent_destroy = true }
}

resource "aws_iam_role_policy" "analyst" {
  name = "query-approved-gold-without-pii"
  role = aws_iam_role.analyst.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "QueryBIWorkgroup", Effect = "Allow", Action = ["athena:GetQueryExecution", "athena:GetQueryResults", "athena:StartQueryExecution", "athena:StopQueryExecution"], Resource = "arn:aws:athena:${var.aws_region}:${var.account_id}:workgroup/${var.athena_workgroup_name}" },
    { Sid = "ReadGoldCatalog", Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTable", "glue:GetTables", "lakeformation:GetDataAccess"], Resource = [local.catalog_arn, "arn:aws:glue:${var.aws_region}:${var.account_id}:database/${var.glue_database_names["gold"]}", local.gold_tables_arn] },
    { Sid = "AthenaResults", Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = local.control_arn, Condition = { StringLike = { "s3:prefix" = ["athena-results", "athena-results/*"] } } },
    { Sid = "AthenaResultObjects", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"], Resource = "${local.control_arn}/athena-results/*" },
    { Sid = "DecryptApprovedData", Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"], Resource = var.platform_kms_key_arn },
    { Sid = "DenyRawAndSecrets", Effect = "Deny", Action = ["s3:GetObject", "s3:ListBucket"], Resource = [local.landing_arn, "${local.landing_arn}/*", "${local.lakehouse_arn}/lakehouse/bronze/*", "${local.lakehouse_arn}/lakehouse/silver/*"] },
    { Sid = "DenySecrets", Effect = "Deny", Action = "secretsmanager:GetSecretValue", Resource = "*" },
    { Sid = "ReadOwnIdentity", Effect = "Allow", Action = "sts:GetCallerIdentity", Resource = "*" }
  ] })
}

resource "aws_iam_role" "ml_engineer" {
  name                 = "${local.role_prefix}-ml-engineer-role"
  max_session_duration = 3600
  assume_role_policy   = local.persona_trust
  tags                 = merge(var.tags, { Persona = "MLEngineer" })
  lifecycle { prevent_destroy = true }
}

resource "aws_iam_role_policy" "ml_engineer" {
  name = "approved-claim-risk-batch-ml"
  role = aws_iam_role.ml_engineer.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "UseMLArtifacts", Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"], Resource = "${local.control_arn}/ml/*" },
    { Sid = "ListApprovedMLArtifacts", Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = local.control_arn, Condition = { StringLike = { "s3:prefix" = ["ml", "ml/*", "athena-results", "athena-results/*"] } } },
    { Sid = "AthenaResultObjects", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"], Resource = "${local.control_arn}/athena-results/*" },
    { Sid = "UsePlatformKey", Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"], Resource = var.platform_kms_key_arn },
    { Sid = "RunBatchML", Effect = "Allow", Action = ["sagemaker:CreateModel", "sagemaker:CreateTrainingJob", "sagemaker:CreateTransformJob", "sagemaker:DeleteModel", "sagemaker:DescribeModel", "sagemaker:DescribeTrainingJob", "sagemaker:DescribeTransformJob", "sagemaker:ListTags", "sagemaker:StopTrainingJob", "sagemaker:StopTransformJob", "sagemaker:TagResource"], Resource = ["arn:aws:sagemaker:${var.aws_region}:${var.account_id}:model/insurance-${var.environment}-*", "arn:aws:sagemaker:${var.aws_region}:${var.account_id}:training-job/insurance-${var.environment}-*", "arn:aws:sagemaker:${var.aws_region}:${var.account_id}:transform-job/insurance-${var.environment}-*"] },
    { Sid = "PassOnlyMLExecutionRole", Effect = "Allow", Action = "iam:PassRole", Resource = var.sagemaker_execution_role_arn, Condition = { StringEquals = { "iam:PassedToService" = "sagemaker.amazonaws.com" } } },
    { Sid = "ReadMLCatalog", Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTable", "lakeformation:GetDataAccess"], Resource = "*" },
    { Sid = "QueryApprovedMLData", Effect = "Allow", Action = ["athena:GetQueryExecution", "athena:GetQueryResults", "athena:StartQueryExecution", "athena:StopQueryExecution"], Resource = "arn:aws:athena:${var.aws_region}:${var.account_id}:workgroup/${var.athena_workgroup_name}" },
    { Sid = "DenyCustomerRaw", Effect = "Deny", Action = "s3:GetObject", Resource = ["${local.landing_arn}/*", "${local.lakehouse_arn}/lakehouse/bronze/*", "${local.lakehouse_arn}/lakehouse/silver/customers/*"] },
    { Sid = "DenySecrets", Effect = "Deny", Action = "secretsmanager:GetSecretValue", Resource = "*" },
    { Sid = "ReadOwnIdentity", Effect = "Allow", Action = "sts:GetCallerIdentity", Resource = "*" }
  ] })
}

resource "aws_iam_role" "rag_application" {
  name                 = "${local.role_prefix}-rag-application-role"
  max_session_duration = 3600
  assume_role_policy   = local.persona_trust
  tags                 = merge(var.tags, { Persona = "RAGApplication" })
  lifecycle { prevent_destroy = true }
}

resource "aws_iam_role_policy" "rag_application" {
  name = "approved-documents-and-knowledge-base"
  role = aws_iam_role.rag_application.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "RetrieveKnowledgeBase", Effect = "Allow", Action = "bedrock:Retrieve", Resource = "arn:aws:bedrock:${var.aws_region}:${var.account_id}:knowledge-base/${var.rag_knowledge_base_id}" },
    { Sid = "RetrieveAndGenerate", Effect = "Allow", Action = "bedrock:RetrieveAndGenerate", Resource = "*" },
    { Sid = "InvokeApprovedModels", Effect = "Allow", Action = "bedrock:InvokeModel", Resource = var.rag_generation_model_arns },
    { Sid = "DenyStructuredLakehouse", Effect = "Deny", Action = ["s3:GetObject", "s3:ListBucket"], Resource = [local.landing_arn, "${local.landing_arn}/*", local.lakehouse_arn, "${local.lakehouse_arn}/*"] },
    { Sid = "DenySecrets", Effect = "Deny", Action = "secretsmanager:GetSecretValue", Resource = "*" },
    { Sid = "ReadOwnIdentity", Effect = "Allow", Action = "sts:GetCallerIdentity", Resource = "*" }
  ] })
}

resource "aws_iam_role" "lakeformation_registration" {
  name               = "${local.role_prefix}-lakeformation-registration-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "lakeformation.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = merge(var.tags, { Persona = "LakeFormationRegistration" })
  lifecycle { prevent_destroy = true }
}

resource "aws_iam_role_policy" "lakeformation_registration" {
  name = "registered-lakehouse-access"
  role = aws_iam_role.lakeformation_registration.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = [local.lakehouse_arn, local.control_arn] },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${local.lakehouse_arn}/lakehouse/*", "${local.control_arn}/control/*"] },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"], Resource = var.platform_kms_key_arn }
  ] })
}
