#!/usr/bin/env bash
set -euo pipefail

# Offline-only IaC gate. Never runs init, plan, apply, AWS CLI, or downloads.
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
terraform_root="$repo/terraform"

if ! command -v terraform >/dev/null 2>&1; then
  echo "NOT RUN: terraform not installed; fmt/validate unavailable" >&2
else
  terraform fmt -check -recursive "$terraform_root"
  for env in dev prod; do
    root="$terraform_root/environments/$env"
    if [[ -d "$root/.terraform" ]]; then
      terraform "-chdir=$root" validate -no-color
    else
      echo "NOT RUN: terraform validate skipped for $root (no initialized provider cache; no download)" >&2
    fi
  done
fi

mapfile -t tf_files < <(find "$terraform_root" -type f -name '*.tf' -not -path '*/.terraform/*' -print)
all_tf="$(cat "${tf_files[@]}")"
if grep -Eiq '^[[:space:]]*resource[[:space:]]+"' <<<"$all_tf"; then
  echo 'FAIL: TASK-INF-001 must not define AWS resources' >&2; exit 1
fi
if grep -Eiq '^[[:space:]]*workspace[[:space:]]*=' <<<"$all_tf"; then
  echo 'FAIL: workspaces are not environment boundaries' >&2; exit 1
fi
for env in dev prod; do
  root_tf="$(find "$terraform_root/environments/$env" -type f -name '*.tf' -print0 | xargs -0 cat)"
  grep -Eiq 'provider[[:space:]]+"aws"' <<<"$root_tf" || { echo "FAIL: $env provider missing" >&2; exit 1; }
  grep -Eiq 'region[[:space:]]*=[[:space:]]*var\.aws_region' <<<"$root_tf" || { echo "FAIL: $env provider region contract missing" >&2; exit 1; }
  grep -Eiq 'default[[:space:]]*=[[:space:]]*"ap-southeast-2"' <<<"$root_tf" || { echo "FAIL: $env Sydney validation missing" >&2; exit 1; }
done

secret_re='aws_access_key_id|aws_secret_access_key|password[[:space:]]*=|secret[[:space:]]*=[[:space:]]*"|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY'
mapfile -t scan_files < <(find "$terraform_root" "$repo/buildspecs" "$repo/tests/infrastructure" -type f \( -name '*.tf' -o -name '*.tfvars' -o -name '*.hcl' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.ps1' -o -name '*.sh' \) -not -name 'validate.ps1' -not -name 'validate.sh' -not -path '*/.terraform/*' -print)
if grep -Eiq "$secret_re" "${scan_files[@]}"; then
  echo 'FAIL: possible credential material detected' >&2; exit 1
fi
echo 'Offline infrastructure boundary and secret checks passed. AWS changes performed: None.'
