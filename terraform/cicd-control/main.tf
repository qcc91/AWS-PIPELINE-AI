locals {
  pipeline_name = "insurance-dev-v4b-cd"
  codebuild_names = {
    dev        = "insurance-dev-v4b-deploy-dev"
    prod_plan  = "insurance-dev-v4b-plan-prod"
    prod_apply = "insurance-dev-v4b-apply-prod"
  }
  artifact_bucket = "aip-insurance-dev-v4b-artifacts-dev01"
  connection_arn  = var.github_connection_arn != null ? var.github_connection_arn : aws_codeconnections_connection.github[0].arn
  tags = {
    Project     = "aws-insurance-data-ai-platform"
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "v4b-minimal-cd-proof"
  }
  action_environment = [
    { name = "SOURCE_SHA", value = "#{SourceVariables.CommitId}", type = "PLAINTEXT" },
    { name = "PIPELINE_EXECUTION_ID", value = "#{codepipeline.PipelineExecutionId}", type = "PLAINTEXT" },
  ]
}

resource "aws_codeconnections_connection" "github" {
  count         = var.github_connection_arn == null ? 1 : 0
  name          = "insurance-dev-v4b-github"
  provider_type = "GitHub"
  tags          = local.tags
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifact_bucket
  force_destroy = false
  tags          = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "all" {
  for_each = { artifacts = aws_s3_bucket.artifacts.id }
  bucket   = each.value

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "all" {
  for_each = { artifacts = aws_s3_bucket.artifacts.id }
  bucket   = each.value

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "all" {
  for_each                = { artifacts = aws_s3_bucket.artifacts.id }
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "all" {
  for_each = { artifacts = aws_s3_bucket.artifacts.id }
  bucket   = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "all" {
  for_each = { artifacts = aws_s3_bucket.artifacts.id }
  bucket   = each.value

  depends_on = [aws_s3_bucket_versioning.all]

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "all" {
  for_each = { artifacts = aws_s3_bucket.artifacts.id }
  bucket   = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["arn:aws:s3:::${each.value}", "arn:aws:s3:::${each.value}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "DenyIncorrectExplicitEncryption"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${each.value}/*"
        Condition = {
          StringNotEquals = { "s3:x-amz-server-side-encryption" = "AES256" }
          Null            = { "s3:x-amz-server-side-encryption" = "false" }
        }
      },
    ]
  })
}

resource "aws_iam_role" "codepipeline" {
  name = "insurance-dev-v4b-codepipeline-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codepipeline.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.tags
}

resource "aws_iam_role" "codebuild" {
  for_each = toset(["dev", "prod_plan", "prod_apply"])
  name     = "insurance-dev-v4b-codebuild-${replace(each.key, "_", "-")}-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = merge(local.tags, { ExecutionBoundary = each.key })
}

resource "aws_iam_role" "proof" {
  for_each = toset(["dev", "prod_plan", "prod_apply"])
  name     = "insurance-dev-v4b-proof-${replace(each.key, "_", "-")}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.codebuild[each.key].arn }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = merge(local.tags, { ExecutionBoundary = each.key })
}

resource "aws_iam_role_policy" "proof" {
  for_each = aws_iam_role.proof
  name     = "v4b-${replace(each.key, "_", "-")}-proof"
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateBucketMetadata"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.state_bucket_name}"
        Condition = {
          StringLike = { "s3:prefix" = ["cicd-proof/${startswith(each.key, "prod") ? "prod" : "dev"}/terraform.tfstate*"] }
        }
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.state_bucket_name}/cicd-proof/${startswith(each.key, "prod") ? "prod" : "dev"}/terraform.tfstate"
      },
      {
        Sid      = "DecryptState"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = var.state_kms_key_arn
      },
      {
        Sid      = "ValidateProofLogGroup"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      {
        Sid      = "ReadProofLogGroupTags"
        Effect   = "Allow"
        Action   = "logs:ListTagsForResource"
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/insurance-cicd-proof/${startswith(each.key, "prod") ? "prod" : "dev"}"
      },
    ]
  })
}

