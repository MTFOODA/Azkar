$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'dev_config.ps1')

try {
    $configPath = Assert-AzkarSupabaseDevConfig -ProjectRoot $projectRoot
    $projectHost = ([Uri](Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json).SUPABASE_URL).Host
    Write-Output ('Supabase development configuration verified for project host {0} (keys redacted).' -f $projectHost)
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
