$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'dev_config.ps1')

try {
    $null = Assert-AzkarSupabaseDevConfig -ProjectRoot $projectRoot
    Write-Output 'Supabase development configuration verified (values redacted).'
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
