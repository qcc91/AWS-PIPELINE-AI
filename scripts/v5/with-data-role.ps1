param([Parameter(Mandatory = $true)][scriptblock]$Action)

# Keep temporary role credentials in this process only, and restore its caller.
$ErrorActionPreference = 'Stop'
$names = @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN', 'AWS_PROFILE')
$prior = @{}
foreach ($name in $names) { $prior[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $operator = aws configure export-credentials --profile aip-dev-operator --format process | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $operator.SessionToken) { throw 'Operator authentication failed' }
    $env:AWS_ACCESS_KEY_ID = $operator.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $operator.SecretAccessKey
    $env:AWS_SESSION_TOKEN = $operator.SessionToken
    Remove-Item Env:AWS_PROFILE -ErrorAction SilentlyContinue
    $session = aws sts assume-role --role-arn arn:aws:iam::199476069493:role/insurance-dev-data-engineer-role --role-session-name v5-data-operations --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $session.AssumedRoleUser.Arn -notlike 'arn:aws:sts::199476069493:assumed-role/insurance-dev-data-engineer-role/*') { throw 'DataEngineer authentication failed' }
    $env:AWS_ACCESS_KEY_ID = $session.Credentials.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $session.Credentials.SecretAccessKey
    $env:AWS_SESSION_TOKEN = $session.Credentials.SessionToken
    & $Action
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $prior[$name], 'Process') }
    Remove-Variable operator,session,prior -ErrorAction SilentlyContinue
}
