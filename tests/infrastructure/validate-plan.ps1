[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("dev", "prod")]
  [string]$Environment,

  [Parameter(Mandatory = $true)]
  [string]$PlanJson,

  [string]$Manifest = (Join-Path $PSScriptRoot "approved-plan-manifest.json")
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
  throw "PLAN VALIDATION FAILED: $Message"
}

if (-not (Test-Path -LiteralPath $PlanJson -PathType Leaf)) {
  Fail "plan JSON does not exist: $PlanJson"
}
if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
  Fail "approved manifest does not exist: $Manifest"
}

$manifestDocument = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json -Depth 100
$plan = Get-Content -LiteralPath $PlanJson -Raw | ConvertFrom-Json -Depth 100
$contract = $manifestDocument.environments.PSObject.Properties[$Environment].Value
if ($null -eq $contract) {
  Fail "manifest has no contract for $Environment"
}

$changes = @($plan.resource_changes)
if ($contract.expected_active_changes -eq 0) {
  if ($changes.Count -ne 0) {
    Fail "PROD must have zero resource changes, found $($changes.Count)"
  }
  Write-Output "PASS: prod reviewed plan contains zero actions and zero resource changes."
  exit 0
}

if ($changes.Count -ne [int]$contract.expected_active_changes) {
  Fail "$Environment must contain exactly $($contract.expected_active_changes) create changes, found $($changes.Count)"
}

$forbiddenTypes = @($manifestDocument.forbidden_resource_types)
$patterns = @($contract.address_patterns)
$matchedCounts = @{}
foreach ($patternContract in $patterns) {
  $matchedCounts[[string]$patternContract.pattern] = 0
}

foreach ($resourceChange in $changes) {
  $actions = @($resourceChange.change.actions)
  if ($actions.Count -ne 1 -or $actions[0] -ne "create") {
    Fail "only create is allowed; $($resourceChange.address) has actions [$($actions -join ',')]"
  }
  if ($forbiddenTypes -contains [string]$resourceChange.type) {
    Fail "forbidden resource type in plan: $($resourceChange.type)"
  }

  $matchingPatterns = @($patterns | Where-Object {
      [string]$resourceChange.address -match [string]$_.pattern
    })
  if ($matchingPatterns.Count -ne 1) {
    Fail "$($resourceChange.address) must match exactly one approved address pattern; matched $($matchingPatterns.Count)"
  }
  $matchedPattern = [string]$matchingPatterns[0].pattern
  $matchedCounts[$matchedPattern]++

  if ($resourceChange.type -eq "aws_subnet" -and $resourceChange.change.after.map_public_ip_on_launch -ne $false) {
    Fail "$($resourceChange.address) must explicitly disable public IP assignment"
  }
  if ($resourceChange.type -eq "aws_vpc_endpoint" -and $resourceChange.change.after.vpc_endpoint_type -ne "Gateway") {
    Fail "$($resourceChange.address) must be a Gateway endpoint, not interface/public connectivity"
  }
  if ($resourceChange.type -eq "aws_s3_bucket" -and $resourceChange.change.after.force_destroy -ne $false) {
    Fail "$($resourceChange.address) must have force_destroy=false"
  }
}

foreach ($patternContract in $patterns) {
  $actual = $matchedCounts[[string]$patternContract.pattern]
  if ($actual -ne [int]$patternContract.count) {
    Fail "address pattern $($patternContract.pattern) expected $($patternContract.count), found $actual"
  }
}

$expectedFromPatterns = ($patterns | Measure-Object -Property count -Sum).Sum
if ($expectedFromPatterns -ne [int]$contract.expected_active_changes) {
  Fail "manifest pattern counts sum to $expectedFromPatterns, not $($contract.expected_active_changes)"
}

Write-Output "PASS: dev reviewed plan contains exactly 62 approved create actions, with zero update/delete/replace actions."
