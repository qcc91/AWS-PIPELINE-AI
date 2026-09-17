$ErrorActionPreference = "Stop"

function Invoke-Aws([string[]]$Arguments) {
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = (Get-Command aws).Source
  foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $start.UseShellExecute = $false
  $process = [Diagnostics.Process]::Start($start)
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw $stderr }
  $stdout
}

function Set-Session($Credentials) {
  $env:AWS_ACCESS_KEY_ID = $Credentials.AccessKeyId
  $env:AWS_SECRET_ACCESS_KEY = $Credentials.SecretAccessKey
  $env:AWS_SESSION_TOKEN = $Credentials.SessionToken
}

$evidence = Get-Content -LiteralPath (Join-Path $env:TEMP "aip-v3-access-validation.json") -Raw | ConvertFrom-Json
$operator = Invoke-Aws @("sts", "assume-role", "--profile", "aip-dev-human", "--role-arn", "arn:aws:iam::199476069493:role/insurance-dev-operator-role", "--role-session-name", "v3-athena-status-operator", "--query", "Credentials", "--output", "json") | ConvertFrom-Json
Set-Session $operator
$engineer = Invoke-Aws @("sts", "assume-role", "--role-arn", "arn:aws:iam::199476069493:role/insurance-dev-data-engineer-role", "--role-session-name", "v3-athena-status", "--query", "Credentials", "--output", "json") | ConvertFrom-Json
Set-Session $engineer

$results = foreach ($test in $evidence.Tests | Where-Object Id) {
  $status = Invoke-Aws @("athena", "get-query-execution", "--region", "ap-southeast-2", "--query-execution-id", $test.Id, "--query", "QueryExecution.Status.[State,StateChangeReason]", "--output", "json") | ConvertFrom-Json
  [pscustomobject]@{
    Name = $test.Name
    Id = $test.Id
    State = $status[0]
    Reason = $status[1]
  }
}

[Console]::Out.WriteLine(($results | ConvertTo-Json -Depth 4 -Compress))
