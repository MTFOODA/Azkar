[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath = Join-Path $projectRoot 'config\production.json'

foreach ($name in @('AZKAR_SUPABASE_URL', 'AZKAR_SUPABASE_PUBLISHABLE_KEY')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "The required production environment value '$name' is missing."
    }
}

if ($env:AZKAR_AUTH_SCHEMA_VERIFIED -cne 'true') {
    throw 'AZKAR_AUTH_SCHEMA_VERIFIED must be true only after production schema, provisioning, and RLS verification.'
}

$config = [ordered]@{
    SUPABASE_URL = $env:AZKAR_SUPABASE_URL
    SUPABASE_ANON_KEY = $env:AZKAR_SUPABASE_PUBLISHABLE_KEY
    AZKAR_DEMO_MODE = $false
    AZKAR_AUTH_SCHEMA_VERIFIED = $true
    PUBLIC_BASE_URL = 'https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev'
}

$json = ConvertTo-Json -InputObject $config
[IO.File]::WriteAllText(
    $configPath,
    $json,
    (New-Object Text.UTF8Encoding($false))
)

Write-Output 'Production build configuration written locally; values were not logged.'
