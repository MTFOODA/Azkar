[CmdletBinding()]
param(
    [string]$DeviceId = 'edge'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $projectRoot
. (Join-Path $PSScriptRoot 'dev_config.ps1')

try {
    $null = Assert-AzkarSupabaseDevConfig -ProjectRoot $projectRoot
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

$deviceOutput = & flutter devices --machine
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine('Flutter could not enumerate connected devices.')
    exit $LASTEXITCODE
}

try {
    $deviceDocument = ($deviceOutput -join "`n") | ConvertFrom-Json -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine('Flutter returned an unreadable device list.')
    exit 1
}

$webDevices = @($deviceDocument | Where-Object {
    $_.isSupported -and $_.targetPlatform -like 'web-*'
})
$selectedDevice = $webDevices | Where-Object { $_.id -eq $DeviceId } | Select-Object -First 1
if ($null -eq $selectedDevice) {
    $available = @($webDevices | ForEach-Object { $_.id })
    [Console]::Error.WriteLine(
        ('Web device "{0}" is unavailable. Available Web devices: {1}' -f $DeviceId, ($available -join ', '))
    )
    exit 1
}

Write-Output ('Starting AZKAR with Supabase development configuration on {0}.' -f $selectedDevice.id)
& flutter run -d $selectedDevice.id --dart-define-from-file=config/dev.json
exit $LASTEXITCODE
