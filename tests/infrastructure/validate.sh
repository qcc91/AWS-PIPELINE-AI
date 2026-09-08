#!/usr/bin/env bash
set -euo pipefail

# Offline-only IaC gate. Never runs init, plan, apply, AWS CLI, or downloads.
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_ere() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  grep -Eiq "$pattern" "$file" || fail "$message"
}

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
terraform_root="$repo/terraform"
bootstrap_root="$terraform_root/bootstrap"
roots=(
  "foundation/dev:$terraform_root/environments/dev"
  "foundation/prod:$terraform_root/environments/prod"
  "bootstrap/dev:$bootstrap_root/environments/dev"
  "bootstrap/prod:$bootstrap_root/environments/prod"
)

if command -v terraform >/dev/null 2>&1; then
  terraform fmt -check -recursive "$terraform_root"
  for root_entry in "${roots[@]}"; do
    root_name="${root_entry%%:*}"
    root_path="${root_entry#*:}"
    if [[ -d "$root_path/.terraform" ]]; then
      terraform "-chdir=$root_path" validate -no-color
    else
      echo "NOT RUN: terraform validate skipped for $root_name; no initialized provider cache and this gate does not download dependencies." >&2
    fi
  done
else
  echo "NOT RUN: terraform is unavailable; fmt and validate have no executable evidence." >&2
fi

