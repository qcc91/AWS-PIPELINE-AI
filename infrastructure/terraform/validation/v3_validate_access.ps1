param([string]$Region = "ap-southeast-2")

$ErrorActionPreference = "Stop"
$AccountId = "199476069493"
$HumanProfile = "aip-dev-human"
$ControlOutput = "s3://aip-insurance-dev-control-dev01/athena-results/v3-security/"

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
  [pscustomobject]@{ Code = $process.ExitCode; Out = $stdout; Err = $stderr }
}

function Set-Session($Credentials) {
  $env:AWS_ACCESS_KEY_ID = $Credentials.AccessKeyId
  $env:AWS_SECRET_ACCESS_KEY = $Credentials.SecretAccessKey
  $env:AWS_SESSION_TOKEN = $Credentials.SessionToken
}

function Assume-Role([string]$RoleName, [string]$SessionName, [switch]$FromHuman) {
  $arguments = @("sts", "assume-role")
  if ($FromHuman) { $arguments += @("--profile", $HumanProfile) }
  $arguments += @("--role-arn", "arn:aws:iam::${AccountId}:role/${RoleName}", "--role-session-name", $SessionName, "--query", "Credentials", "--output", "json")
  $result = Invoke-Aws $arguments
  if ($result.Code -ne 0) { throw $result.Err }
  $result.Out | ConvertFrom-Json
}

function Invoke-Athena([string]$Sql) {
  $start = Invoke-Aws @("athena", "start-query-execution", "--region", $Region, "--work-group", "insurance-dev-bi", "--query-string", $Sql, "--result-configuration", "OutputLocation=${ControlOutput}", "--query", "QueryExecutionId", "--output", "text")
  if ($start.Code -ne 0) { return [pscustomobject]@{ State = "API_DENIED"; Id = $null } }
  [pscustomobject]@{ State = "SUBMITTED"; Id = $start.Out.Trim() }
}

$human = Invoke-Aws @("sts", "get-caller-identity", "--profile", $HumanProfile, "--query", "Arn", "--output", "text")
if ($human.Code -ne 0) { throw $human.Err }
$humanData = Invoke-Aws @("s3api", "list-objects-v2", "--profile", $HumanProfile, "--region", $Region, "--bucket", "aip-insurance-dev-lakehouse-dev01", "--max-keys", "1")

$operator = Assume-Role "insurance-dev-operator-role" "v3-validation-operator" -FromHuman
Set-Session $operator
$operatorArn = (Invoke-Aws @("sts", "get-caller-identity", "--query", "Arn", "--output", "text")).Out.Trim()
$operatorData = Invoke-Aws @("s3api", "list-objects-v2", "--region", $Region, "--bucket", "aip-insurance-dev-lakehouse-dev01", "--max-keys", "1")

$tests = @()

Set-Session $operator
$terraformExecution = Assume-Role "insurance-dev-terraform-execution-role" "v3-validation-terraform"
Set-Session $terraformExecution
$trail = Invoke-Aws @("cloudtrail", "get-trail-status", "--region", $Region, "--name", "insurance-dev-management-trail", "--query", "IsLogging", "--output", "text")
$trailValidation = Invoke-Aws @("cloudtrail", "describe-trails", "--region", $Region, "--trail-name-list", "insurance-dev-management-trail", "--query", "trailList[0].LogFileValidationEnabled", "--output", "text")
$tests += [pscustomobject]@{ Name = "CloudTrail logging"; Expected = "True"; Actual = $trail.Out.Trim(); Id = $null }
$tests += [pscustomobject]@{ Name = "CloudTrail log validation"; Expected = "True"; Actual = $trailValidation.Out.Trim(); Id = $null }

Set-Session $operator
$dataEngineer = Assume-Role "insurance-dev-data-engineer-role" "v3-validation-data-engineer"
Set-Session $dataEngineer
$result = Invoke-Aws @("glue", "get-table", "--region", $Region, "--database-name", "insurance_dev_gold", "--name", "claim_daily_summary", "--query", "Table.Name", "--output", "text")
$tests += [pscustomobject]@{ Name = "DataEngineer Gold catalog"; Expected = "ALLOW"; Actual = $(if ($result.Code -eq 0) { "ALLOW" } else { "DENY" }); Id = $null }
$batch = Invoke-Aws @("stepfunctions", "list-executions", "--region", $Region, "--state-machine-arn", "arn:aws:states:ap-southeast-2:199476069493:stateMachine:insurance-dev-batch-claim-lakehouse", "--max-results", "1", "--query", "executions[0].status", "--output", "text")
$cdc = Invoke-Aws @("stepfunctions", "list-executions", "--region", $Region, "--state-machine-arn", "arn:aws:states:ap-southeast-2:199476069493:stateMachine:insurance-dev-cdc-iceberg", "--max-results", "1", "--query", "executions[0].status", "--output", "text")
$dms = Invoke-Aws @("dms", "describe-replication-tasks", "--region", $Region, "--filters", "Name=replication-task-id,Values=insurancedevcdc", "--query", "ReplicationTasks[0].Status", "--output", "text")
$tests += [pscustomobject]@{ Name = "V2 latest Batch execution"; Expected = "SUCCEEDED"; Actual = $batch.Out.Trim(); Id = $null }
$tests += [pscustomobject]@{ Name = "V2 latest CDC execution"; Expected = "SUCCEEDED"; Actual = $cdc.Out.Trim(); Id = $null }
$tests += [pscustomobject]@{ Name = "V2 DMS task"; Expected = "running/ready"; Actual = $dms.Out.Trim(); Id = $null }

