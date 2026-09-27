[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Profile,
  [Parameter(Mandatory = $true)][string]$TerraformDirectory,
  [Parameter(Mandatory = $true)][string]$PlanPath,
  [string[]]$VariableArguments = @(),
  [string[]]$TargetArguments = @(),
  [switch]$SkipRefresh
)

$ErrorActionPreference = "Stop"
$credentialJson = & aws configure export-credentials --profile $Profile --format process
if ($LASTEXITCODE -ne 0 -or -not $credentialJson) {
  throw "Unable to export temporary credentials for profile $Profile"
}
$credentials = ConvertFrom-Json -InputObject ([string]::Join([Environment]::NewLine, $credentialJson))

try {
  $env:AWS_ACCESS_KEY_ID = $credentials.AccessKeyId
  $env:AWS_SECRET_ACCESS_KEY = $credentials.SecretAccessKey
  $env:AWS_SESSION_TOKEN = $credentials.SessionToken
  $env:AWS_REGION = "ap-southeast-2"
  $env:AWS_DEFAULT_REGION = "ap-southeast-2"
  Remove-Variable credentials, credentialJson

  $terraformArguments = @("-chdir=$TerraformDirectory", "plan", "-input=false", "-no-color", "-out=$PlanPath")
  if ($SkipRefresh) {
    $terraformArguments += "-refresh=false"
  }
  $terraformArguments += $VariableArguments | ForEach-Object { "-var=$_" }
  $terraformArguments += $TargetArguments | ForEach-Object { "-target=$_" }
  & terraform @terraformArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Terraform plan failed for $TerraformDirectory"
  }
}
finally {
  Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
  Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
  Remove-Item Env:AWS_REGION -ErrorAction SilentlyContinue
  Remove-Item Env:AWS_DEFAULT_REGION -ErrorAction SilentlyContinue
}