resource "aws_iam_role_policy" "proof_write" {
  for_each = { for key, role in aws_iam_role.proof : key => role if key != "prod_plan" }
  name     = "v4b-${replace(each.key, "_", "-")}-proof-write"
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteStateAndLock"
        Effect = "Allow"
        Action = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
        Resource = [
          "arn:aws:s3:::${var.state_bucket_name}/cicd-proof/${each.key == "dev" ? "dev" : "prod"}/terraform.tfstate",
          "arn:aws:s3:::${var.state_bucket_name}/cicd-proof/${each.key == "dev" ? "dev" : "prod"}/terraform.tfstate.tflock",
        ]
      },
      {
        Sid      = "EncryptState"
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:GenerateDataKey"]
        Resource = var.state_kms_key_arn
      },
      {
        Sid      = "CreateTaggedProofLogGroup"
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestTag/Purpose" = "v4b-deployment-proof" }
        }
      },
      {
        Sid    = "ManageExactProofLogGroup"
        Effect = "Allow"
        Action = ["logs:DeleteLogGroup", "logs:ListTagsForResource", "logs:PutRetentionPolicy", "logs:TagResource", "logs:UntagResource"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/insurance-cicd-proof/${each.key == "dev" ? "dev" : "prod"}",
          "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/insurance-cicd-proof/${each.key == "dev" ? "dev" : "prod"}:*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "v4b-artifacts-source-and-build"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:ListBucket"], Resource = aws_s3_bucket.artifacts.arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"], Resource = "${aws_s3_bucket.artifacts.arn}/*" },
      { Effect = "Allow", Action = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"], Resource = [for project in aws_codebuild_project.deploy : project.arn] },
      { Effect = "Allow", Action = "codeconnections:UseConnection", Resource = local.connection_arn },
    ]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  for_each = aws_iam_role.codebuild
  name     = "v4b-logs-artifacts-and-assume"
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.codebuild[each.key].arn}:*" },
      { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:ListBucket"], Resource = aws_s3_bucket.artifacts.arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"], Resource = "${aws_s3_bucket.artifacts.arn}/*" },
      { Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.proof[each.key].arn },
    ]
  })
}

resource "aws_cloudwatch_log_group" "codebuild" {
  for_each          = local.codebuild_names
  name              = "/aws/codebuild/${each.value}"
  retention_in_days = 30
  tags              = merge(local.tags, { ExecutionBoundary = each.key })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_codebuild_project" "deploy" {
  for_each      = local.codebuild_names
  name          = each.value
  service_role  = aws_iam_role.codebuild[each.key].arn
  build_timeout = 15

  artifacts { type = "CODEPIPELINE" }
  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/v4b-minimal-cd.yml"
  }
  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.codebuild[each.key].name
    }
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "TARGET_TERRAFORM_EXECUTION_ROLE_ARN"
      value = aws_iam_role.proof[each.key].arn
    }
    environment_variable {
      name  = "STATE_BUCKET"
      value = var.state_bucket_name
    }
    environment_variable {
      name  = "STATE_KMS_KEY_ARN"
      value = var.state_kms_key_arn
    }
  }
  tags = merge(local.tags, { ExecutionBoundary = each.key })
}

resource "aws_codepipeline" "deploy" {
  name           = local.pipeline_name
  role_arn       = aws_iam_role.codepipeline.arn
  pipeline_type  = "V1"
  execution_mode = "SUPERSEDED"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "ProtectedMain"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      namespace        = "SourceVariables"
      configuration = {
        ConnectionArn    = local.connection_arn
        FullRepositoryId = "${var.github_owner}/${var.github_repository}"
        BranchName       = "main"
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "DEVPlan"
    action {
      name             = "DEVPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["DevPlanOutput"]
      configuration = {
        ProjectName          = aws_codebuild_project.deploy["dev"].name
        PrimarySource        = "SourceOutput"
        EnvironmentVariables = jsonencode(concat(local.action_environment, [{ name = "CD_ACTION", value = "DEV_PLAN", type = "PLAINTEXT" }]))
      }
    }
  }

  stage {
    name = "DEVApply"
    action {
      name            = "DEVApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput", "DevPlanOutput"]
      configuration = {
        ProjectName          = aws_codebuild_project.deploy["dev"].name
        PrimarySource        = "SourceOutput"
        EnvironmentVariables = jsonencode(concat(local.action_environment, [{ name = "CD_ACTION", value = "DEV_APPLY", type = "PLAINTEXT" }]))
      }
    }
  }

  stage {
    name = "DEVValidate"
    action {
      name            = "DEVValidate"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]
      configuration = {
        ProjectName          = aws_codebuild_project.deploy["dev"].name
        PrimarySource        = "SourceOutput"
        EnvironmentVariables = jsonencode(concat(local.action_environment, [{ name = "CD_ACTION", value = "DEV_VALIDATE", type = "PLAINTEXT" }]))
      }
    }
  }

  stage {
    name = "PRODPlan"
    action {
      name             = "PRODPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      namespace        = "ProdPlanVariables"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["ProdPlanOutput"]
      configuration = {
        ProjectName          = aws_codebuild_project.deploy["prod_plan"].name
        PrimarySource        = "SourceOutput"
        EnvironmentVariables = jsonencode(concat(local.action_environment, [{ name = "CD_ACTION", value = "PROD_PLAN", type = "PLAINTEXT" }]))
      }
    }
  }

  stage {
    name = "PRODApproval"
    action {
      name     = "ApproveExactPlan"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
      configuration = {
        CustomData = "Source=#{SourceVariables.CommitId}; Execution=#{codepipeline.PipelineExecutionId}; PlanSHA256=#{ProdPlanVariables.PLAN_SHA256}; Changes=create #{ProdPlanVariables.PLAN_CREATE_COUNT}, update #{ProdPlanVariables.PLAN_UPDATE_COUNT}, delete #{ProdPlanVariables.PLAN_DELETE_COUNT}, replace #{ProdPlanVariables.PLAN_REPLACE_COUNT}. Approve this exact binary plan only."
      }
    }
  }

  stage {
    name = "PRODApply"
    action {
      name            = "ApplyApprovedBinaryPlan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput", "ProdPlanOutput"]
      configuration = {
        ProjectName   = aws_codebuild_project.deploy["prod_apply"].name
        PrimarySource = "SourceOutput"
        EnvironmentVariables = jsonencode(concat(local.action_environment, [
          { name = "CD_ACTION", value = "PROD_APPLY", type = "PLAINTEXT" },
          { name = "EXPECTED_PLAN_SHA256", value = "#{ProdPlanVariables.PLAN_SHA256}", type = "PLAINTEXT" },
        ]))
      }
    }
  }

  tags = local.tags
}
