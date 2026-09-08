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

# TASK-INF-002 phase scopes. Later tasks extend this table explicitly with their
# approved foundation paths and type allowlists; they do not weaken this check.
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
)

foreach ($file in $terraformFiles) {
  $content = Get-Content -LiteralPath $file.FullName -Raw
  $declarations = [regex]::Matches($content, '(?im)^\s*resource\s+"([^"]+)"')
  foreach ($declaration in $declarations) {
    $scope = $resourceScopes | Where-Object {
      $file.FullName.StartsWith($_.Prefix, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if ($null -eq $scope) {
      Fail "resource outside an approved TASK-INF-002 scope: $($file.FullName)"
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

foreach ($outputFile in $terraformFiles | Where-Object { $_.Name -eq "outputs.tf" -and $_.FullName.StartsWith($bootstrapRoot, [System.StringComparison]::OrdinalIgnoreCase) }) {
  $outputText = Get-Content -LiteralPath $outputFile.FullName -Raw
  $outputCount = ([regex]::Matches($outputText, '(?im)^\s*output\s+"')).Count
  $descriptionCount = ([regex]::Matches($outputText, '(?im)^\s*description\s*=')).Count
  if ($outputCount -ne $descriptionCount) {
    Fail "every bootstrap output must have one description: $($outputFile.FullName)"
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

Write-Output "PASS: offline infrastructure/bootstrap assertions. AWS changes performed: None."
