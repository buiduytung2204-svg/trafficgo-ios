# Generate a local-only access token without printing it or replacing existing config.
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $workspaceRoot 'backend\.env'
if (Test-Path -LiteralPath $envPath) {
    Write-Output 'backend/.env already exists; left unchanged.'
    exit 0
}
$randomBytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($randomBytes)
$rng.Dispose()
$localToken = [Convert]::ToBase64String($randomBytes)
$template = [System.IO.File]::ReadAllText((Join-Path $workspaceRoot 'backend\.env.example'))
$template = $template.Replace('APP_ACCESS_TOKEN=', "APP_ACCESS_TOKEN=$localToken")
[System.IO.File]::WriteAllText($envPath, $template, (New-Object System.Text.UTF8Encoding($false)))
Write-Output 'Created backend/.env. Set TomTom key, database and CORS locally; copy app token into TrafficGo Settings. Do not send secrets in chat.'