Set-Session $operator
$analyst = Assume-Role "insurance-dev-analyst-role" "v3-validation-analyst"
Set-Session $analyst
$result = Invoke-Athena "SELECT count(*) FROM insurance_dev_gold.claim_daily_summary"
$tests += [pscustomobject]@{ Name = "Analyst approved Gold"; Expected = "SUCCEEDED"; Actual = $result.State; Id = $result.Id }
$result = Invoke-Athena "SELECT count(*) FROM insurance_dev_silver.customers"
$tests += [pscustomobject]@{ Name = "Analyst Silver"; Expected = "DENY"; Actual = $result.State; Id = $result.Id }
$result = Invoke-Aws @("secretsmanager", "get-secret-value", "--region", $Region, "--secret-id", "insurance-dev-cdc-postgres", "--query", "ARN", "--output", "text")
$tests += [pscustomobject]@{ Name = "Analyst secret"; Expected = "DENY"; Actual = $(if ($result.Code -ne 0) { "DENY" } else { "ALLOW" }); Id = $null }

Set-Session $operator
$mlEngineer = Assume-Role "insurance-dev-ml-engineer-role" "v3-validation-ml-engineer"
Set-Session $mlEngineer
$result = Invoke-Athena "SELECT count(*) FROM insurance_dev_gold.claim_risk_features"
$tests += [pscustomobject]@{ Name = "MLEngineer approved features"; Expected = "SUCCEEDED"; Actual = $result.State; Id = $result.Id }
$result = Invoke-Athena "SELECT count(*) FROM insurance_dev_silver.customers"
$tests += [pscustomobject]@{ Name = "MLEngineer Silver"; Expected = "DENY"; Actual = $result.State; Id = $result.Id }
$result = Invoke-Aws @("secretsmanager", "get-secret-value", "--region", $Region, "--secret-id", "insurance-dev-cdc-postgres", "--query", "ARN", "--output", "text")
$tests += [pscustomobject]@{ Name = "MLEngineer secret"; Expected = "DENY"; Actual = $(if ($result.Code -ne 0) { "DENY" } else { "ALLOW" }); Id = $null }

Set-Session $operator
$rag = Assume-Role "insurance-dev-rag-application-role" "v3-validation-rag"
Set-Session $rag
$result = Invoke-Aws @("bedrock-agent-runtime", "retrieve", "--region", $Region, "--knowledge-base-id", "AIKVWGQ7FK", "--retrieval-query", '{"text":"What guidance applies to claim handling?"}', "--retrieval-configuration", '{"vectorSearchConfiguration":{"numberOfResults":1}}', "--query", "length(retrievalResults)", "--output", "text")
$tests += [pscustomobject]@{ Name = "RAG approved retrieval"; Expected = "ALLOW"; Actual = $(if ($result.Code -eq 0) { "ALLOW" } else { "DENY" }); Id = $null }
$result = Invoke-Aws @("s3api", "list-objects-v2", "--region", $Region, "--bucket", "aip-insurance-dev-lakehouse-dev01", "--max-keys", "1")
$tests += [pscustomobject]@{ Name = "RAG lakehouse"; Expected = "DENY"; Actual = $(if ($result.Code -ne 0) { "DENY" } else { "ALLOW" }); Id = $null }

$report = [pscustomobject]@{
  HumanArn = $human.Out.Trim()
  HumanDirectData = $(if ($humanData.Code -ne 0) { "DENY" } else { "ALLOW" })
  OperatorArn = $operatorArn
  OperatorDirectData = $(if ($operatorData.Code -ne 0) { "DENY" } else { "ALLOW" })
  Tests = $tests
}

$summary = $report | ConvertTo-Json -Depth 6 -Compress
[System.IO.File]::WriteAllText((Join-Path $env:TEMP "aip-v3-access-validation.json"), $summary)
[Console]::Out.WriteLine($summary)
