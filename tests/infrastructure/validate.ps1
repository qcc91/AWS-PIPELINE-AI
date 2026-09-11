$ErrorActionPreference = "Stop"

# Offline-only IaC gate. Never runs init, plan, apply, AWS CLI, or downloads.
function Fail([string]$Message) {
  throw $Message
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -notmatch $Pattern) {
    Fail $Message
  }
}

function Get-TerraformText([string]$Path) {
  return (Get-ChildItem -LiteralPath $Path -Recurse -Filter "*.tf" -File |
      Where-Object { $_.FullName -notmatch '\\.terraform([\\/]|$)' } |
      ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$terraformRoot = Join-Path $repo "terraform"
$bootstrapRoot = (Resolve-Path (Join-Path $terraformRoot "bootstrap")).Path
$terraformFiles = @(Get-ChildItem -LiteralPath $terraformRoot -Recurse -Filter "*.tf" -File |
    Where-Object { $_.FullName -notmatch '\\.terraform([\\/]|$)' })
$allTf = ($terraformFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

$roots = @(
  [pscustomobject]@{ Name = "foundation/dev"; Path = Join-Path $terraformRoot "environments/dev" }
  [pscustomobject]@{ Name = "foundation/prod"; Path = Join-Path $terraformRoot "environments/prod" }
  [pscustomobject]@{ Name = "bootstrap/dev"; Path = Join-Path $bootstrapRoot "environments/dev" }
  [pscustomobject]@{ Name = "bootstrap/prod"; Path = Join-Path $bootstrapRoot "environments/prod" }
)

$terraform = Get-Command terraform -ErrorAction SilentlyContinue
if ($null -eq $terraform) {
  Write-Warning "NOT RUN: terraform is unavailable; fmt and validate have no executable evidence."
} else {
  & $terraform.Source fmt -check -recursive $terraformRoot
  if ($LASTEXITCODE -ne 0) {
    Fail "terraform fmt -check failed"
  }

  foreach ($root in $roots) {
    if (Test-Path -LiteralPath (Join-Path $root.Path ".terraform")) {
      & $terraform.Source "-chdir=$($root.Path)" validate -no-color
      if ($LASTEXITCODE -ne 0) {
        Fail "terraform validate failed: $($root.Name)"
      }
    } else {
      Write-Warning "NOT RUN: terraform validate skipped for $($root.Name); no initialized provider cache and this gate does not download dependencies."
    }
  }
}

# Approved Phase 1 scopes use path-specific type allowlists. A resource in any
# other path fails even if its type appears in one of these lists.
$resourceScopes = @(
  [pscustomobject]@{
    Name = "bootstrap"
    Prefix = $bootstrapRoot + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @(
      "aws_kms_alias"
      "aws_kms_key"
      "aws_s3_bucket"
      "aws_s3_bucket_lifecycle_configuration"
      "aws_s3_bucket_ownership_controls"
      "aws_s3_bucket_policy"
      "aws_s3_bucket_public_access_block"
      "aws_s3_bucket_server_side_encryption_configuration"
      "aws_s3_bucket_versioning"
    )
  }
  [pscustomobject]@{
    Name = "networking"
    Prefix = (Join-Path $terraformRoot "modules/networking") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @(
      "aws_route_table"
      "aws_route_table_association"
      "aws_subnet"
      "aws_vpc"
      "aws_vpc_endpoint"
    )
  }
  [pscustomobject]@{
    Name = "kms"
    Prefix = (Join-Path $terraformRoot "modules/kms") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @(
      "aws_kms_alias"
      "aws_kms_key"
    )
  }
  [pscustomobject]@{
    Name = "s3"
    Prefix = (Join-Path $terraformRoot "modules/s3") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @(
      "aws_s3_bucket"
      "aws_s3_bucket_lifecycle_configuration"
      "aws_s3_bucket_ownership_controls"
      "aws_s3_bucket_policy"
      "aws_s3_bucket_public_access_block"
      "aws_s3_bucket_server_side_encryption_configuration"
      "aws_s3_bucket_versioning"
    )
  }
  [pscustomobject]@{
    Name         = "glue"
    Prefix       = (Join-Path $terraformRoot "modules/glue") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @("aws_glue_catalog_database")
  }
  [pscustomobject]@{
    Name   = "lakeformation"
    Prefix = (Join-Path $terraformRoot "modules/lakeformation") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @(
      "aws_lakeformation_data_lake_settings"
      "aws_lakeformation_permissions"
      "aws_lakeformation_resource"
    )
  }
  [pscustomobject]@{
    Name   = "monitoring"
    Prefix = (Join-Path $terraformRoot "modules/monitoring") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @(
      "aws_cloudtrail"
      "aws_cloudwatch_log_group"
      "aws_iam_role"
      "aws_iam_role_policy"
      "aws_kms_alias"
      "aws_kms_key"
      "aws_s3_bucket"
      "aws_s3_bucket_lifecycle_configuration"
      "aws_s3_bucket_ownership_controls"
      "aws_s3_bucket_policy"
      "aws_s3_bucket_public_access_block"
      "aws_s3_bucket_server_side_encryption_configuration"
      "aws_s3_bucket_versioning"
      "aws_sns_topic"
    )
  }
  [pscustomobject]@{
    Name = "iam"
    Prefix = (Join-Path $terraformRoot "modules/iam") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @(
      "aws_iam_role"
      "aws_iam_role_policy"
    )
  }
  [pscustomobject]@{
    Name = "batch-ingestion"
    Prefix = (Join-Path $terraformRoot "modules/batch-ingestion") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @(
      "aws_cloudwatch_event_rule"
      "aws_cloudwatch_event_target"
      "aws_cloudwatch_log_group"
      "aws_glue_job"
      "aws_iam_role"
      "aws_iam_role_policy"
      "aws_s3_bucket_notification"
      "aws_s3_object"
      "aws_sfn_state_machine"
    )
  }
  [pscustomobject]@{
    Name = "cdc"
    Prefix = (Join-Path $terraformRoot "modules/cdc") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @(
      "aws_cloudwatch_event_rule", "aws_cloudwatch_event_target", "aws_cloudwatch_log_group"
      "aws_db_instance", "aws_db_parameter_group", "aws_db_subnet_group"
      "aws_dms_endpoint", "aws_dms_replication_instance", "aws_dms_replication_subnet_group", "aws_dms_replication_task", "aws_dms_s3_endpoint"
      "aws_glue_connection", "aws_glue_job", "aws_iam_role", "aws_iam_role_policy"
      "aws_s3_object", "aws_secretsmanager_secret", "aws_secretsmanager_secret_version"
      "aws_security_group", "aws_sfn_state_machine", "aws_vpc_endpoint", "random_password"
    )
  }
  [pscustomobject]@{
    Name = "bi"
    Prefix = (Join-Path $terraformRoot "modules/bi") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @("aws_athena_named_query", "aws_athena_workgroup", "aws_quicksight_data_set", "aws_quicksight_data_source")
  }
  [pscustomobject]@{
    Name = "ml"
    Prefix = (Join-Path $terraformRoot "modules/ml") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @("aws_cloudwatch_log_group", "aws_glue_job", "aws_iam_role", "aws_iam_role_policy", "aws_s3_object", "aws_sagemaker_model_package_group")
  }
  [pscustomobject]@{
    Name = "rag"
    Prefix = (Join-Path $terraformRoot "modules/rag") + [System.IO.Path]::DirectorySeparatorChar
    AllowedTypes = @("aws_bedrockagent_data_source", "aws_bedrockagent_knowledge_base", "aws_iam_role", "aws_iam_role_policy", "aws_s3_object", "aws_s3vectors_index", "aws_s3vectors_vector_bucket")
  }
)

foreach ($file in $terraformFiles) {
  $content = Get-Content -LiteralPath $file.FullName -Raw
  $declarations = [regex]::Matches($content, '(?im)^\s*resource\s+"([^"]+)"')
  foreach ($declaration in $declarations) {
    $scope = $resourceScopes | Where-Object {
      $file.FullName.StartsWith($_.Prefix, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if ($null -eq $scope) {
      Fail "resource outside an approved Phase 1 path: $($file.FullName)"
    }

    $type = $declaration.Groups[1].Value
    if ($type -notin $scope.AllowedTypes) {
      Fail "resource type not allowed in $($scope.Name): $type"
    }
  }
}

if ($allTf -match '(?im)^\s*workspace\s*=') {
  Fail "workspaces are not environment boundaries"
}

$singleLineBlock = '(?-i)(?m)^\s*(terraform|required_providers|provider|variable|validation|output|lifecycle|resource|module|rule|versioning_configuration|noncurrent_version_expiration|apply_server_side_encryption_by_default)\b[^\{\r\n]*\{[^\}\r\n]*\S[^\}\r\n]*\}'
if ($allTf -match $singleLineBlock) {
  Fail "non-canonical single-line HCL block detected: $($Matches[0])"
}

foreach ($outputFile in $terraformFiles | Where-Object { $_.Name -eq "outputs.tf" }) {
  $outputText = Get-Content -LiteralPath $outputFile.FullName -Raw
  $outputCount = ([regex]::Matches($outputText, '(?im)^\s*output\s+"')).Count
  $descriptionCount = ([regex]::Matches($outputText, '(?im)^\s*description\s*=')).Count
  if ($outputCount -ne $descriptionCount) {
    Fail "every Terraform output must have one description: $($outputFile.FullName)"
  }
}

foreach ($root in $roots) {
  $rootTf = Get-TerraformText $root.Path
  Assert-Match $rootTf 'provider\s+"aws"' "$($root.Name) provider is missing"
  Assert-Match $rootTf 'region\s*=\s*var\.aws_region' "$($root.Name) provider region contract is missing"
  Assert-Match $rootTf 'default\s*=\s*"ap-southeast-2"' "$($root.Name) Sydney default is missing"
  Assert-Match $rootTf 'condition\s*=\s*var\.aws_region\s*==\s*"ap-southeast-2"' "$($root.Name) Sydney validation is missing"
}

$bootstrapText = (Get-ChildItem -LiteralPath $bootstrapRoot -Recurse -File |
    Where-Object { $_.Name -like "*.tf" -or $_.Name -like "*.hcl.example" } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
if ($bootstrapText -match '(?i)dynamodb|access_key|secret_key|aws_secret') {
  Fail "bootstrap contains forbidden DynamoDB or credential configuration"
}

$moduleMainPath = Join-Path $bootstrapRoot "modules/state-backend/main.tf"
$moduleVariablesPath = Join-Path $bootstrapRoot "modules/state-backend/variables.tf"
$moduleOutputsPath = Join-Path $bootstrapRoot "modules/state-backend/outputs.tf"
$moduleMain = Get-Content -LiteralPath $moduleMainPath -Raw
$moduleVariables = Get-Content -LiteralPath $moduleVariablesPath -Raw
$moduleOutputs = Get-Content -LiteralPath $moduleOutputsPath -Raw

foreach ($stateKey in @("bootstrap/terraform.tfstate", "foundation/terraform.tfstate")) {
  if (-not $moduleOutputs.Contains($stateKey)) {
    Fail "state-backend module output is missing key: $stateKey"
  }
}

$backendTexts = @{}
foreach ($environment in @("dev", "prod")) {
  $backendPath = Join-Path $bootstrapRoot "environments/$environment/backend.hcl.example"
  $backend = Get-Content -LiteralPath $backendPath -Raw
  $backendTexts[$environment] = $backend

  Assert-Match $backend ('(?im)^\s*bucket\s*=\s*"<org>-insurance-' + $environment + '-tfstate-<account_short>"\s*$') "bootstrap/$environment bucket contract is missing"
  Assert-Match $backend '(?im)^\s*key\s*=\s*"bootstrap/terraform\.tfstate"\s*$' "bootstrap/$environment bootstrap state key is missing"
  Assert-Match $backend '(?im)^\s*region\s*=\s*"ap-southeast-2"\s*$' "bootstrap/$environment Sydney backend region is missing"
  Assert-Match $backend '(?im)^\s*encrypt\s*=\s*true\s*$' "bootstrap/$environment backend encryption is missing"
  Assert-Match $backend '(?im)^\s*use_lockfile\s*=\s*true\s*$' "bootstrap/$environment native lockfile is missing"
  Assert-Match $backend ('(?im)^\s*kms_key_id\s*=\s*"arn:aws:kms:ap-southeast-2:<account_id>:key/<' + $environment + '_state_kms_key_id>"\s*$') "bootstrap/$environment must use the created key's actual ARN placeholder"
  Assert-Match $backend ('(?im)^\s*role_arn\s*=\s*"arn:aws:iam::<account_id>:role/<' + $environment + '_terraform_backend_role_path_and_name>"\s*$') "bootstrap/$environment same-account backend role placeholder is missing"

  $rootOutputs = Get-Content -LiteralPath (Join-Path $bootstrapRoot "environments/$environment/outputs.tf") -Raw
  Assert-Match $rootOutputs 'module\.state_backend\.backend_state_keys' "bootstrap/$environment root does not expose both approved state keys"
}

if ($backendTexts.dev -eq $backendTexts.prod) {
  Fail "DEV and PROD backend files must be different"
}
foreach ($identity in @("bucket", "kms_key_id", "role_arn")) {
  $identityPattern = '(?im)^\s*' + [regex]::Escape($identity) + '\s*=\s*"([^"]+)"'
  $devValue = [regex]::Match($backendTexts.dev, $identityPattern).Groups[1].Value
  $prodValue = [regex]::Match($backendTexts.prod, $identityPattern).Groups[1].Value
  if ([string]::IsNullOrWhiteSpace($devValue) -or $devValue -eq $prodValue) {
    Fail "DEV/PROD $identity isolation assertion failed"
  }
}

$devMain = Get-Content -LiteralPath (Join-Path $bootstrapRoot "environments/dev/main.tf") -Raw
$prodMain = Get-Content -LiteralPath (Join-Path $bootstrapRoot "environments/prod/main.tf") -Raw
Assert-Match $devMain 'create_resources\s*=\s*true' "DEV bootstrap must explicitly enable its planned resources"
Assert-Match $prodMain 'create_resources\s*=\s*false' "PROD bootstrap must remain design-only"

if (([regex]::Matches($moduleMain, 'prevent_destroy\s*=\s*true')).Count -ne 2) {
  Fail "both the state KMS key and S3 bucket must set prevent_destroy=true"
}
Assert-Match $moduleMain 'force_destroy\s*=\s*false' "state bucket force_destroy must be false"
Assert-Match $moduleMain 'depends_on\s*=\s*\[aws_s3_bucket_versioning\.state\]' "state lifecycle must depend on versioning"
Assert-Match $moduleMain 'versioning_configuration\s*\{[\s\S]*?status\s*=\s*"Enabled"' "state bucket versioning is missing"
foreach ($control in @("block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets")) {
  Assert-Match $moduleMain ($control + '\s*=\s*true') "S3 public-access control is missing: $control"
}
Assert-Match $moduleMain 'object_ownership\s*=\s*"BucketOwnerEnforced"' "BucketOwnerEnforced is missing"
Assert-Match $moduleMain 'kms_master_key_id\s*=\s*aws_kms_key\.state\[0\]\.arn' "default SSE-KMS must use the actual state key ARN"
Assert-Match $moduleMain 'sse_algorithm\s*=\s*"aws:kms"' "default SSE-KMS algorithm is missing"
Assert-Match $moduleMain 'Sid\s*=\s*"DenyInsecureTransport"[\s\S]*?"aws:SecureTransport"\s*=\s*"false"' "TLS-only bucket deny is missing"
Assert-Match $moduleMain 'Sid\s*=\s*"DenyIncorrectExplicitEncryption"[\s\S]*?StringNotEquals[\s\S]*?"s3:x-amz-server-side-encryption"\s*=\s*"aws:kms"[\s\S]*?Null[\s\S]*?"s3:x-amz-server-side-encryption"\s*=\s*"false"' "explicit wrong encryption-algorithm deny is missing"
Assert-Match $moduleMain 'Sid\s*=\s*"DenyIncorrectExplicitKmsKey"[\s\S]*?ArnNotEquals[\s\S]*?"s3:x-amz-server-side-encryption-aws-kms-key-id"\s*=\s*aws_kms_key\.state\[0\]\.arn[\s\S]*?Null[\s\S]*?"s3:x-amz-server-side-encryption-aws-kms-key-id"\s*=\s*"false"' "explicit wrong KMS-key deny is missing"
if ($moduleMain -match '(?is)Null\s*=\s*\{\s*"s3:x-amz-server-side-encryption(?:-aws-kms-key-id)?"\s*=\s*"true"') {
  Fail "missing encryption headers must remain allowed so bucket default SSE-KMS can apply"
}

Assert-Match $moduleMain 'enable_key_rotation\s*=\s*true' "KMS rotation is missing"
Assert-Match $moduleMain 'deletion_window_in_days\s*=\s*30' "KMS deletion window is missing"
Assert-Match $moduleMain 'var\.allow_root_for_v1\s*\?\s*\[\{[\s\S]*?arn:aws:iam::\$\{var\.account_id\}:root' "state KMS root access must be guarded by the explicit V1 flag"
if ($moduleMain -match 'Action\s*=\s*"kms:\*"') { Fail "state KMS policy must not use kms:*" }
foreach ($sid in [regex]::Matches($moduleMain, '(?im)^\s*Sid\s*=\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) {
  $renderedSid = $sid.Replace('${role_index}', '0')
  if ($renderedSid -notmatch '^[A-Za-z0-9]+$') {
    Fail "KMS Sid renders invalid characters: $sid"
  }
}

$hclRolePrefix = '^arn:aws:iam::${var.account_id}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$'
if (-not $moduleVariables.Contains($hclRolePrefix)) {
  Fail "same-account IAM role validation with path support is missing"
}
Assert-Match $moduleVariables 'var\.allow_root_for_v1[\s\S]*?length\(var\.terraform_role_arns\)\s*>\s*0' "state roles may be omitted only under the V1 root shortcut"
$rolePattern = '^arn:aws:iam::123456789012:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$'
if ("arn:aws:iam::123456789012:role/platform/dev/TerraformExecution" -notmatch $rolePattern) {
  Fail "role validation regression: a reasonable IAM role path must be accepted"
}
foreach ($invalidRole in @(
    "arn:aws:iam::210987654321:role/platform/dev/TerraformExecution",
    "arn:aws:iam::123456789012:role/platform/*",
    "arn:aws:iam::123456789012:role/"
  )) {
  if ($invalidRole -match $rolePattern) {
    Fail "role validation regression: invalid role was accepted: $invalidRole"
  }
}

# TASK-INF-003 networking assertions.
$networkingMain = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/networking/main.tf") -Raw
$networkingVariables = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/networking/variables.tf") -Raw
$networkingOutputs = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/networking/outputs.tf") -Raw
$networkingResources = [regex]::Matches($networkingMain, '(?im)^\s*resource\s+"([^"]+)"\s+"([^"]+)"')
$expectedNetworkingResources = @{
  "aws_vpc.this"                       = 1
  "aws_subnet.private"                 = 1
  "aws_route_table.private"            = 1
  "aws_route_table_association.private" = 1
  "aws_vpc_endpoint.s3"                = 1
}
if ($networkingResources.Count -ne $expectedNetworkingResources.Count) {
  Fail "networking must contain exactly five approved resource declarations"
}
foreach ($expected in $expectedNetworkingResources.Keys) {
  $parts = $expected.Split('.')
  $count = @($networkingResources | Where-Object { $_.Groups[1].Value -eq $parts[0] -and $_.Groups[2].Value -eq $parts[1] }).Count
  if ($count -ne 1) {
    Fail "networking resource declaration missing or duplicated: $expected"
  }
}
Assert-Match $networkingMain 'resource\s+"aws_subnet"\s+"private"\s*\{[\s\S]*?count\s*=\s*2' "networking must create exactly two private subnets"
Assert-Match $networkingMain 'resource\s+"aws_route_table_association"\s+"private"\s*\{[\s\S]*?count\s*=\s*2' "networking must create exactly two route-table associations"
Assert-Match $networkingMain 'cidr_block\s*=\s*cidrsubnet\(var\.vpc_cidr,\s*var\.private_subnet_newbits,\s*var\.private_subnet_netnums\[count\.index\]\)' "private subnet CIDRs must use the approved cidrsubnet expression"
Assert-Match $networkingVariables 'length\(var\.private_subnet_netnums\)\s*==\s*2' "exactly two subnet netnums must be required"
Assert-Match $networkingVariables 'netnum\s*>=\s*0' "subnet netnums must be non-negative"
Assert-Match $networkingVariables 'netnum\s*<\s*pow\(2,\s*var\.private_subnet_newbits\)' "subnet netnums must remain below 2^newbits"
Assert-Match $networkingVariables 'var\.private_subnet_netnums\[0\]\s*!=\s*var\.private_subnet_netnums\[1\]' "subnet netnums must be distinct"
Assert-Match $networkingVariables 'var\.private_subnet_newbits\s*>=\s*1[\s\S]*?var\.private_subnet_newbits\s*<=\s*8' "private_subnet_newbits must have the approved bounded range"
Assert-Match $networkingVariables 'length\(var\.availability_zones\)\s*==\s*2' "exactly two availability zones must be required"
Assert-Match $networkingVariables 'var\.availability_zones\[0\]\s*!=\s*var\.availability_zones\[1\]' "availability zones must be distinct"
Assert-Match $networkingVariables '\^ap-southeast-2\[a-z\]\$' "availability zones must be restricted to Sydney"
Assert-Match $networkingMain 'service_name\s*=\s*"com\.amazonaws\.ap-southeast-2\.s3"' "the S3 endpoint service must be Sydney"
Assert-Match $networkingMain 'vpc_endpoint_type\s*=\s*"Gateway"' "the S3 endpoint must be Gateway type"
Assert-Match $networkingMain 'route_table_ids\s*=\s*\[aws_route_table\.private\.id\]' "the S3 endpoint must use the private route table"
Assert-Match $networkingMain 'map_public_ip_on_launch\s*=\s*false' "private subnets must disable automatic public IPs"
if ($networkingMain -match '(?im)^\s*resource\s+"aws_(internet_gateway|nat_gateway|eip|route)"' -or
    $networkingMain -match 'vpc_endpoint_type\s*=\s*"Interface"' -or
    $networkingMain -match 'map_public_ip_on_launch\s*=\s*true' -or
    $networkingMain -match 'assign_ipv6_address_on_creation\s*=\s*true' -or
    $networkingMain -match '0\.0\.0\.0/0') {
  Fail "networking contains a prohibited internet/NAT/interface/public route or address control"
}
foreach ($requiredOutput in @("vpc_id", "private_subnet_ids", "private_subnet_cidrs", "private_route_table_id", "s3_gateway_endpoint_id")) {
  Assert-Match $networkingOutputs ('(?im)^\s*output\s+"' + $requiredOutput + '"') "networking output missing: $requiredOutput"
}

# TASK-INF-003 shared tag-contract assertions.
foreach ($moduleName in @("networking", "kms", "s3")) {
  $variablesText = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/$moduleName/variables.tf") -Raw
  $tagsBlock = [regex]::Match($variablesText, '(?ms)^variable\s+"tags"\s*\{(?<body>.*)\}\s*$').Groups['body'].Value
  if ([string]::IsNullOrWhiteSpace($tagsBlock) -or $tagsBlock -match '(?im)^\s*default\s*=') {
    Fail "$moduleName tags must be required and have no default"
  }
  foreach ($tagKey in @("Project", "Environment", "Owner", "ManagedBy", "CostCenter", "DataClassification")) {
    if (-not $tagsBlock.Contains('"' + $tagKey + '"')) {
      Fail "$moduleName tags validation is missing required key: $tagKey"
    }
  }
  Assert-Match $tagsBlock 'trimspace\(lookup\(var\.tags,\s*key,\s*""\)\)\s*!=\s*""' "$moduleName must reject empty required tag values"
  Assert-Match $tagsBlock 'lookup\(var\.tags,\s*"ManagedBy",\s*""\)\s*==\s*"terraform"' "$moduleName ManagedBy must be terraform"
  foreach ($classification in @("public", "internal", "confidential", "restricted")) {
    if (-not $tagsBlock.Contains('"' + $classification + '"')) {
      Fail "$moduleName DataClassification allowlist is incomplete: $classification"
    }
  }
}

# TASK-INF-003 reusable KMS assertions.
$kmsMain = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/kms/main.tf") -Raw
$kmsVariables = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/kms/variables.tf") -Raw
$kmsResources = [regex]::Matches($kmsMain, '(?im)^\s*resource\s+"([^"]+)"\s+"([^"]+)"')
if ($kmsResources.Count -ne 2 -or
    ([regex]::Matches($kmsMain, '(?im)^\s*resource\s+"aws_kms_key"\s+"this"')).Count -ne 1 -or
    ([regex]::Matches($kmsMain, '(?im)^\s*resource\s+"aws_kms_alias"\s+"this"')).Count -ne 1) {
  Fail "KMS module must declare exactly one key and one alias"
}
Assert-Match $kmsMain 'enable_key_rotation\s*=\s*true' "KMS rotation is missing"
Assert-Match $kmsMain 'deletion_window_in_days\s*=\s*30' "KMS 30-day deletion window is missing"
Assert-Match $kmsMain 'prevent_destroy\s*=\s*true' "KMS key deletion protection is missing"
Assert-Match $kmsMain 'target_key_id\s*=\s*aws_kms_key\.this\.key_id' "KMS alias target is missing"
if (([regex]::Matches($kmsMain, 'Action\s*=\s*"kms:\*"')).Count -gt 0) {
  Fail "KMS must not contain direct kms:*"
}
Assert-Match $kmsMain 'var\.allow_root_for_v1\s*\?\s*\[\{[\s\S]*?arn:aws:iam::\$\{var\.account_id\}:root' "platform KMS root access must be guarded by the explicit V1 flag"
$kmsAdmin = [regex]::Match($kmsMain, '(?s)for role_index, role_arn in var\.admin_role_arns\s*:\s*\{(?<body>.*?)\n\s*\}\n\s*\],').Groups['body'].Value
$kmsUser = [regex]::Match($kmsMain, '(?s)for role_index, role_arn in var\.user_role_arns\s*:\s*\{(?<body>.*?)\n\s*\}\n\s*\],').Groups['body'].Value
if ([string]::IsNullOrWhiteSpace($kmsAdmin) -or $kmsAdmin -match 'kms:\*') {
  Fail "direct KMS administrators must have explicit management actions and no kms:*"
}
foreach ($adminAction in @("kms:PutKeyPolicy", "kms:EnableKeyRotation", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:CreateGrant")) {
  if (-not $kmsAdmin.Contains('"' + $adminAction + '"')) {
    Fail "direct KMS administrator action missing: $adminAction"
  }
}
foreach ($userAction in @("kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:ReEncrypt*")) {
  if (-not $kmsUser.Contains('"' + $userAction + '"')) {
    Fail "KMS user data-plane action missing: $userAction"
  }
}
if (([regex]::Matches($kmsVariables, [regex]::Escape($hclRolePrefix))).Count -ne 2) {
  Fail "KMS admin and user role validations must both be same-account, path-capable, and wildcard-free"
}
Assert-Match $kmsVariables 'length\(var\.admin_role_arns\)\s*>\s*0' "at least one KMS administrator is required"
Assert-Match $kmsVariables 'variable\s+"user_role_arns"[\s\S]*?default\s*=\s*\[\]' "KMS user roles must be allowed to remain empty"
Assert-Match $kmsMain 'Purpose\s*=\s*var\.purpose' "KMS purpose must be applied as a Purpose tag"

# TASK-INF-003 reusable S3 assertions.
$s3Main = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/s3/main.tf") -Raw
$s3Variables = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/s3/variables.tf") -Raw
$s3Resources = [regex]::Matches($s3Main, '(?im)^\s*resource\s+"([^"]+)"\s+"([^"]+)"')
$expectedS3Types = @(
  "aws_s3_bucket"
  "aws_s3_bucket_versioning"
  "aws_s3_bucket_ownership_controls"
  "aws_s3_bucket_public_access_block"
  "aws_s3_bucket_server_side_encryption_configuration"
  "aws_s3_bucket_lifecycle_configuration"
  "aws_s3_bucket_policy"
)
if ($s3Resources.Count -ne $expectedS3Types.Count) {
  Fail "S3 module must declare exactly seven approved resources"
}
foreach ($resourceType in $expectedS3Types) {
  if (@($s3Resources | Where-Object { $_.Groups[1].Value -eq $resourceType }).Count -ne 1) {
    Fail "S3 resource declaration missing or duplicated: $resourceType"
  }
}
foreach ($bucketRule in @('!strcontains(var.bucket_name, "..")', '!strcontains(var.bucket_name, ".-")', '!strcontains(var.bucket_name, "-.")', 'xn--', 'amzn-s3-demo-', '-s3alias', '--x-s3', '--table-s3')) {
  if (-not $s3Variables.Contains($bucketRule)) {
    Fail "S3 bucket-name validation is missing rule: $bucketRule"
  }
}
Assert-Match $s3Variables '\^\[0-9\]\{1,3\}\(\\\\\.\[0-9\]\{1,3\}\)\{3\}\$' "S3 bucket names must reject IP-address format"
Assert-Match $s3Variables '\^arn:aws:kms:ap-southeast-2:\[0-9\]\{12\}:key/\[0-9a-fA-F\]\{8\}' "S3 KMS input must be an actual Sydney key ARN"
Assert-Match $s3Variables 'variable\s+"purpose"[\s\S]*?contains\(' "S3 purpose must be non-empty and allowlisted"
Assert-Match $s3Main 'Purpose\s*=\s*var\.purpose' "S3 purpose must be applied as a Purpose tag"
$retentionBlock = [regex]::Match($s3Variables, '(?ms)^variable\s+"noncurrent_retention_days"\s*\{(?<body>.*?)^\}').Groups['body'].Value
if ([string]::IsNullOrWhiteSpace($retentionBlock) -or $retentionBlock -match '(?im)^\s*default\s*=') {
  Fail "S3 noncurrent retention must be required and have no default"
}
Assert-Match $s3Main 'force_destroy\s*=\s*false' "S3 force_destroy must be false"
Assert-Match $s3Main 'prevent_destroy\s*=\s*true' "S3 bucket deletion protection is missing"
Assert-Match $s3Main 'depends_on\s*=\s*\[aws_s3_bucket_versioning\.this\]' "S3 lifecycle must depend on versioning"
Assert-Match $s3Main 'filter\s*\{\s*\}' "S3 lifecycle must include an all-object filter"
Assert-Match $s3Main 'versioning_configuration\s*\{[\s\S]*?status\s*=\s*"Enabled"' "S3 versioning is missing"
Assert-Match $s3Main 'object_ownership\s*=\s*"BucketOwnerEnforced"' "S3 BucketOwnerEnforced is missing"
foreach ($control in @("block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets")) {
  Assert-Match $s3Main ($control + '\s*=\s*true') "S3 public-access control is missing: $control"
}
Assert-Match $s3Main 'kms_master_key_id\s*=\s*var\.kms_key_arn' "S3 default encryption must use the supplied KMS key ARN"
Assert-Match $s3Main 'sse_algorithm\s*=\s*"aws:kms"' "S3 default encryption algorithm is missing"
Assert-Match $s3Main 'Sid\s*=\s*"DenyInsecureTransport"[\s\S]*?"aws:SecureTransport"\s*=\s*"false"' "S3 TLS-only deny is missing"
Assert-Match $s3Main 'Sid\s*=\s*"DenyIncorrectExplicitEncryption"[\s\S]*?StringNotEquals[\s\S]*?"s3:x-amz-server-side-encryption"\s*=\s*"aws:kms"[\s\S]*?Null[\s\S]*?"s3:x-amz-server-side-encryption"\s*=\s*"false"' "S3 explicit wrong-algorithm deny is missing"
Assert-Match $s3Main 'Sid\s*=\s*"DenyIncorrectExplicitKmsKey"[\s\S]*?ArnNotEquals[\s\S]*?"s3:x-amz-server-side-encryption-aws-kms-key-id"\s*=\s*var\.kms_key_arn[\s\S]*?Null[\s\S]*?"s3:x-amz-server-side-encryption-aws-kms-key-id"\s*=\s*"false"' "S3 explicit wrong-key deny is missing"
if ($s3Main -match '(?is)Null\s*=\s*\{\s*"s3:x-amz-server-side-encryption(?:-aws-kms-key-id)?"\s*=\s*"true"') {
  Fail "S3 missing encryption headers must remain allowed for default SSE-KMS"
}

# TASK-INF-004 IAM, Glue, Lake Formation, and monitoring assertions.
$iamMain = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/iam/main.tf") -Raw
$iamVariables = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/iam/variables.tf") -Raw
$iamResources = [regex]::Matches($iamMain, '(?im)^\s*resource\s+"([^"]+)"\s+"([^"]+)"')
if ($iamResources.Count -ne 4 -or
    ([regex]::Matches($iamMain, '(?im)^\s*resource\s+"aws_iam_role"')).Count -ne 2 -or
    ([regex]::Matches($iamMain, '(?im)^\s*resource\s+"aws_iam_role_policy"')).Count -ne 2) {
  Fail "IAM must declare exactly two roles and two inline role policies"
}
if ($iamMain -match '(?i)AdministratorAccess|PowerUser|Action\s*=\s*"\*"|"iam:\*"|"kms:\*"') {
  Fail "IAM contains a forbidden broad policy action or managed-policy name"
}
if (([regex]::Matches($iamMain, 'Resource\s*=\s*"\*"')).Count -ne 1) {
  Fail "IAM Resource=* must occur exactly once for unsupported resource-level discovery APIs"
}
foreach ($unscopedAction in @("ec2:DescribeAvailabilityZones", "sts:GetCallerIdentity")) {
  if (-not $iamMain.Contains('"' + $unscopedAction + '"')) {
    Fail "IAM unscoped discovery action missing: $unscopedAction"
  }
}
if ($iamMain.Contains('"s3:ListAllMyBuckets"')) {
  Fail "Terraform review role must not include unnecessary s3:ListAllMyBuckets"
}
Assert-Match $iamMain 'Sid\s*=\s*"PassLakeFormationRegistrationRoleOnly"[\s\S]*?Action\s*=\s*"iam:PassRole"[\s\S]*?Resource\s*=\s*aws_iam_role\.lakeformation_registration\.arn[\s\S]*?"iam:PassedToService"\s*=\s*"lakeformation\.amazonaws\.com"' "PassRole must be scoped to the created registration role and Lake Formation service"
Assert-Match $iamMain 'Principal\s*=\s*\{\s*AWS\s*=\s*var\.trusted_role_arns' "Terraform trust must use explicit approved roles"
Assert-Match $iamMain 'Principal\s*=\s*\{\s*Service\s*=\s*"lakeformation\.amazonaws\.com"' "registration-role trust must use Lake Formation"
Assert-Match $iamVariables 'length\(var\.trusted_role_arns\)\s*>\s*0' "Terraform trust-role input must be non-empty"
Assert-Match $iamVariables '\^arn:aws:iam::\$\{var\.account_id\}:role/\(\[A-Za-z0-9\+=,\.@_-\]\+/\)\*' "Terraform trust role validation must be same-account and path-capable"
foreach ($iamScope in @("var.data_location_bucket_arns", "local.data_location_object_arns", "var.data_kms_key_arns")) {
  if (-not $iamMain.Contains("Resource = $iamScope")) {
    Fail "Lake Formation registration policy scope missing: $iamScope"
  }
}
foreach ($kmsAction in @("kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:ReEncrypt*")) {
  if (-not $iamMain.Contains('"' + $kmsAction + '"')) {
    Fail "Lake Formation registration KMS action missing: $kmsAction"
  }
}

$glueMain = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/glue/main.tf") -Raw
$glueVariables = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/glue/variables.tf") -Raw
if (([regex]::Matches($glueMain, '(?im)^\s*resource\s+"aws_glue_catalog_database"\s+"layer"')).Count -ne 1 -or
    ([regex]::Matches($glueMain, '(?im)^\s*resource\s+"')).Count -ne 1) {
  Fail "Glue must use exactly one four-item database resource declaration"
}
foreach ($layer in @("bronze", "silver", "gold", "control")) {
  if (-not $glueMain.Contains($layer)) {
    Fail "Glue layer mapping missing: $layer"
  }
}
Assert-Match $glueMain 'for_each\s*=\s*local\.database_locations' "Glue database declaration must use the exact layer map"
Assert-Match $glueMain 'name\s*=\s*"insurance_\$\{var\.environment\}_\$\{each\.key\}"' "Glue database naming contract is missing"
Assert-Match $glueVariables '!contains\(' "Glue control location must be distinct from all lakehouse locations"
if ($glueMain -match '(?im)^\s*resource\s+"aws_glue_(catalog_table|job|crawler)"') {
  Fail "Glue module must not create tables, jobs, or crawlers"
}

$lakeFormationMain = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/lakeformation/main.tf") -Raw
$lakeFormationVariables = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/lakeformation/variables.tf") -Raw
Assert-Match $lakeFormationMain 'resource\s+"aws_lakeformation_resource"\s+"location"[\s\S]*?for_each\s*=\s*local\.registered_locations[\s\S]*?role_arn\s*=\s*var\.data_access_role_arn[\s\S]*?use_service_linked_role\s*=\s*false' "Lake Formation must register exactly two locations with the explicit role"
Assert-Match $lakeFormationVariables 'lakehouse_location_arn[\s\S]*?control_location_arn' "Lake Formation two location inputs are missing"
Assert-Match $lakeFormationMain 'resource\s+"aws_lakeformation_data_lake_settings"[\s\S]*?admins\s*=\s*var\.admin_role_arns' "Lake Formation explicit admins are missing"
Assert-Match $lakeFormationMain 'resource\s+"aws_lakeformation_permissions"\s+"data_engineer_database"[\s\S]*?for_each\s*=\s*local\.data_engineer_databases[\s\S]*?principal\s*=\s*var\.data_engineer_role_arn' "DataEngineer four-database metadata grant is missing"
Assert-Match $lakeFormationMain 'permissions\s*=\s*\["ALTER",\s*"CREATE_TABLE",\s*"DESCRIBE"\]' "DataEngineer permissions must be ALTER, CREATE_TABLE, and DESCRIBE"
Assert-Match $lakeFormationMain 'resource\s+"aws_lakeformation_permissions"\s+"analyst_gold_database"[\s\S]*?principal\s*=\s*var\.analyst_role_arn[\s\S]*?name\s*=\s*var\.database_names\["gold"\]' "Analyst must receive only gold database metadata"
Assert-Match $lakeFormationMain 'resource\s+"aws_lakeformation_permissions"\s+"ml_engineer_database"[\s\S]*?for_each\s*=\s*local\.ml_engineer_databases[\s\S]*?principal\s*=\s*var\.ml_engineer_role_arn' "MLEngineer silver/gold database metadata grants are missing"
if ($lakeFormationMain.Contains("var.rag_application_role_arn") -or $lakeFormationMain -match 'SELECT|DROP|table\s*\{|table_with_columns') {
  Fail "RAGApplication and table/data permissions must not appear in Lake Formation grants"
}
Assert-Match $lakeFormationVariables 'length\(distinct\(concat\(' "Lake Formation workload/admin/access roles must be mutually distinct"
if (([regex]::Matches($lakeFormationVariables, '\^arn:aws:iam::\$\{var\.account_id\}:role/')).Count -lt 6) {
  Fail "every Lake Formation role input must be same-account and path-capable"
}

$monitoringMain = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/monitoring/main.tf") -Raw
$monitoringVariables = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/monitoring/variables.tf") -Raw
$monitoringResources = [regex]::Matches($monitoringMain, '(?im)^\s*resource\s+"([^"]+)"\s+"([^"]+)"')
if ($monitoringResources.Count -ne 14) {
  Fail "monitoring must declare exactly 14 resources for the complete audit chain"
}
foreach ($resourceType in @("aws_kms_key", "aws_kms_alias", "aws_s3_bucket", "aws_s3_bucket_versioning", "aws_s3_bucket_ownership_controls", "aws_s3_bucket_public_access_block", "aws_s3_bucket_server_side_encryption_configuration", "aws_s3_bucket_lifecycle_configuration", "aws_s3_bucket_policy", "aws_cloudwatch_log_group", "aws_iam_role", "aws_iam_role_policy", "aws_sns_topic", "aws_cloudtrail")) {
  if (@($monitoringResources | Where-Object { $_.Groups[1].Value -eq $resourceType }).Count -ne 1) {
    Fail "monitoring resource missing or duplicated: $resourceType"
  }
}
if (([regex]::Matches($monitoringMain, 'Action\s*=\s*"kms:\*"')).Count -gt 0) {
  Fail "monitoring KMS must not contain direct kms:*"
}
Assert-Match $monitoringMain 'var\.allow_root_for_v1\s*\?\s*\[\{[\s\S]*?arn:aws:iam::\$\{var\.account_id\}:root' "audit KMS root access must be guarded by the explicit V1 flag"
foreach ($kmsGrant in @("AllowCloudTrailGenerateDataKey", "AllowCloudTrailDescribeKey", "AllowCloudWatchLogsEncryption", "AllowSnsEncryption")) {
  Assert-Match $monitoringMain ('Sid\s*=\s*"' + $kmsGrant + '"[\s\S]*?Condition\s*=\s*\{') "conditioned monitoring KMS grant missing: $kmsGrant"
}
$generateStart = $monitoringMain.IndexOf('Sid    = "AllowCloudTrailGenerateDataKey"')
$describeStart = $monitoringMain.IndexOf('Sid    = "AllowCloudTrailDescribeKey"')
$logsStart = $monitoringMain.IndexOf('Sid    = "AllowCloudWatchLogsEncryption"')
if ($generateStart -lt 0 -or $describeStart -le $generateStart -or $logsStart -le $describeStart) {
  Fail "CloudTrail KMS statements must be separate and ordered"
}
$generateStatement = $monitoringMain.Substring($generateStart, $describeStart - $generateStart)
$describeStatement = $monitoringMain.Substring($describeStart, $logsStart - $describeStart)
foreach ($required in @('Action   = "kms:GenerateDataKey*"', '"aws:SourceAccount"', '"aws:SourceArn"', '"kms:EncryptionContext:aws:cloudtrail:arn"')) {
  if (-not $generateStatement.Contains($required)) {
    Fail "CloudTrail GenerateDataKey statement missing binding: $required"
  }
}
foreach ($required in @('Action   = "kms:DescribeKey"', '"aws:SourceAccount"', '"aws:SourceArn"')) {
  if (-not $describeStatement.Contains($required)) {
    Fail "CloudTrail DescribeKey statement missing binding: $required"
  }
}
if ($describeStatement.Contains('kms:EncryptionContext:aws:cloudtrail:arn')) {
  Fail "CloudTrail DescribeKey statement must not require encryption context"
}
foreach ($conditionKey in @("aws:SourceArn", "aws:SourceAccount", "kms:EncryptionContext:aws:cloudtrail:arn", "kms:EncryptionContext:aws:logs:arn")) {
  if (-not $monitoringMain.Contains('"' + $conditionKey + '"')) {
    Fail "monitoring KMS/delivery condition key missing: $conditionKey"
  }
}
Assert-Match $monitoringMain 'enable_key_rotation\s*=\s*true' "monitoring KMS rotation is missing"
Assert-Match $monitoringMain 'deletion_window_in_days\s*=\s*30' "monitoring KMS deletion window is missing"
if (([regex]::Matches($monitoringMain, 'prevent_destroy\s*=\s*true')).Count -ne 2) {
  Fail "monitoring KMS key and audit bucket must both have prevent_destroy"
}
Assert-Match $monitoringMain 'force_destroy\s*=\s*false' "audit bucket force_destroy must be false"
Assert-Match $monitoringMain 'depends_on\s*=\s*\[aws_s3_bucket_versioning\.audit\]' "audit lifecycle must depend on versioning"
Assert-Match $monitoringMain 'filter\s*\{\s*\}' "audit lifecycle must include an all-object filter"
Assert-Match $monitoringMain 'noncurrent_days\s*=\s*var\.audit_noncurrent_retention_days' "audit noncurrent retention input is not wired"
Assert-Match $monitoringMain 'expiration\s*\{[\s\S]*?days\s*=\s*var\.audit_retention_days' "audit current retention expiration is not wired"
$auditRetentionBlock = [regex]::Match($monitoringVariables, '(?ms)^variable\s+"audit_retention_days"\s*\{(?<body>.*?)^\}').Groups['body'].Value
if ([string]::IsNullOrWhiteSpace($auditRetentionBlock) -or $auditRetentionBlock -match '(?im)^\s*default\s*=') {
  Fail "audit_retention_days must be required with no default"
}
Assert-Match $auditRetentionBlock 'var\.audit_retention_days\s*>=\s*var\.audit_noncurrent_retention_days' "current audit retention must be at least noncurrent retention"
Assert-Match $monitoringMain 'kms_master_key_id\s*=\s*aws_kms_key\.audit\.arn' "audit bucket must use its dedicated KMS key"
Assert-Match $monitoringMain 'object_ownership\s*=\s*"BucketOwnerEnforced"' "audit bucket ownership control is missing"
foreach ($control in @("block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets")) {
  Assert-Match $monitoringMain ($control + '\s*=\s*true') "audit public access block missing: $control"
}
foreach ($bucketSid in @("DenyInsecureTransport", "AllowCloudTrailBucketAclCheck", "AllowCloudTrailWrite")) {
  Assert-Match $monitoringMain ('Sid\s*=\s*"' + $bucketSid + '"') "audit bucket policy statement missing: $bucketSid"
}
Assert-Match $monitoringMain '"s3:x-amz-acl"\s*=\s*"bucket-owner-full-control"' "CloudTrail writes must require bucket-owner-full-control"
Assert-Match $monitoringMain 'resource\s+"aws_cloudwatch_log_group"[\s\S]*?retention_in_days\s*=\s*var\.log_retention_days[\s\S]*?kms_key_id\s*=\s*aws_kms_key\.audit\.arn' "CloudWatch log group retention/encryption is incomplete"
Assert-Match $monitoringMain 'Resource\s*=\s*"\$\{aws_cloudwatch_log_group\.audit\.arn\}:log-stream:\*"' "CloudTrail delivery policy must be bound to target log streams"
Assert-Match $monitoringMain 'resource\s+"aws_cloudtrail"\s+"management"[\s\S]*?is_multi_region_trail\s*=\s*false[\s\S]*?include_global_service_events\s*=\s*true[\s\S]*?enable_logging\s*=\s*true' "CloudTrail regional management configuration is incomplete"
Assert-Match $monitoringMain 'event_selector\s*\{[\s\S]*?read_write_type\s*=\s*"All"[\s\S]*?include_management_events\s*=\s*true[\s\S]*?exclude_management_event_sources\s*=\s*\[\]' "CloudTrail management-only event selector is incomplete"
if ($monitoringMain -match 'data_resource\s*\{' -or $monitoringMain -match '(?im)^\s*resource\s+"aws_(sns_topic_subscription|cloudwatch_metric_alarm)"') {
  Fail "monitoring must contain no data resources, SNS subscriptions, or alarms"
}

foreach ($moduleName in @("iam", "glue", "lakeformation", "monitoring")) {
  $variablesText = Get-Content -LiteralPath (Join-Path $terraformRoot "modules/$moduleName/variables.tf") -Raw
  $tagsBlock = [regex]::Match($variablesText, '(?ms)^variable\s+"tags"\s*\{(?<body>.*)\}\s*$').Groups['body'].Value
  if ([string]::IsNullOrWhiteSpace($tagsBlock) -or $tagsBlock -match '(?im)^\s*default\s*=') {
    Fail "$moduleName tags must be required and have no default"
  }
  foreach ($tagKey in @("Project", "Environment", "Owner", "ManagedBy", "CostCenter", "DataClassification")) {
    if (-not $tagsBlock.Contains('"' + $tagKey + '"')) {
      Fail "$moduleName tag contract missing: $tagKey"
    }
  }
}

# TASK-INF-005 environment integration and reviewed-plan contract assertions.
$devRoot = Join-Path $terraformRoot "environments/dev"
$prodRoot = Join-Path $terraformRoot "environments/prod"
$devMain = Get-Content -LiteralPath (Join-Path $devRoot "main.tf") -Raw
$prodMain = Get-Content -LiteralPath (Join-Path $prodRoot "main.tf") -Raw
$devVariables = Get-Content -LiteralPath (Join-Path $devRoot "variables.tf") -Raw
$prodVariables = Get-Content -LiteralPath (Join-Path $prodRoot "variables.tf") -Raw
$devOutputs = Get-Content -LiteralPath (Join-Path $devRoot "outputs.tf") -Raw
$prodOutputs = Get-Content -LiteralPath (Join-Path $prodRoot "outputs.tf") -Raw
$devBackend = Get-Content -LiteralPath (Join-Path $devRoot "backend.hcl.example") -Raw
$prodBackend = Get-Content -LiteralPath (Join-Path $prodRoot "backend.hcl.example") -Raw
$devVersions = Get-Content -LiteralPath (Join-Path $devRoot "versions.tf") -Raw
$prodVersions = Get-Content -LiteralPath (Join-Path $prodRoot "versions.tf") -Raw

if ($devVersions -match 'backend\s+"s3"') { Fail "DEV V1 must use local state until reviewed bootstrap resources exist; S3 migration is deferred to V4" }
Assert-Match $prodVersions 'backend\s+"s3"\s*\{\s*\}' "PROD partial S3 backend declaration is missing"

foreach ($rootEntry in @(@("DEV", $devMain), @("PROD", $prodMain))) {
  $rootName = $rootEntry[0]
  $rootMain = $rootEntry[1]
  $requiredModules = if ($rootName -eq "DEV") { @("common", "networking", "platform_kms", "storage", "glue", "monitoring") } else { @("common", "networking", "platform_kms", "storage", "iam", "glue", "lakeformation", "monitoring") }
  foreach ($moduleName in $requiredModules) {
    if (([regex]::Matches($rootMain, '(?m)^module\s+"' + $moduleName + '"\s*\{')).Count -ne 1) {
      Fail "$rootName must wire module $moduleName exactly once"
    }
  }
  if ($rootMain -match '(?im)^\s*resource\s+"' -or $rootMain -match '(?i)source\s*=\s*"[^\"]*(nat|internet-gateway)') {
    Fail "$rootName root must use modules, declare no resources directly, and avoid forbidden internet egress modules"
  }
}
if ($devMain -match '(?m)^module\s+"(iam|lakeformation)"\s*\{') {
  Fail "DEV V1 must defer IAM persona and Lake Formation governance modules to V3"
}

$bucketPurposeMatch = [regex]::Match($devMain, '(?ms)for purpose in \[(?<purposes>.*?)\]\s*:\s*purpose')
if (-not $bucketPurposeMatch.Success) {
  Fail "DEV five-bucket purpose map is missing"
}
$devPurposes = @([regex]::Matches($bucketPurposeMatch.Groups['purposes'].Value, '"([^\"]+)"') | ForEach-Object { $_.Groups[1].Value })
$approvedPurposes = @("landing", "lakehouse", "control", "quarantine", "documents")
if (($devPurposes.Count -ne 5) -or (@(Compare-Object $approvedPurposes $devPurposes).Count -ne 0)) {
  Fail "DEV storage must contain exactly landing, lakehouse, control, quarantine, and documents"
}
Assert-Match $devMain 'module\s+"storage"[\s\S]*?for_each\s*=\s*local\.bucket_names' "DEV must instantiate five generic S3 modules"
Assert-Match $devMain 'kms_key_arn\s*=\s*module\.platform_kms\.key_arn' "DEV S3 must use the platform KMS key"
Assert-Match $devMain 'module\s+"platform_kms"\s*\{[\s\S]*?user_role_arns\s*=\s*\[\]' "DEV platform KMS must not directly grant data-plane roles in Phase 1"
Assert-Match $devMain 'lakehouse_location_uri\s*=\s*"s3://\$\{module\.storage\["lakehouse"\]\.bucket_id\}/lakehouse"' "DEV Glue lakehouse location wiring is missing"
Assert-Match $devMain 'control_location_uri\s*=\s*"s3://\$\{module\.storage\["control"\]\.bucket_id\}/control"' "DEV Glue control location wiring is missing"

$devEnableBlock = [regex]::Match($devVariables, '(?ms)^variable\s+"enable_deployment"\s*\{(?<body>.*?)^\}').Groups['body'].Value
Assert-Match $devEnableBlock 'default\s*=\s*true' "DEV enable_deployment must default true"
Assert-Match $devEnableBlock 'condition\s*=\s*var\.enable_deployment' "DEV topology switch must be locked enabled"

foreach ($moduleName in @("networking", "platform_kms", "iam", "glue", "lakeformation", "monitoring")) {
  Assert-Match $prodMain ('module\s+"' + $moduleName + '"\s*\{[\s\S]*?count\s*=\s*var\.enable_deployment\s*\?\s*1\s*:\s*0') "PROD resource module $moduleName must be count-gated"
}
Assert-Match $prodMain 'module\s+"storage"\s*\{[\s\S]*?for_each\s*=\s*var\.enable_deployment\s*\?\s*local\.bucket_names\s*:\s*\{\}' "PROD storage modules must be gated to an empty map"
Assert-Match $prodMain 'module\s+"platform_kms"\s*\{[\s\S]*?user_role_arns\s*=\s*\[\]' "PROD platform KMS design must not directly grant data-plane roles"
$prodEnableBlock = [regex]::Match($prodVariables, '(?ms)^variable\s+"enable_deployment"\s*\{(?<body>.*?)^\}').Groups['body'].Value
Assert-Match $prodEnableBlock 'default\s*=\s*false' "PROD enable_deployment must default false"
Assert-Match $prodEnableBlock 'condition\s*=\s*!var\.enable_deployment' "PROD deployment must be validation-locked off in Phase 1"
if (([regex]::Matches($prodOutputs, 'try\(module\.(networking|platform_kms|iam|glue|lakeformation|monitoring)\[0\]')).Count -lt 6) {
  Fail "PROD resource-bearing module outputs must be count-safe"
}
Assert-Match $prodOutputs 'expected_resource_instance_count[\s\S]*?value\s*=\s*0' "PROD expected instance output must be zero"
Assert-Match $devOutputs 'expected_resource_instance_count[\s\S]*?value\s*=\s*62' "DEV expected V1 instance output must be 62"

foreach ($requiredInput in @("account_id", "account_short", "org_short", "vpc_cidr", "availability_zones", "data_noncurrent_retention_days", "audit_noncurrent_retention_days", "audit_retention_days", "log_retention_days", "monthly_budget_usd")) {
  $inputBlock = [regex]::Match($devVariables, '(?ms)^variable\s+"' + $requiredInput + '"\s*\{(?<body>.*?)^\}').Groups['body'].Value
  if ([string]::IsNullOrWhiteSpace($inputBlock) -or $inputBlock -match '(?im)^\s*default\s*=') {
    Fail "DEV plan input $requiredInput must be explicit and have no default"
  }
}

foreach ($backendEntry in @(@("DEV", $devBackend, "dev"), @("PROD", $prodBackend, "prod"))) {
  $backendName = $backendEntry[0]
  $backendText = $backendEntry[1]
  $environmentName = $backendEntry[2]
  foreach ($setting in @('key\s*=\s*"foundation/terraform\.tfstate"', 'region\s*=\s*"ap-southeast-2"', 'encrypt\s*=\s*true', 'use_lockfile\s*=\s*true', 'kms_key_id\s*=\s*"arn:aws:kms:ap-southeast-2:<account_id>:key/<')) {
    Assert-Match $backendText $setting "$backendName foundation backend setting is missing: $setting"
  }
  Assert-Match $backendText ('bucket\s*=\s*"<org>-insurance-' + $environmentName + '-tfstate-<account_short>"') "$backendName foundation backend bucket is not environment-isolated"
  Assert-Match $backendText ('role_arn\s*=\s*"arn:aws:iam::<account_id>:role/<' + $environmentName + '_terraform_backend_role_path_and_name>"') "$backendName backend role placeholder is not environment-isolated"
}
if ($devBackend -eq $prodBackend) {
  Fail "DEV and PROD foundation backend examples must remain distinct"
}

$manifestPath = Join-Path $repo "tests/infrastructure/approved-plan-manifest.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$patternTotal = ($manifest.environments.dev.address_patterns | Measure-Object -Property count -Sum).Sum
if ($manifest.environments.dev.expected_active_changes -ne 62 -or $patternTotal -ne 62) {
  Fail "DEV V1 approved manifest and address-pattern counts must both equal 62"
}
if ($manifest.environments.prod.expected_active_changes -ne 0 -or @($manifest.environments.prod.address_patterns).Count -ne 0) {
  Fail "PROD approved manifest must permit zero active changes"
}
foreach ($forbiddenType in @("aws_internet_gateway", "aws_nat_gateway", "aws_sns_topic_subscription", "aws_cloudwatch_metric_alarm", "aws_bedrockagent_agent", "aws_bedrockagent_knowledge_base")) {
  if (@($manifest.forbidden_resource_types) -notcontains $forbiddenType) {
    Fail "approved plan manifest must reject forbidden resource type: $forbiddenType"
  }
}
$planValidator = Get-Content -LiteralPath (Join-Path $repo "tests/infrastructure/validate-plan.ps1") -Raw
foreach ($planRule in @('only create is allowed', 'PROD must have zero resource changes', 'map_public_ip_on_launch', 'vpc_endpoint_type', 'force_destroy=false', 'must match exactly one approved address pattern')) {
  if (-not $planValidator.Contains($planRule)) {
    Fail "PowerShell plan validator is missing rule: $planRule"
  }
}

$secretPattern = '(?i)(aws_access_key_id|aws_secret_access_key|password\s*=\s*"|secret\s*=\s*"|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)'
$scanFiles = @(Get-ChildItem -LiteralPath $terraformRoot, (Join-Path $repo "buildspecs"), (Join-Path $repo "tests/infrastructure") -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -notin @("validate.ps1", "validate.sh") -and
      $_.FullName -notmatch '\\.terraform([\\/]|$)' -and
      ($_.Name -like "*.tf*" -or $_.Name -like "*.hcl*" -or $_.Extension -in @(".json", ".yaml", ".yml", ".ps1", ".sh"))
    })
foreach ($file in $scanFiles) {
  if ((Get-Content -LiteralPath $file.FullName -Raw) -match $secretPattern) {
    Fail "possible credential material detected: $($file.FullName)"
  }
}

Write-Output "PASS: offline TASK-INF-001/002/003/004/005 infrastructure assertions. AWS changes performed: None."
