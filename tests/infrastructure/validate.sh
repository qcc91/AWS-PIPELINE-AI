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

# TASK-INF-002 phase scopes. Later tasks extend this function explicitly with
# approved foundation paths and type allowlists; they do not weaken this check.
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
    *)
      fail "resource outside an approved TASK-INF-002 scope: $file"
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
  [[ "$output_count" == "$description_count" ]] || fail "every bootstrap output must have one description: $output_file"
done < <(find "$bootstrap_root" -type f -name 'outputs.tf' -print0)

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
grep -Fq 'AWS = "arn:aws:iam::${var.account_id}:root"' "$module_main" || fail "same-account root delegation is missing"
grep -Fq 'Sid    = "EnableAccountRootDelegation"' "$module_main" || fail "stable account-root KMS Sid is missing"
grep -Fq 'Sid    = "AllowTerraformRole${role_index}"' "$module_main" || fail "stable role KMS Sid is missing"

hcl_role_pattern='^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$'
grep -Fq "$hcl_role_pattern" "$module_variables" || fail "same-account IAM role validation with path support is missing"
grep -Eiq 'length\(var\.terraform_role_arns\)[[:space:]]*>[[:space:]]*0' "$module_variables" || fail "at least one state-key role ARN must be required"
role_pattern='^arn:aws:iam::123456789012:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$'
[[ 'arn:aws:iam::123456789012:role/platform/dev/TerraformExecution' =~ $role_pattern ]] || fail "role validation regression: a reasonable IAM role path must be accepted"
for invalid_role in 'arn:aws:iam::210987654321:role/platform/dev/TerraformExecution' 'arn:aws:iam::123456789012:role/platform/*' 'arn:aws:iam::123456789012:role/'; do
  [[ ! "$invalid_role" =~ $role_pattern ]] || fail "role validation regression: invalid role was accepted: $invalid_role"
done

secret_pattern='aws_access_key_id|aws_secret_access_key|password[[:space:]]*=|secret[[:space:]]*=[[:space:]]*"|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY'
mapfile -d '' -t scan_files < <(find "$terraform_root" "$repo/buildspecs" "$repo/tests/infrastructure" -type f \( -name '*.tf*' -o -name '*.hcl*' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.ps1' -o -name '*.sh' \) ! -name 'validate.ps1' ! -name 'validate.sh' -not -path '*/.terraform/*' -print0)
if ((${#scan_files[@]} > 0)) && grep -Eiq "$secret_pattern" "${scan_files[@]}"; then
  fail "possible credential material detected"
fi

echo "PASS: offline infrastructure/bootstrap assertions. AWS changes performed: None."
