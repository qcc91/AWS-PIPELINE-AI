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
Assert-Match $moduleMain 'AWS\s*=\s*"arn:aws:iam::\$\{var\.account_id\}:root"' "same-account root delegation is missing"
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
Assert-Match $moduleVariables 'length\(var\.terraform_role_arns\)\s*>\s*0' "at least one state-key role ARN must be required"
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
if (([regex]::Matches($kmsMain, 'Action\s*=\s*"kms:\*"')).Count -ne 1 -or
    ([regex]::Matches($kmsMain, 'Sid\s*=\s*"EnableAccountRootDelegation"')).Count -ne 1) {
  Fail "KMS must contain exactly one account-root kms:* delegation statement"
}
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

$secretPattern = '(?i)(aws_access_key_id|aws_secret_access_key|password\s*=|secret\s*=\s*"|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)'
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

Write-Output "PASS: offline TASK-INF-001/002/003 infrastructure assertions. AWS changes performed: None."
