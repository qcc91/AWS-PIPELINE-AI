locals {
  user_name = "insurance-${var.environment}-local-operator"
  role_name = "insurance-${var.environment}-operator-role"
}

# Deliberately no aws_iam_user_login_profile and no aws_iam_access_key.
# The Human Owner sets the initial console password and MFA outside Terraform;
# AWS Sign-In local development then issues short-lived CLI credentials.
resource "aws_iam_user" "operator" {
  name          = local.user_name
  force_destroy = false
  tags          = merge(var.tags, { Persona = "OperatorBootstrap" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_user_policy_attachment" "local_development" {
  user       = aws_iam_user.operator.name
  policy_arn = "arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess"
}

resource "aws_iam_user_policy" "assume_operator" {
  name = "assume-operator-with-mfa-only"
  user = aws_iam_user.operator.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeOperatorWithMfa"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.operator.arn
      Condition = {
        Bool = { "aws:MultiFactorAuthPresent" = "true" }
      }
    }]
  })
}

resource "aws_iam_role" "operator" {
  name                 = local.role_name
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ConsoleOnlyUserWithMfa"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.operator.arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        Bool = { "aws:MultiFactorAuthPresent" = "true" }
      }
    }]
  })
  tags = merge(var.tags, { Persona = "Operator" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "operator" {
  name = "assume-approved-project-roles"
  role = aws_iam_role.operator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeApprovedRoles"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = sort(tolist(var.target_role_arns))
      },
      {
        Sid      = "ReadOwnIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "terraform_execution" {
  name                 = "insurance-${var.environment}-terraform-execution-role"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OperatorTemporarySessionsOnly"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.operator.arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = merge(var.tags, { Persona = "TerraformExecution" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "terraform_execution" {
  name = "manage-approved-v3-security-governance"
  role = aws_iam_role.terraform_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TerraformStateBucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:ListBucket"]
        Resource = var.state_bucket_arn
      },
      {
        Sid      = "TerraformStateObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.state_bucket_arn}/*"
      },
      {
        Sid      = "TerraformStateKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = var.state_kms_key_arn
      },
      {
        Sid      = "ProjectKmsPolicyAdministration"
        Effect   = "Allow"
        Action   = ["kms:CreateGrant", "kms:DescribeKey", "kms:EnableKeyRotation", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListGrants", "kms:ListResourceTags", "kms:PutKeyPolicy", "kms:TagResource", "kms:UntagResource", "kms:UpdateKeyDescription"]
        Resource = sort(tolist(var.platform_kms_key_arns))
      },
      {
        Sid      = "ProjectRoleAdministration"
        Effect   = "Allow"
        Action   = ["iam:CreateRole", "iam:DeleteRole", "iam:DeleteRolePolicy", "iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:ListRolePolicies", "iam:PassRole", "iam:PutRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy", "iam:UpdateRole", "iam:UpdateRoleDescription"]
        Resource = "arn:aws:iam::${var.account_id}:role/insurance-${var.environment}-*"
      },
      {
        Sid      = "V3LakeFormationAdministration"
        Effect   = "Allow"
        Action   = ["lakeformation:BatchGrantPermissions", "lakeformation:BatchRevokePermissions", "lakeformation:DeregisterResource", "lakeformation:GetDataLakeSettings", "lakeformation:GrantPermissions", "lakeformation:ListLakeFormationOptIns", "lakeformation:ListPermissions", "lakeformation:ListResources", "lakeformation:PutDataLakeSettings", "lakeformation:RegisterResource", "lakeformation:RevokePermissions", "lakeformation:CreateLakeFormationOptIn", "lakeformation:DeleteLakeFormationOptIn", "lakeformation:UpdateResource"]
        Resource = "*"
      },
      {
        Sid      = "CloudTrailValidation"
        Effect   = "Allow"
        Action   = ["cloudtrail:DescribeTrails", "cloudtrail:GetEventSelectors", "cloudtrail:GetTrailStatus", "cloudtrail:ListTags", "cloudtrail:UpdateTrail"]
        Resource = "arn:aws:cloudtrail:ap-southeast-2:${var.account_id}:trail/insurance-${var.environment}-management-trail"
      },
      {
        Sid    = "FoundationRefreshMetadata"
        Effect = "Allow"
        Action = [
          "athena:GetNamedQuery", "athena:GetWorkGroup", "athena:ListTagsForResource",
          "bedrock:GetKnowledgeBase", "bedrock:GetDataSource", "cloudwatch:ListTagsForResource",
          "dms:DescribeEndpoints", "dms:DescribeReplicationInstances", "dms:DescribeReplicationSubnetGroups", "dms:DescribeReplicationTasks",
          "ec2:Describe*", "events:DescribeRule", "events:ListTagsForResource", "events:ListTargetsByRule",
          "glue:Get*", "iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:ListRolePolicies",
          "kms:DescribeKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListResourceTags",
          "logs:DescribeLogGroups", "logs:ListTagsForResource", "rds:Describe*",
          "s3:GetAccelerateConfiguration", "s3:GetBucketAcl", "s3:GetBucketCORS", "s3:GetBucketLogging", "s3:GetBucketObjectLockConfiguration", "s3:GetBucketPolicy", "s3:GetBucketPolicyStatus", "s3:GetBucketPublicAccessBlock", "s3:GetBucketRequestPayment", "s3:GetBucketTagging", "s3:GetBucketVersioning", "s3:GetBucketWebsite", "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:GetReplicationConfiguration", "s3:ListBucket",
          "s3vectors:GetIndex", "s3vectors:GetVectorBucket", "sagemaker:DescribeModelPackageGroup", "sagemaker:ListTags",
          "secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy", "secretsmanager:ListSecretVersionIds", "sns:GetTopicAttributes", "sns:ListTagsForResource",
          "states:DescribeStateMachine", "states:ListTagsForResource", "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}