mapfile -d '' -t tf_files < <(find "$terraform_root" -type f -name '*.tf' -not -path '*/.terraform/*' -print0)
((${#tf_files[@]} > 0)) || fail "no Terraform files found"
all_tf="$(cat "${tf_files[@]}")"

# Approved Phase 1 scopes use path-specific type allowlists. A resource in any
# other path fails even if its type appears in one of these lists.
is_allowed_resource() {
  local file="$1"
  local type="$2"

  case "$file" in
    "$bootstrap_root"/*)
      case "$type" in
        aws_kms_alias|aws_kms_key|aws_s3_bucket|aws_s3_bucket_lifecycle_configuration|aws_s3_bucket_ownership_controls|aws_s3_bucket_policy|aws_s3_bucket_public_access_block|aws_s3_bucket_server_side_encryption_configuration|aws_s3_bucket_versioning)
          return 0
          ;;
        *)
          fail "resource type not allowed in bootstrap: $type"
          ;;
      esac
      ;;
    "$terraform_root/modules/networking"/*)
      case "$type" in
        aws_vpc|aws_subnet|aws_route_table|aws_route_table_association|aws_vpc_endpoint)
          return 0
          ;;
        *)
          fail "resource type not allowed in networking: $type"
          ;;
      esac
      ;;
    "$terraform_root/modules/kms"/*)
      case "$type" in
        aws_kms_key|aws_kms_alias)
          return 0
          ;;
        *)
          fail "resource type not allowed in kms: $type"
          ;;
      esac
      ;;
    "$terraform_root/modules/s3"/*)
      case "$type" in
        aws_s3_bucket|aws_s3_bucket_versioning|aws_s3_bucket_lifecycle_configuration|aws_s3_bucket_ownership_controls|aws_s3_bucket_policy|aws_s3_bucket_public_access_block|aws_s3_bucket_server_side_encryption_configuration)
          return 0
          ;;
        *)
          fail "resource type not allowed in s3: $type"
          ;;
      esac
      ;;
    "$terraform_root/modules/iam"/*)
      case "$type" in
        aws_iam_role|aws_iam_role_policy)
          return 0
          ;;
        *)
          fail "resource type not allowed in iam: $type"
          ;;
      esac
      ;;
    "$terraform_root/modules/glue"/*)
      case "$type" in
        aws_glue_catalog_database)
          return 0
          ;;
        *)
          fail "resource type not allowed in glue: $type"
          ;;
      esac
      ;;
    "$terraform_root/modules/lakeformation"/*)
      case "$type" in
        aws_lakeformation_resource|aws_lakeformation_data_lake_settings|aws_lakeformation_permissions)
          return 0
          ;;
        *)
          fail "resource type not allowed in lakeformation: $type"
          ;;
      esac
      ;;
    "$terraform_root/modules/monitoring"/*)
      case "$type" in
        aws_kms_key|aws_kms_alias|aws_s3_bucket|aws_s3_bucket_versioning|aws_s3_bucket_ownership_controls|aws_s3_bucket_public_access_block|aws_s3_bucket_server_side_encryption_configuration|aws_s3_bucket_lifecycle_configuration|aws_s3_bucket_policy|aws_cloudwatch_log_group|aws_iam_role|aws_iam_role_policy|aws_sns_topic|aws_cloudtrail)
          return 0
          ;;
        *)
          fail "resource type not allowed in monitoring: $type"
          ;;
      esac
      ;;
    *)
      fail "resource outside an approved Phase 1 path: $file"
      ;;
  esac
}

for file in "${tf_files[@]}"; do
  while IFS= read -r declaration; do
    [[ -z "$declaration" ]] && continue
    type="${declaration#*\"}"
    type="${type%%\"*}"
    is_allowed_resource "$file" "$type"
  done < <(grep -Eio '^[[:space:]]*resource[[:space:]]+"[^"]+"' "$file" || true)
done

if grep -Eiq '^[[:space:]]*workspace[[:space:]]*=' <<<"$all_tf"; then
  fail "workspaces are not environment boundaries"
fi

single_line_block='^[[:space:]]*(terraform|required_providers|provider|variable|validation|output|lifecycle|resource|module|rule|versioning_configuration|noncurrent_version_expiration|apply_server_side_encryption_by_default)[^{[:space:]]*([[:space:]]+[^\{]*)?\{[^}]*[^}[:space:]][^}]*\}'
if grep -E "$single_line_block" "${tf_files[@]}" >/dev/null; then
  fail "non-canonical single-line HCL block detected"
fi

while IFS= read -r -d '' output_file; do
  output_count="$(grep -Eic '^[[:space:]]*output[[:space:]]+"' "$output_file" || true)"
  description_count="$(grep -Eic '^[[:space:]]*description[[:space:]]*=' "$output_file" || true)"
  [[ "$output_count" == "$description_count" ]] || fail "every Terraform output must have one description: $output_file"
done < <(find "$terraform_root" -type f -name 'outputs.tf' -not -path '*/.terraform/*' -print0)

for root_entry in "${roots[@]}"; do
  root_name="${root_entry%%:*}"
  root_path="${root_entry#*:}"
  root_tf="$(find "$root_path" -type f -name '*.tf' -not -path '*/.terraform/*' -print0 | xargs -0 cat)"
  grep -Eiq 'provider[[:space:]]+"aws"' <<<"$root_tf" || fail "$root_name provider is missing"
  grep -Eiq 'region[[:space:]]*=[[:space:]]*var\.aws_region' <<<"$root_tf" || fail "$root_name provider region contract is missing"
  grep -Eiq 'default[[:space:]]*=[[:space:]]*"ap-southeast-2"' <<<"$root_tf" || fail "$root_name Sydney default is missing"
  grep -Eiq 'condition[[:space:]]*=[[:space:]]*var\.aws_region[[:space:]]*==[[:space:]]*"ap-southeast-2"' <<<"$root_tf" || fail "$root_name Sydney validation is missing"
done

mapfile -d '' -t bootstrap_files < <(find "$bootstrap_root" -type f \( -name '*.tf' -o -name '*.hcl.example' \) -not -path '*/.terraform/*' -print0)
if grep -Eiq 'dynamodb|access_key|secret_key|aws_secret' "${bootstrap_files[@]}"; then
  fail "bootstrap contains forbidden DynamoDB or credential configuration"
fi

module_main="$bootstrap_root/modules/state-backend/main.tf"
module_variables="$bootstrap_root/modules/state-backend/variables.tf"
module_outputs="$bootstrap_root/modules/state-backend/outputs.tf"
for state_key in 'bootstrap/terraform.tfstate' 'foundation/terraform.tfstate'; do
  grep -Fq "$state_key" "$module_outputs" || fail "state-backend module output is missing key: $state_key"
done

for environment in dev prod; do
  backend="$bootstrap_root/environments/$environment/backend.hcl.example"
  assert_ere "^[[:space:]]*bucket[[:space:]]*=[[:space:]]*\"<org>-insurance-${environment}-tfstate-<account_short>\"[[:space:]]*$" "$backend" "bootstrap/$environment bucket contract is missing"
  assert_ere '^[[:space:]]*key[[:space:]]*=[[:space:]]*"bootstrap/terraform\.tfstate"[[:space:]]*$' "$backend" "bootstrap/$environment bootstrap state key is missing"
  assert_ere '^[[:space:]]*region[[:space:]]*=[[:space:]]*"ap-southeast-2"[[:space:]]*$' "$backend" "bootstrap/$environment Sydney backend region is missing"
  assert_ere '^[[:space:]]*encrypt[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$backend" "bootstrap/$environment backend encryption is missing"
  assert_ere '^[[:space:]]*use_lockfile[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$backend" "bootstrap/$environment native lockfile is missing"
  assert_ere "^[[:space:]]*kms_key_id[[:space:]]*=[[:space:]]*\"arn:aws:kms:ap-southeast-2:<account_id>:key/<${environment}_state_kms_key_id>\"[[:space:]]*$" "$backend" "bootstrap/$environment must use the created key's actual ARN placeholder"
  assert_ere "^[[:space:]]*role_arn[[:space:]]*=[[:space:]]*\"arn:aws:iam::<account_id>:role/<${environment}_terraform_backend_role_path_and_name>\"[[:space:]]*$" "$backend" "bootstrap/$environment same-account backend role placeholder is missing"
  grep -Eq 'module\.state_backend\.backend_state_keys' "$bootstrap_root/environments/$environment/outputs.tf" || fail "bootstrap/$environment root does not expose both approved state keys"
done

dev_backend="$bootstrap_root/environments/dev/backend.hcl.example"
prod_backend="$bootstrap_root/environments/prod/backend.hcl.example"
cmp -s "$dev_backend" "$prod_backend" && fail "DEV and PROD backend files must be different"
for identity in bucket kms_key_id role_arn; do
  dev_value="$(sed -nE "s/^[[:space:]]*${identity}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" "$dev_backend")"
  prod_value="$(sed -nE "s/^[[:space:]]*${identity}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" "$prod_backend")"
  [[ -n "$dev_value" && "$dev_value" != "$prod_value" ]] || fail "DEV/PROD $identity isolation assertion failed"
done

grep -Eiq 'create_resources[[:space:]]*=[[:space:]]*true' "$bootstrap_root/environments/dev/main.tf" || fail "DEV bootstrap must explicitly enable its planned resources"
grep -Eiq 'create_resources[[:space:]]*=[[:space:]]*false' "$bootstrap_root/environments/prod/main.tf" || fail "PROD bootstrap must remain design-only"

[[ "$(grep -Ec 'prevent_destroy[[:space:]]*=[[:space:]]*true' "$module_main")" == "2" ]] || fail "both the state KMS key and S3 bucket must set prevent_destroy=true"
grep -Eiq 'force_destroy[[:space:]]*=[[:space:]]*false' "$module_main" || fail "state bucket force_destroy must be false"
grep -Eiq 'depends_on[[:space:]]*=[[:space:]]*\[aws_s3_bucket_versioning\.state\]' "$module_main" || fail "state lifecycle must depend on versioning"
grep -Eiq 'status[[:space:]]*=[[:space:]]*"Enabled"' "$module_main" || fail "state bucket versioning is missing"
for control in block_public_acls block_public_policy ignore_public_acls restrict_public_buckets; do
  grep -Eiq "$control[[:space:]]*=[[:space:]]*true" "$module_main" || fail "S3 public-access control is missing: $control"
done
grep -Eiq 'object_ownership[[:space:]]*=[[:space:]]*"BucketOwnerEnforced"' "$module_main" || fail "BucketOwnerEnforced is missing"
grep -Eiq 'kms_master_key_id[[:space:]]*=[[:space:]]*aws_kms_key\.state\[0\]\.arn' "$module_main" || fail "default SSE-KMS must use the actual state key ARN"
grep -Eiq 'sse_algorithm[[:space:]]*=[[:space:]]*"aws:kms"' "$module_main" || fail "default SSE-KMS algorithm is missing"

compact_module="$(tr -d '\r\n' < "$module_main")"
grep -Eiq 'Sid[[:space:]]*=[[:space:]]*"DenyInsecureTransport".*"aws:SecureTransport"[[:space:]]*=[[:space:]]*"false"' <<<"$compact_module" || fail "TLS-only bucket deny is missing"
grep -Eiq 'Sid[[:space:]]*=[[:space:]]*"DenyIncorrectExplicitEncryption".*StringNotEquals.*"s3:x-amz-server-side-encryption"[[:space:]]*=[[:space:]]*"aws:kms".*Null.*"s3:x-amz-server-side-encryption"[[:space:]]*=[[:space:]]*"false"' <<<"$compact_module" || fail "explicit wrong encryption-algorithm deny is missing"
grep -Eiq 'Sid[[:space:]]*=[[:space:]]*"DenyIncorrectExplicitKmsKey".*ArnNotEquals.*"s3:x-amz-server-side-encryption-aws-kms-key-id"[[:space:]]*=[[:space:]]*aws_kms_key\.state\[0\]\.arn.*Null.*"s3:x-amz-server-side-encryption-aws-kms-key-id"[[:space:]]*=[[:space:]]*"false"' <<<"$compact_module" || fail "explicit wrong KMS-key deny is missing"
if grep -Eiq 'Null[[:space:]]*=[[:space:]]*\{[[:space:]]*"s3:x-amz-server-side-encryption(-aws-kms-key-id)?"[[:space:]]*=[[:space:]]*"true"' <<<"$compact_module"; then
  fail "missing encryption headers must remain allowed so bucket default SSE-KMS can apply"
fi

grep -Eiq 'enable_key_rotation[[:space:]]*=[[:space:]]*true' "$module_main" || fail "KMS rotation is missing"
grep -Eiq 'deletion_window_in_days[[:space:]]*=[[:space:]]*30' "$module_main" || fail "KMS deletion window is missing"
grep -Fq 'var.allow_root_for_v1 ?' "$module_main" || fail "state KMS root access must be guarded by the explicit V1 flag"
grep -Fq 'arn:aws:iam::${var.account_id}:root' "$module_main" || fail "state KMS exact same-account root principal is missing"
! grep -Eq 'Action[[:space:]]*=[[:space:]]*"kms:\*"' "$module_main" || fail "state KMS policy must not use kms:*"
grep -Fq 'Sid    = "AllowTerraformRole${role_index}"' "$module_main" || fail "stable role KMS Sid is missing"

hcl_role_pattern='^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$'
grep -Fq "$hcl_role_pattern" "$module_variables" || fail "same-account IAM role validation with path support is missing"
grep -Fq 'var.allow_root_for_v1' "$module_variables" || fail "state roles may be omitted only under the V1 root shortcut"
role_pattern='^arn:aws:iam::123456789012:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$'
[[ 'arn:aws:iam::123456789012:role/platform/dev/TerraformExecution' =~ $role_pattern ]] || fail "role validation regression: a reasonable IAM role path must be accepted"
for invalid_role in 'arn:aws:iam::210987654321:role/platform/dev/TerraformExecution' 'arn:aws:iam::123456789012:role/platform/*' 'arn:aws:iam::123456789012:role/'; do
  [[ ! "$invalid_role" =~ $role_pattern ]] || fail "role validation regression: invalid role was accepted: $invalid_role"
done

# TASK-INF-003 networking assertions.
networking_main="$terraform_root/modules/networking/main.tf"
networking_variables="$terraform_root/modules/networking/variables.tf"
networking_outputs="$terraform_root/modules/networking/outputs.tf"
[[ "$(grep -Ec '^[[:space:]]*resource[[:space:]]+"' "$networking_main")" == '5' ]] || fail "networking must contain exactly five approved resource declarations"
for declaration in 'aws_vpc" "this' 'aws_subnet" "private' 'aws_route_table" "private' 'aws_route_table_association" "private' 'aws_vpc_endpoint" "s3'; do
  [[ "$(grep -Fc "resource \"$declaration\"" "$networking_main")" == '1' ]] || fail "networking resource declaration missing or duplicated: $declaration"
done
compact_networking="$(tr -d '\r\n' < "$networking_main")"
grep -Eq 'resource[[:space:]]+"aws_subnet"[[:space:]]+"private"[[:space:]]*\{[^}]*count[[:space:]]*=[[:space:]]*2' <<<"$compact_networking" || fail "networking must create exactly two private subnets"
grep -Eq 'resource[[:space:]]+"aws_route_table_association"[[:space:]]+"private"[[:space:]]*\{[^}]*count[[:space:]]*=[[:space:]]*2' <<<"$compact_networking" || fail "networking must create exactly two route-table associations"
grep -Fq 'cidrsubnet(var.vpc_cidr, var.private_subnet_newbits, var.private_subnet_netnums[count.index])' "$networking_main" || fail "private subnet CIDRs must use the approved cidrsubnet expression"
grep -Eiq 'length\(var\.private_subnet_netnums\)[[:space:]]*==[[:space:]]*2' "$networking_variables" || fail "exactly two subnet netnums must be required"
grep -Eiq 'netnum[[:space:]]*>=[[:space:]]*0' "$networking_variables" || fail "subnet netnums must be non-negative"
grep -Eiq 'netnum[[:space:]]*<[[:space:]]*pow\(2,[[:space:]]*var\.private_subnet_newbits\)' "$networking_variables" || fail "subnet netnums must remain below 2^newbits"
grep -Fq 'var.private_subnet_netnums[0] != var.private_subnet_netnums[1]' "$networking_variables" || fail "subnet netnums must be distinct"
compact_networking_variables="$(tr -d '\r\n' < "$networking_variables")"
grep -Eq 'var\.private_subnet_newbits[[:space:]]*>=[[:space:]]*1.*var\.private_subnet_newbits[[:space:]]*<=[[:space:]]*8' <<<"$compact_networking_variables" || fail "private_subnet_newbits must have the approved bounded range"
grep -Eiq 'length\(var\.availability_zones\)[[:space:]]*==[[:space:]]*2' "$networking_variables" || fail "exactly two availability zones must be required"
grep -Fq 'var.availability_zones[0] != var.availability_zones[1]' "$networking_variables" || fail "availability zones must be distinct"
grep -Fq '^ap-southeast-2[a-z]$' "$networking_variables" || fail "availability zones must be restricted to Sydney"
grep -Fq 'service_name      = "com.amazonaws.ap-southeast-2.s3"' "$networking_main" || fail "the S3 endpoint service must be Sydney"
grep -Fq 'vpc_endpoint_type = "Gateway"' "$networking_main" || fail "the S3 endpoint must be Gateway type"
grep -Fq 'route_table_ids   = [aws_route_table.private.id]' "$networking_main" || fail "the S3 endpoint must use the private route table"
grep -Fq 'map_public_ip_on_launch = false' "$networking_main" || fail "private subnets must disable automatic public IPs"
if grep -Eiq '^[[:space:]]*resource[[:space:]]+"aws_(internet_gateway|nat_gateway|eip|route)"|vpc_endpoint_type[[:space:]]*=[[:space:]]*"Interface"|map_public_ip_on_launch[[:space:]]*=[[:space:]]*true|assign_ipv6_address_on_creation[[:space:]]*=[[:space:]]*true|0\.0\.0\.0/0' "$networking_main"; then
  fail "networking contains a prohibited internet/NAT/interface/public route or address control"
fi
for required_output in vpc_id private_subnet_ids private_subnet_cidrs private_route_table_id s3_gateway_endpoint_id; do
  grep -Eq "^[[:space:]]*output[[:space:]]+\"${required_output}\"" "$networking_outputs" || fail "networking output missing: $required_output"
done

# TASK-INF-003 shared tag-contract assertions.
for module_name in networking kms s3; do
  module_variables="$terraform_root/modules/$module_name/variables.tf"
  tags_block="$(sed -n '/^variable "tags"/,$p' "$module_variables")"
  [[ -n "$tags_block" ]] || fail "$module_name tags block is missing"
  ! grep -Eq '^[[:space:]]*default[[:space:]]*=' <<<"$tags_block" || fail "$module_name tags must have no default"
  for tag_key in Project Environment Owner ManagedBy CostCenter DataClassification; do
    grep -Fq "\"$tag_key\"" <<<"$tags_block" || fail "$module_name tags validation is missing required key: $tag_key"
  done
  grep -Eq 'trimspace\(lookup\(var\.tags,[[:space:]]*key,[[:space:]]*""\)\)[[:space:]]*!=[[:space:]]*""' <<<"$tags_block" || fail "$module_name must reject empty required tag values"
  grep -Eq 'lookup\(var\.tags,[[:space:]]*"ManagedBy",[[:space:]]*""\)[[:space:]]*==[[:space:]]*"terraform"' <<<"$tags_block" || fail "$module_name ManagedBy must be terraform"
  for classification in public internal confidential restricted; do
    grep -Fq "\"$classification\"" <<<"$tags_block" || fail "$module_name DataClassification allowlist is incomplete: $classification"
  done
done

# TASK-INF-003 reusable KMS assertions.
kms_main="$terraform_root/modules/kms/main.tf"
kms_variables="$terraform_root/modules/kms/variables.tf"
[[ "$(grep -Ec '^[[:space:]]*resource[[:space:]]+"' "$kms_main")" == '2' ]] || fail "KMS module must declare exactly one key and one alias"
[[ "$(grep -Fc 'resource "aws_kms_key" "this"' "$kms_main")" == '1' ]] || fail "KMS key declaration missing or duplicated"
[[ "$(grep -Fc 'resource "aws_kms_alias" "this"' "$kms_main")" == '1' ]] || fail "KMS alias declaration missing or duplicated"
grep -Eiq 'enable_key_rotation[[:space:]]*=[[:space:]]*true' "$kms_main" || fail "KMS rotation is missing"
grep -Eiq 'deletion_window_in_days[[:space:]]*=[[:space:]]*30' "$kms_main" || fail "KMS 30-day deletion window is missing"
grep -Eiq 'prevent_destroy[[:space:]]*=[[:space:]]*true' "$kms_main" || fail "KMS key deletion protection is missing"
grep -Fq 'target_key_id = aws_kms_key.this.key_id' "$kms_main" || fail "KMS alias target is missing"
[[ "$(grep -Ec 'Action[[:space:]]*=[[:space:]]*"kms:\*"' "$kms_main")" == '0' ]] || fail "KMS must not contain direct kms:*"
grep -Fq 'var.allow_root_for_v1 ?' "$kms_main" || fail "platform KMS root access must be guarded by the V1 flag"
grep -Fq 'arn:aws:iam::${var.account_id}:root' "$kms_main" || fail "platform KMS exact same-account root principal is missing"
for admin_action in kms:PutKeyPolicy kms:EnableKeyRotation kms:ScheduleKeyDeletion kms:CancelKeyDeletion kms:CreateGrant; do
  grep -Fq "\"$admin_action\"" "$kms_main" || fail "direct KMS administrator action missing: $admin_action"
done
for user_action in kms:Encrypt kms:Decrypt 'kms:GenerateDataKey*' kms:DescribeKey 'kms:ReEncrypt*'; do
  grep -Fq "\"$user_action\"" "$kms_main" || fail "KMS user data-plane action missing: $user_action"
done
[[ "$(grep -Fc "$hcl_role_pattern" "$kms_variables")" == '2' ]] || fail "KMS admin and user roles must both be same-account, path-capable, and wildcard-free"
grep -Eiq 'length\(var\.admin_role_arns\)[[:space:]]*>[[:space:]]*0' "$kms_variables" || fail "at least one KMS administrator is required"
compact_kms_variables="$(tr -d '\r\n' < "$kms_variables")"
grep -Eq 'variable[[:space:]]+"user_role_arns"[[:space:]]*\{.*default[[:space:]]*=[[:space:]]*\[\]' <<<"$compact_kms_variables" || fail "KMS user roles must be allowed to remain empty"
grep -Fq 'Purpose = var.purpose' "$kms_main" || fail "KMS purpose must be applied as a Purpose tag"

# TASK-INF-003 reusable S3 assertions.
s3_main="$terraform_root/modules/s3/main.tf"
s3_variables="$terraform_root/modules/s3/variables.tf"
[[ "$(grep -Ec '^[[:space:]]*resource[[:space:]]+"' "$s3_main")" == '7' ]] || fail "S3 module must declare exactly seven approved resources"
for resource_type in aws_s3_bucket aws_s3_bucket_versioning aws_s3_bucket_ownership_controls aws_s3_bucket_public_access_block aws_s3_bucket_server_side_encryption_configuration aws_s3_bucket_lifecycle_configuration aws_s3_bucket_policy; do
  [[ "$(grep -Ec "^[[:space:]]*resource[[:space:]]+\"${resource_type}\"" "$s3_main")" == '1' ]] || fail "S3 resource declaration missing or duplicated: $resource_type"
done
for bucket_rule in '!strcontains(var.bucket_name, "..")' '!strcontains(var.bucket_name, ".-")' '!strcontains(var.bucket_name, "-.")' 'xn--' 'amzn-s3-demo-' '-s3alias' '--x-s3' '--table-s3'; do
  grep -Fq -- "$bucket_rule" "$s3_variables" || fail "S3 bucket-name validation is missing rule: $bucket_rule"
done
grep -Fq '^[0-9]{1,3}(\\.[0-9]{1,3}){3}$' "$s3_variables" || fail "S3 bucket names must reject IP-address format"
grep -Fq '^arn:aws:kms:ap-southeast-2:[0-9]{12}:key/[0-9a-fA-F]{8}-' "$s3_variables" || fail "S3 KMS input must be an actual Sydney key ARN"
compact_s3_variables="$(tr -d '\r\n' < "$s3_variables")"
grep -Eq 'variable[[:space:]]+"purpose"[[:space:]]*\{.*contains\(' <<<"$compact_s3_variables" || fail "S3 purpose must be non-empty and allowlisted"
grep -Fq 'Purpose = var.purpose' "$s3_main" || fail "S3 purpose must be applied as a Purpose tag"
retention_block="$(sed -n '/^variable "noncurrent_retention_days"/,/^}/p' "$s3_variables")"
[[ -n "$retention_block" ]] || fail "S3 noncurrent retention block is missing"
! grep -Eq '^[[:space:]]*default[[:space:]]*=' <<<"$retention_block" || fail "S3 noncurrent retention must have no default"
grep -Eiq 'force_destroy[[:space:]]*=[[:space:]]*false' "$s3_main" || fail "S3 force_destroy must be false"
grep -Eiq 'prevent_destroy[[:space:]]*=[[:space:]]*true' "$s3_main" || fail "S3 bucket deletion protection is missing"
grep -Eiq 'depends_on[[:space:]]*=[[:space:]]*\[aws_s3_bucket_versioning\.this\]' "$s3_main" || fail "S3 lifecycle must depend on versioning"
grep -Eq 'filter[[:space:]]*\{[[:space:]]*\}' "$s3_main" || fail "S3 lifecycle must include an all-object filter"
grep -Eiq 'status[[:space:]]*=[[:space:]]*"Enabled"' "$s3_main" || fail "S3 versioning is missing"
grep -Eiq 'object_ownership[[:space:]]*=[[:space:]]*"BucketOwnerEnforced"' "$s3_main" || fail "S3 BucketOwnerEnforced is missing"
for control in block_public_acls block_public_policy ignore_public_acls restrict_public_buckets; do
  grep -Eiq "$control[[:space:]]*=[[:space:]]*true" "$s3_main" || fail "S3 public-access control is missing: $control"
done
grep -Eiq 'kms_master_key_id[[:space:]]*=[[:space:]]*var\.kms_key_arn' "$s3_main" || fail "S3 default encryption must use the supplied KMS key ARN"
grep -Eiq 'sse_algorithm[[:space:]]*=[[:space:]]*"aws:kms"' "$s3_main" || fail "S3 default encryption algorithm is missing"
compact_s3="$(tr -d '\r\n' < "$s3_main")"
grep -Eiq 'Sid[[:space:]]*=[[:space:]]*"DenyInsecureTransport".*"aws:SecureTransport"[[:space:]]*=[[:space:]]*"false"' <<<"$compact_s3" || fail "S3 TLS-only deny is missing"
grep -Eiq 'Sid[[:space:]]*=[[:space:]]*"DenyIncorrectExplicitEncryption".*StringNotEquals.*"s3:x-amz-server-side-encryption"[[:space:]]*=[[:space:]]*"aws:kms".*Null.*"s3:x-amz-server-side-encryption"[[:space:]]*=[[:space:]]*"false"' <<<"$compact_s3" || fail "S3 explicit wrong-algorithm deny is missing"
grep -Eiq 'Sid[[:space:]]*=[[:space:]]*"DenyIncorrectExplicitKmsKey".*ArnNotEquals.*"s3:x-amz-server-side-encryption-aws-kms-key-id"[[:space:]]*=[[:space:]]*var\.kms_key_arn.*Null.*"s3:x-amz-server-side-encryption-aws-kms-key-id"[[:space:]]*=[[:space:]]*"false"' <<<"$compact_s3" || fail "S3 explicit wrong-key deny is missing"
if grep -Eiq 'Null[[:space:]]*=[[:space:]]*\{[[:space:]]*"s3:x-amz-server-side-encryption(-aws-kms-key-id)?"[[:space:]]*=[[:space:]]*"true"' <<<"$compact_s3"; then
  fail "S3 missing encryption headers must remain allowed for default SSE-KMS"
fi

# TASK-INF-004 IAM, Glue, Lake Formation, and monitoring assertions.
iam_main="$terraform_root/modules/iam/main.tf"
iam_variables="$terraform_root/modules/iam/variables.tf"
[[ "$(grep -Ec '^[[:space:]]*resource[[:space:]]+"' "$iam_main")" == '4' ]] || fail "IAM must declare exactly two roles and two inline policies"
[[ "$(grep -Ec '^[[:space:]]*resource[[:space:]]+"aws_iam_role"' "$iam_main")" == '2' ]] || fail "IAM role count must be two"
[[ "$(grep -Ec '^[[:space:]]*resource[[:space:]]+"aws_iam_role_policy"' "$iam_main")" == '2' ]] || fail "IAM inline policy count must be two"
if grep -Eiq 'AdministratorAccess|PowerUser|Action[[:space:]]*=[[:space:]]*"\*"|"iam:\*"|"kms:\*"' "$iam_main"; then
  fail "IAM contains a forbidden broad action or managed-policy name"
fi
[[ "$(grep -Ec 'Resource[[:space:]]*=[[:space:]]*"\*"' "$iam_main")" == '1' ]] || fail "IAM Resource=* must occur only for unsupported discovery APIs"
for action in ec2:DescribeAvailabilityZones sts:GetCallerIdentity; do
  grep -Fq "\"$action\"" "$iam_main" || fail "IAM unscoped discovery action missing: $action"
done
! grep -Fq '"s3:ListAllMyBuckets"' "$iam_main" || fail "Terraform review role must not include s3:ListAllMyBuckets"
compact_iam="$(tr -d '\r\n' < "$iam_main")"
grep -Eq 'Sid[[:space:]]*=[[:space:]]*"PassLakeFormationRegistrationRoleOnly".*Action[[:space:]]*=[[:space:]]*"iam:PassRole".*Resource[[:space:]]*=[[:space:]]*aws_iam_role\.lakeformation_registration\.arn.*"iam:PassedToService"[[:space:]]*=[[:space:]]*"lakeformation\.amazonaws\.com"' <<<"$compact_iam" || fail "PassRole must be role- and service-bound"
grep -Eq 'Principal[[:space:]]*=[[:space:]]*\{[[:space:]]*AWS[[:space:]]*=[[:space:]]*var\.trusted_role_arns' <<<"$compact_iam" || fail "Terraform trust must use explicit roles"
grep -Eq 'Principal[[:space:]]*=[[:space:]]*\{[[:space:]]*Service[[:space:]]*=[[:space:]]*"lakeformation\.amazonaws\.com"' <<<"$compact_iam" || fail "registration role trust must use Lake Formation"
grep -Eiq 'length\(var\.trusted_role_arns\)[[:space:]]*>[[:space:]]*0' "$iam_variables" || fail "Terraform trust-role input must be non-empty"
for scope in var.data_location_bucket_arns local.data_location_object_arns var.data_kms_key_arns; do
  grep -Fq "Resource = $scope" "$iam_main" || fail "registration policy scope missing: $scope"
done
for action in kms:Encrypt kms:Decrypt 'kms:GenerateDataKey*' kms:DescribeKey 'kms:ReEncrypt*'; do
  grep -Fq "\"$action\"" "$iam_main" || fail "registration KMS action missing: $action"
done

glue_main="$terraform_root/modules/glue/main.tf"
glue_variables="$terraform_root/modules/glue/variables.tf"
[[ "$(grep -Ec '^[[:space:]]*resource[[:space:]]+"' "$glue_main")" == '1' ]] || fail "Glue must declare exactly one database resource"
[[ "$(grep -Fc 'resource "aws_glue_catalog_database" "layer"' "$glue_main")" == '1' ]] || fail "Glue database declaration missing"
for layer in bronze silver gold control; do
  grep -Fq "$layer" "$glue_main" || fail "Glue layer mapping missing: $layer"
done
grep -Fq 'for_each = local.database_locations' "$glue_main" || fail "Glue must use the exact four-layer map"
grep -Fq 'name         = "insurance_${var.environment}_${each.key}"' "$glue_main" || fail "Glue database naming contract is missing"
grep -Fq '!contains([' "$glue_variables" || fail "Glue locations must be distinct"
if grep -Eiq '^[[:space:]]*resource[[:space:]]+"aws_glue_(catalog_table|job|crawler)"' "$glue_main"; then
  fail "Glue must not create tables, jobs, or crawlers"
fi

lf_main="$terraform_root/modules/lakeformation/main.tf"
lf_variables="$terraform_root/modules/lakeformation/variables.tf"
[[ "$(grep -Ec '^[[:space:]]*resource[[:space:]]+"' "$lf_main")" == '5' ]] || fail "Lake Formation must declare registration, settings, and three permission resources"
compact_lf="$(tr -d '\r\n' < "$lf_main")"
grep -Eq 'resource[[:space:]]+"aws_lakeformation_resource"[[:space:]]+"location".*for_each[[:space:]]*=[[:space:]]*local\.registered_locations.*role_arn[[:space:]]*=[[:space:]]*var\.data_access_role_arn.*use_service_linked_role[[:space:]]*=[[:space:]]*false' <<<"$compact_lf" || fail "Lake Formation location registration must use the explicit role"
grep -Eq 'resource[[:space:]]+"aws_lakeformation_data_lake_settings".*admins[[:space:]]*=[[:space:]]*var\.admin_role_arns' <<<"$compact_lf" || fail "Lake Formation explicit admins are missing"
grep -Eq 'resource[[:space:]]+"aws_lakeformation_permissions"[[:space:]]+"data_engineer_database".*for_each[[:space:]]*=[[:space:]]*local\.data_engineer_databases.*principal[[:space:]]*=[[:space:]]*var\.data_engineer_role_arn' <<<"$compact_lf" || fail "DataEngineer four-database grant missing"
grep -Fq 'permissions = ["ALTER", "CREATE_TABLE", "DESCRIBE"]' "$lf_main" || fail "DataEngineer permissions must exclude DROP"
grep -Eq 'resource[[:space:]]+"aws_lakeformation_permissions"[[:space:]]+"analyst_gold_database".*principal[[:space:]]*=[[:space:]]*var\.analyst_role_arn.*name[[:space:]]*=[[:space:]]*var\.database_names\["gold"\]' <<<"$compact_lf" || fail "Analyst gold-only grant missing"
grep -Eq 'resource[[:space:]]+"aws_lakeformation_permissions"[[:space:]]+"ml_engineer_database".*for_each[[:space:]]*=[[:space:]]*local\.ml_engineer_databases.*principal[[:space:]]*=[[:space:]]*var\.ml_engineer_role_arn' <<<"$compact_lf" || fail "MLEngineer silver/gold grants missing"
if grep -Fq 'var.rag_application_role_arn' "$lf_main" || grep -Eq 'SELECT|DROP|table[[:space:]]*\{|table_with_columns' "$lf_main"; then
  fail "RAGApplication and table/data permissions must not appear in grants"
fi
grep -Fq 'length(distinct(concat(' "$lf_variables" || fail "Lake Formation roles must be mutually distinct"
[[ "$(grep -Fc '^arn:aws:iam::${var.account_id}:role/' "$lf_variables")" -ge '6' ]] || fail "every Lake Formation role must be same-account and path-capable"

monitoring_main="$terraform_root/modules/monitoring/main.tf"
monitoring_variables="$terraform_root/modules/monitoring/variables.tf"
[[ "$(grep -Ec '^[[:space:]]*resource[[:space:]]+"' "$monitoring_main")" == '14' ]] || fail "monitoring must declare exactly 14 audit-chain resources"
for type in aws_kms_key aws_kms_alias aws_s3_bucket aws_s3_bucket_versioning aws_s3_bucket_ownership_controls aws_s3_bucket_public_access_block aws_s3_bucket_server_side_encryption_configuration aws_s3_bucket_lifecycle_configuration aws_s3_bucket_policy aws_cloudwatch_log_group aws_iam_role aws_iam_role_policy aws_sns_topic aws_cloudtrail; do
  [[ "$(grep -Ec "^[[:space:]]*resource[[:space:]]+\"${type}\"" "$monitoring_main")" == '1' ]] || fail "monitoring resource missing or duplicated: $type"
done
[[ "$(grep -Ec 'Action[[:space:]]*=[[:space:]]*"kms:\*"' "$monitoring_main")" == '0' ]] || fail "monitoring KMS must not contain direct kms:*"
grep -Fq 'var.allow_root_for_v1 ?' "$monitoring_main" || fail "monitoring KMS root access must be guarded by the V1 flag"
grep -Fq 'arn:aws:iam::${var.account_id}:root' "$monitoring_main" || fail "monitoring KMS exact same-account root principal is missing"
compact_monitoring="$(tr -d '\r\n' < "$monitoring_main")"
for sid in AllowCloudTrailGenerateDataKey AllowCloudTrailDescribeKey AllowCloudWatchLogsEncryption AllowSnsEncryption; do
  grep -Eq "Sid[[:space:]]*=[[:space:]]*\"${sid}\".*Condition[[:space:]]*=[[:space:]]*\{" <<<"$compact_monitoring" || fail "conditioned KMS grant missing: $sid"
done
generate_statement="$(sed -n '/Sid    = "AllowCloudTrailGenerateDataKey"/,/Sid    = "AllowCloudTrailDescribeKey"/p' "$monitoring_main")"
describe_statement="$(sed -n '/Sid    = "AllowCloudTrailDescribeKey"/,/Sid    = "AllowCloudWatchLogsEncryption"/p' "$monitoring_main")"
for binding in 'Action   = "kms:GenerateDataKey*"' '"aws:SourceAccount"' '"aws:SourceArn"' '"kms:EncryptionContext:aws:cloudtrail:arn"'; do
  grep -Fq "$binding" <<<"$generate_statement" || fail "CloudTrail GenerateDataKey statement missing binding: $binding"
done
for binding in 'Action   = "kms:DescribeKey"' '"aws:SourceAccount"' '"aws:SourceArn"'; do
  grep -Fq "$binding" <<<"$describe_statement" || fail "CloudTrail DescribeKey statement missing binding: $binding"
done
! grep -Fq 'kms:EncryptionContext:aws:cloudtrail:arn' <<<"$describe_statement" || fail "CloudTrail DescribeKey must not require encryption context"
for key in aws:SourceArn aws:SourceAccount kms:EncryptionContext:aws:cloudtrail:arn kms:EncryptionContext:aws:logs:arn; do
  grep -Fq "\"$key\"" "$monitoring_main" || fail "monitoring condition key missing: $key"
done
grep -Eiq 'enable_key_rotation[[:space:]]*=[[:space:]]*true' "$monitoring_main" || fail "monitoring KMS rotation missing"
grep -Eiq 'deletion_window_in_days[[:space:]]*=[[:space:]]*30' "$monitoring_main" || fail "monitoring KMS deletion window missing"
[[ "$(grep -Ec 'prevent_destroy[[:space:]]*=[[:space:]]*true' "$monitoring_main")" == '2' ]] || fail "audit key and bucket must have prevent_destroy"
grep -Eiq 'force_destroy[[:space:]]*=[[:space:]]*false' "$monitoring_main" || fail "audit bucket force_destroy must be false"
grep -Fq 'depends_on = [aws_s3_bucket_versioning.audit]' "$monitoring_main" || fail "audit lifecycle must depend on versioning"
grep -Eq 'filter[[:space:]]*\{[[:space:]]*\}' "$monitoring_main" || fail "audit lifecycle filter missing"
grep -Fq 'noncurrent_days = var.audit_noncurrent_retention_days' "$monitoring_main" || fail "audit retention input not wired"
grep -Eq 'expiration[[:space:]]*\{[^}]*days[[:space:]]*=[[:space:]]*var\.audit_retention_days' <<<"$compact_monitoring" || fail "audit current retention expiration not wired"
audit_retention_block="$(sed -n '/^variable "audit_retention_days"/,/^}/p' "$monitoring_variables")"
[[ -n "$audit_retention_block" ]] || fail "audit_retention_days input missing"
! grep -Eq '^[[:space:]]*default[[:space:]]*=' <<<"$audit_retention_block" || fail "audit_retention_days must have no default"
grep -Fq 'var.audit_retention_days >= var.audit_noncurrent_retention_days' <<<"$audit_retention_block" || fail "current audit retention must be at least noncurrent retention"
grep -Fq 'kms_master_key_id = aws_kms_key.audit.arn' "$monitoring_main" || fail "audit bucket must use dedicated KMS key"
grep -Fq 'object_ownership = "BucketOwnerEnforced"' "$monitoring_main" || fail "audit ownership control missing"
for control in block_public_acls block_public_policy ignore_public_acls restrict_public_buckets; do
  grep -Eiq "$control[[:space:]]*=[[:space:]]*true" "$monitoring_main" || fail "audit public block missing: $control"
done
for sid in DenyInsecureTransport AllowCloudTrailBucketAclCheck AllowCloudTrailWrite; do
  grep -Fq "Sid" "$monitoring_main" && grep -Fq "\"$sid\"" "$monitoring_main" || fail "audit bucket policy Sid missing: $sid"
done
grep -Fq '"s3:x-amz-acl"      = "bucket-owner-full-control"' "$monitoring_main" || fail "CloudTrail ACL condition missing"
grep -Eq 'resource[[:space:]]+"aws_cloudwatch_log_group".*retention_in_days[[:space:]]*=[[:space:]]*var\.log_retention_days.*kms_key_id[[:space:]]*=[[:space:]]*aws_kms_key\.audit\.arn' <<<"$compact_monitoring" || fail "CloudWatch retention/encryption incomplete"
grep -Fq 'Resource = "${aws_cloudwatch_log_group.audit.arn}:log-stream:*"' "$monitoring_main" || fail "delivery policy must target only log streams"
grep -Eq 'resource[[:space:]]+"aws_cloudtrail"[[:space:]]+"management".*is_multi_region_trail[[:space:]]*=[[:space:]]*false.*include_global_service_events[[:space:]]*=[[:space:]]*true.*enable_logging[[:space:]]*=[[:space:]]*true' <<<"$compact_monitoring" || fail "CloudTrail regional management configuration incomplete"
grep -Eq 'event_selector[[:space:]]*\{.*read_write_type[[:space:]]*=[[:space:]]*"All".*include_management_events[[:space:]]*=[[:space:]]*true.*exclude_management_event_sources[[:space:]]*=[[:space:]]*\[\]' <<<"$compact_monitoring" || fail "CloudTrail management-only selector incomplete"
if grep -Eq 'data_resource[[:space:]]*\{|^[[:space:]]*resource[[:space:]]+"aws_(sns_topic_subscription|cloudwatch_metric_alarm)"' "$monitoring_main"; then
  fail "monitoring must contain no data resources, subscriptions, or alarms"
fi

for module_name in iam glue lakeformation monitoring; do
  variables_file="$terraform_root/modules/$module_name/variables.tf"
  tags_block="$(sed -n '/^variable "tags"/,$p' "$variables_file")"
  [[ -n "$tags_block" ]] || fail "$module_name tags block missing"
  ! grep -Eq '^[[:space:]]*default[[:space:]]*=' <<<"$tags_block" || fail "$module_name tags must have no default"
  for tag_key in Project Environment Owner ManagedBy CostCenter DataClassification; do
    grep -Fq "\"$tag_key\"" <<<"$tags_block" || fail "$module_name tag contract missing: $tag_key"
  done
done

# TASK-INF-005 environment integration and reviewed-plan contract assertions.
dev_root="$terraform_root/environments/dev"
prod_root="$terraform_root/environments/prod"
dev_main="$dev_root/main.tf"
prod_main="$prod_root/main.tf"
dev_variables="$dev_root/variables.tf"
prod_variables="$prod_root/variables.tf"
dev_outputs="$dev_root/outputs.tf"
prod_outputs="$prod_root/outputs.tf"
dev_backend="$dev_root/backend.hcl.example"
prod_backend="$prod_root/backend.hcl.example"
dev_versions="$dev_root/versions.tf"
prod_versions="$prod_root/versions.tf"

! grep -Eq 'backend[[:space:]]+"s3"' "$dev_versions" || fail "DEV V1 must use local state until bootstrap exists; migration is deferred to V4"
grep -Eq 'backend[[:space:]]+"s3"[[:space:]]*\{[[:space:]]*\}' "$prod_versions" || fail "PROD partial S3 backend declaration is missing"

for root_entry in "DEV:$dev_main" "PROD:$prod_main"; do
  root_name="${root_entry%%:*}"
  root_main="${root_entry#*:}"
  if [[ "$root_name" == 'DEV' ]]; then
    required_modules='common networking platform_kms storage glue monitoring'
  else
    required_modules='common networking platform_kms storage iam glue lakeformation monitoring'
  fi
  for module_name in $required_modules; do
    [[ "$(grep -Ec "^module[[:space:]]+\"${module_name}\"[[:space:]]*\{" "$root_main")" == '1' ]] || fail "$root_name must wire module $module_name exactly once"
  done
  ! grep -Eiq '^[[:space:]]*resource[[:space:]]+"|source[[:space:]]*=[[:space:]]*"[^\"]*(bedrock|rag|nat|internet-gateway)' "$root_main" || fail "$root_name root must use only approved foundation modules and no direct resources"
done
! grep -Eq '^module[[:space:]]+"(iam|lakeformation)"[[:space:]]*\{' "$dev_main" || fail "DEV V1 must defer IAM persona and Lake Formation governance to V3"

purpose_block="$(sed -n '/for purpose in \[/,/^[[:space:]]*\][[:space:]]*:/p' "$dev_main")"
for purpose in landing lakehouse control quarantine documents; do
  [[ "$(grep -Fc "\"$purpose\"" <<<"$purpose_block")" == '1' ]] || fail "DEV storage purpose missing or duplicated: $purpose"
done
[[ "$(grep -Ec '^[[:space:]]*"(landing|lakehouse|control|quarantine|documents)",[[:space:]]*$' <<<"$purpose_block")" == '5' ]] || fail "DEV must define exactly five approved generic bucket purposes"
compact_dev="$(tr -d '\r\n' < "$dev_main")"
grep -Eq 'module[[:space:]]+"storage"[[:space:]]*\{.*for_each[[:space:]]*=[[:space:]]*local\.bucket_names' <<<"$compact_dev" || fail "DEV must instantiate five generic S3 modules"
grep -Fq 'kms_key_arn               = module.platform_kms.key_arn' "$dev_main" || fail "DEV S3 must use the platform KMS key"
grep -Eq 'module[[:space:]]+"platform_kms"[[:space:]]*\{.*user_role_arns[[:space:]]*=[[:space:]]*\[\]' <<<"$compact_dev" || fail "DEV platform KMS must not directly grant data-plane roles in Phase 1"
grep -Fq 'lakehouse_location_uri = "s3://${module.storage["lakehouse"].bucket_id}/lakehouse"' "$dev_main" || fail "DEV Glue lakehouse location wiring missing"
grep -Fq 'control_location_uri   = "s3://${module.storage["control"].bucket_id}/control"' "$dev_main" || fail "DEV Glue control location wiring missing"

dev_enable_block="$(sed -n '/^variable "enable_deployment"/,/^}/p' "$dev_variables")"
grep -Eiq 'default[[:space:]]*=[[:space:]]*true' <<<"$dev_enable_block" || fail "DEV enable_deployment must default true"
grep -Eiq 'condition[[:space:]]*=[[:space:]]*var\.enable_deployment' <<<"$dev_enable_block" || fail "DEV topology switch must be locked enabled"

compact_prod="$(tr -d '\r\n' < "$prod_main")"
for module_name in networking platform_kms iam glue lakeformation monitoring; do
  grep -Eq "module[[:space:]]+\"${module_name}\"[[:space:]]*\{.*count[[:space:]]*=[[:space:]]*var\.enable_deployment[[:space:]]*\?[[:space:]]*1[[:space:]]*:[[:space:]]*0" <<<"$compact_prod" || fail "PROD resource module $module_name must be count-gated"
done
grep -Eq 'module[[:space:]]+"storage"[[:space:]]*\{.*for_each[[:space:]]*=[[:space:]]*var\.enable_deployment[[:space:]]*\?[[:space:]]*local\.bucket_names[[:space:]]*:[[:space:]]*\{\}' <<<"$compact_prod" || fail "PROD storage modules must be gated to an empty map"
grep -Eq 'module[[:space:]]+"platform_kms"[[:space:]]*\{.*user_role_arns[[:space:]]*=[[:space:]]*\[\]' <<<"$compact_prod" || fail "PROD platform KMS design must not directly grant data-plane roles"
prod_enable_block="$(sed -n '/^variable "enable_deployment"/,/^}/p' "$prod_variables")"
grep -Eiq 'default[[:space:]]*=[[:space:]]*false' <<<"$prod_enable_block" || fail "PROD enable_deployment must default false"
grep -Eiq 'condition[[:space:]]*=[[:space:]]*!var\.enable_deployment' <<<"$prod_enable_block" || fail "PROD deployment must be validation-locked off"
[[ "$(grep -Ec 'try\(module\.(networking|platform_kms|iam|glue|lakeformation|monitoring)\[0\]' "$prod_outputs")" -ge '6' ]] || fail "PROD resource module outputs must be count-safe"
compact_dev_outputs="$(tr -d '\r\n' < "$dev_outputs")"
compact_prod_outputs="$(tr -d '\r\n' < "$prod_outputs")"
grep -Eq 'output[[:space:]]+"expected_resource_instance_count".*value[[:space:]]*=[[:space:]]*62' <<<"$compact_dev_outputs" || fail "DEV expected V1 instance output must be 62"
grep -Eq 'output[[:space:]]+"expected_resource_instance_count".*value[[:space:]]*=[[:space:]]*0' <<<"$compact_prod_outputs" || fail "PROD expected instance output must be zero"

for required_input in account_id account_short org_short vpc_cidr availability_zones data_noncurrent_retention_days audit_noncurrent_retention_days audit_retention_days log_retention_days monthly_budget_usd; do
  input_block="$(sed -n "/^variable \"${required_input}\"/,/^}/p" "$dev_variables")"
  [[ -n "$input_block" ]] || fail "DEV explicit plan input missing: $required_input"
  ! grep -Eq '^[[:space:]]*default[[:space:]]*=' <<<"$input_block" || fail "DEV plan input $required_input must have no default"
done

for backend_entry in "DEV:$dev_backend:dev" "PROD:$prod_backend:prod"; do
  backend_name="${backend_entry%%:*}"
  remainder="${backend_entry#*:}"
  backend_file="${remainder%%:*}"
  environment_name="${remainder##*:}"
  for setting in 'key[[:space:]]*=[[:space:]]*"foundation/terraform.tfstate"' 'region[[:space:]]*=[[:space:]]*"ap-southeast-2"' 'encrypt[[:space:]]*=[[:space:]]*true' 'use_lockfile[[:space:]]*=[[:space:]]*true' 'kms_key_id[[:space:]]*=[[:space:]]*"arn:aws:kms:ap-southeast-2:<account_id>:key/<'; do
    grep -Eq "$setting" "$backend_file" || fail "$backend_name foundation backend setting missing: $setting"
  done
  grep -Fq "bucket       = \"<org>-insurance-${environment_name}-tfstate-<account_short>\"" "$backend_file" || fail "$backend_name backend bucket is not environment-isolated"
  grep -Fq "role_arn = \"arn:aws:iam::<account_id>:role/<${environment_name}_terraform_backend_role_path_and_name>\"" "$backend_file" || fail "$backend_name backend role is not environment-isolated"
done
! cmp -s "$dev_backend" "$prod_backend" || fail "DEV and PROD foundation backend examples must differ"

manifest="$repo/tests/infrastructure/approved-plan-manifest.json"
grep -Fq '"expected_active_changes": 62' "$manifest" || fail "DEV V1 manifest must require 62 active changes"
grep -Fq '"expected_active_changes": 0' "$manifest" || fail "PROD manifest must require zero active changes"
manifest_pattern_sum="$(grep -Eo '"count":[[:space:]]*[0-9]+' "$manifest" | awk -F: '{gsub(/[[:space:]]/, "", $2); sum += $2} END {print sum + 0}')"
[[ "$manifest_pattern_sum" == '62' ]] || fail "approved V1 address-pattern counts must sum to 62"
for forbidden_type in aws_internet_gateway aws_nat_gateway aws_sns_topic_subscription aws_cloudwatch_metric_alarm aws_bedrockagent_agent aws_bedrockagent_knowledge_base; do
  grep -Fq "\"$forbidden_type\"" "$manifest" || fail "approved manifest must reject $forbidden_type"
done
plan_validator="$repo/tests/infrastructure/validate-plan.sh"
for plan_rule in 'only create is allowed' 'PROD must have zero resource changes' 'map_public_ip_on_launch' 'vpc_endpoint_type' 'force_destroy=false' 'must match exactly one approved address pattern'; do
  grep -Fq "$plan_rule" "$plan_validator" || fail "Bash plan validator missing rule: $plan_rule"
done

secret_pattern='aws_access_key_id|aws_secret_access_key|password[[:space:]]*=|secret[[:space:]]*=[[:space:]]*"|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY'
mapfile -d '' -t scan_files < <(find "$terraform_root" "$repo/buildspecs" "$repo/tests/infrastructure" -type f \( -name '*.tf*' -o -name '*.hcl*' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.ps1' -o -name '*.sh' \) ! -name 'validate.ps1' ! -name 'validate.sh' -not -path '*/.terraform/*' -print0)
if ((${#scan_files[@]} > 0)) && grep -Eiq "$secret_pattern" "${scan_files[@]}"; then
  fail "possible credential material detected"
fi

echo "PASS: offline TASK-INF-001/002/003/004/005 infrastructure assertions. AWS changes performed: None."
