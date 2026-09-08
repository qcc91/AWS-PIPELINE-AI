$ErrorActionPreference = "Stop"

# Offline-only IaC gate. This script never runs init, plan, apply, or AWS CLI.
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$terraformRoot = Join-Path $repo "terraform"
$terraform = Get-Command terraform -ErrorAction SilentlyContinue

if ($null -eq $terraform) {
  Write-Warning "terraform not installed; fmt/validate are recorded as NOT RUN (offline evidence)."
} else {
  & $terraform.Source fmt -check -recursive $terraformRoot
  if ($LASTEXITCODE -ne 0) { throw "terraform fmt -check failed" }

  $roots = @("terraform/environments/dev", "terraform/environments/prod") | ForEach-Object { Join-Path $repo $_ }
  foreach ($root in $roots) {
    if (Test-Path (Join-Path $root ".terraform")) {
      & $terraform.Source "-chdir=$root" validate -no-color
      if ($LASTEXITCODE -ne 0) { throw "terraform validate failed: $root" }
    } else {
      Write-Warning "terraform validate skipped for ${root}: no initialized provider cache; do not download dependencies in this gate."
    }
  }
}

$allTf = (Get-ChildItem $terraformRoot -Recurse -Filter *.tf | Where-Object FullName -NotMatch '\\.terraform([\\/]|$)' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
if ($allTf -match '(?im)^\s*resource\s+"') { throw "TASK-INF-001 must not define AWS resources" }
if ($allTf -match '(?im)^\s*workspace\s*=') { throw "workspaces are not environment boundaries" }
foreach ($env in @("dev", "prod")) {
  $rootTf = (Get-ChildItem (Join-Path $terraformRoot "environments/$env") -Recurse -Filter *.tf | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  if ($rootTf -notmatch 'provider\s+"aws"' -or $rootTf -notmatch 'region\s*=\s*var\.aws_region') { throw "${env} provider region contract missing" }
  if ($rootTf -notmatch 'default\s*=\s*"ap-southeast-2"') { throw "${env} Sydney validation missing" }
}

$secretPatterns = '(?i)(aws_access_key_id|aws_secret_access_key|password\s*=|secret\s*=\s*"|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)'
$trackedText = (Get-ChildItem $terraformRoot, (Join-Path $repo "buildspecs"), (Join-Path $repo "tests/infrastructure") -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notin @('validate.ps1', 'validate.sh') -and $_.FullName -notmatch '\\.terraform([\\/]|$)' -and $_.Extension -in @('.tf', '.tfvars', '.hcl', '.json', '.yaml', '.yml', '.ps1', '.sh') } |
  ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
if ($trackedText -match $secretPatterns) { throw "possible credential material detected" }

Write-Output "Offline infrastructure boundary and secret checks passed. AWS changes performed: None."
