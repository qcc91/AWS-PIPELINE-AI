resource "aws_kms_key" "this" {
  description             = "${var.environment} ${var.purpose} customer-managed key"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      var.allow_root_for_v1 ? [{ Sid = "EnableV1RootScopedAccess", Effect = "Allow", Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }, Action = ["kms:CancelKeyDeletion", "kms:CreateAlias", "kms:DeleteAlias", "kms:DescribeKey", "kms:DisableKey", "kms:DisableKeyRotation", "kms:EnableKey", "kms:EnableKeyRotation", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListGrants", "kms:ListKeyPolicies", "kms:ListResourceTags", "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion", "kms:TagResource", "kms:UntagResource", "kms:UpdateAlias", "kms:UpdateKeyDescription", "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:ReEncryptFrom", "kms:ReEncryptTo"], Resource = "*" }] : [],
      var.allow_root_for_v1 ? [{ Sid = "EnableV1AWSResourceGrants", Effect = "Allow", Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }, Action = ["kms:CreateGrant"], Resource = "*", Condition = { Bool = { "kms:GrantIsForAWSResource" = "true" } } }] : [],
      [
        for role_index, role_arn in var.admin_role_arns : {
          Sid    = "AllowKeyAdministrator${role_index}"
          Effect = "Allow"
          Principal = {
            AWS = role_arn
          }
          Action = [
            "kms:CancelKeyDeletion",
            "kms:CreateGrant",
            "kms:DescribeKey",
            "kms:DisableKey",
            "kms:DisableKeyRotation",
            "kms:EnableKey",
            "kms:EnableKeyRotation",
            "kms:GetKeyPolicy",
            "kms:GetKeyRotationStatus",
            "kms:ListGrants",
            "kms:ListKeyPolicies",
            "kms:ListResourceTags",
            "kms:PutKeyPolicy",
            "kms:RetireGrant",
            "kms:RevokeGrant",
            "kms:ScheduleKeyDeletion",
            "kms:TagResource",
            "kms:UntagResource",
            "kms:UpdateKeyDescription",
          ]
          Resource = "*"
        }
      ],
      [
        for role_index, role_arn in var.user_role_arns : {
          Sid    = "AllowKeyUser${role_index}"
          Effect = "Allow"
          Principal = {
            AWS = role_arn
          }
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
            "kms:Encrypt",
            "kms:GenerateDataKey*",
            "kms:ReEncrypt*",
          ]
          Resource = "*"
        }
      ],
    )
  })

  tags = merge(var.tags, {
    Purpose = var.purpose
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/insurance/${var.environment}/${var.purpose}"
  target_key_id = aws_kms_key.this.key_id
}
