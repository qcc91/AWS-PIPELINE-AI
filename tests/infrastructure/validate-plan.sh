#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "PLAN VALIDATION FAILED: $1" >&2
  exit 1
}

[[ $# -ge 2 && $# -le 3 ]] || fail "usage: validate-plan.sh <dev|prod> <plan.json> [manifest.json]"
environment="$1"
plan_json="$2"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
manifest="${3:-$script_dir/approved-plan-manifest.json}"

[[ "$environment" == "dev" || "$environment" == "prod" ]] || fail "environment must be dev or prod"
[[ -f "$plan_json" ]] || fail "plan JSON does not exist: $plan_json"
[[ -f "$manifest" ]] || fail "approved manifest does not exist: $manifest"
command -v jq >/dev/null 2>&1 || fail "jq is required to validate Terraform plan JSON"

expected="$(jq -er --arg environment "$environment" '.environments[$environment].expected_active_changes' "$manifest")"
change_count="$(jq -er '(.resource_changes // []) | length' "$plan_json")"

if [[ "$expected" == "0" ]]; then
  [[ "$change_count" == "0" ]] || fail "PROD must have zero resource changes, found $change_count"
  echo "PASS: prod reviewed plan contains zero actions and zero resource changes."
  exit 0
fi

[[ "$change_count" == "$expected" ]] || fail "$environment must contain exactly $expected create changes, found $change_count"

mapfile -t forbidden_types < <(jq -r '.forbidden_resource_types[]' "$manifest")
mapfile -t pattern_rows < <(jq -r --arg environment "$environment" '.environments[$environment].address_patterns[] | [.pattern, (.count | tostring)] | @tsv' "$manifest")
patterns=()
expected_counts=()
actual_counts=()
for row in "${pattern_rows[@]}"; do
  IFS=$'\t' read -r pattern pattern_count <<<"$row"
  patterns+=("$pattern")
  expected_counts+=("$pattern_count")
  actual_counts+=(0)
done

while IFS=$'\t' read -r address resource_type actions public_ip endpoint_type force_destroy; do
  [[ "$actions" == "create" ]] || fail "only create is allowed; $address has actions [$actions]"
  for forbidden_type in "${forbidden_types[@]}"; do
    [[ "$resource_type" != "$forbidden_type" ]] || fail "forbidden resource type in plan: $resource_type"
  done

  matched=0
  matched_index=-1
  for index in "${!patterns[@]}"; do
    if grep -Eq -- "${patterns[$index]}" <<<"$address"; then
      ((matched += 1))
      matched_index="$index"
    fi
  done
  [[ "$matched" == "1" ]] || fail "$address must match exactly one approved address pattern; matched $matched"
  actual_counts[$matched_index]=$((actual_counts[$matched_index] + 1))

  if [[ "$resource_type" == "aws_subnet" && "$public_ip" != "false" ]]; then
    fail "$address must explicitly disable public IP assignment"
  fi
  if [[ "$resource_type" == "aws_vpc_endpoint" && "$endpoint_type" != "Gateway" ]]; then
    fail "$address must be a Gateway endpoint, not interface/public connectivity"
  fi
  if [[ "$resource_type" == "aws_s3_bucket" && "$force_destroy" != "false" ]]; then
    fail "$address must have force_destroy=false"
  fi
done < <(jq -r '(.resource_changes // [])[] | [
  .address,
  .type,
  (.change.actions | join(",")),
  (.change.after.map_public_ip_on_launch | tostring),
  (.change.after.vpc_endpoint_type | tostring),
  (.change.after.force_destroy | tostring)
] | @tsv' "$plan_json")

pattern_sum=0
for index in "${!patterns[@]}"; do
  [[ "${actual_counts[$index]}" == "${expected_counts[$index]}" ]] || fail "address pattern ${patterns[$index]} expected ${expected_counts[$index]}, found ${actual_counts[$index]}"
  pattern_sum=$((pattern_sum + expected_counts[$index]))
done
[[ "$pattern_sum" == "$expected" ]] || fail "manifest pattern counts sum to $pattern_sum, not $expected"

echo "PASS: dev reviewed plan contains exactly 62 approved create actions, with zero update/delete/replace actions."
