[CmdletBinding()]
param(
    [string]$DeviceId
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

$androidDevices = @($deviceDocument | Where-Object {
    $_.isSupported -and $_.targetPlatform -like 'android-*'
})
if ($androidDevices.Count -eq 0) {
    [Console]::Error.WriteLine('No supported Android device is connected. Start an emulator or connect a phone, then retry.')
    exit 1
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    if ($androidDevices.Count -eq 1) {
        $DeviceId = $androidDevices[0].id
    }
    else {
        Write-Output 'Select an Android device:'
        for ($index = 0; $index -lt $androidDevices.Count; $index++) {
            Write-Output ('{0}. {1} ({2})' -f ($index + 1), $androidDevices[$index].name, $androidDevices[$index].id)
        }
        $selection = Read-Host 'Enter a number or device ID'
        $selectedIndex = -1
        if ([int]::TryParse($selection, [ref]$selectedIndex) -and
            $selectedIndex -ge 1 -and
            $selectedIndex -le $androidDevices.Count) {
            $DeviceId = $androidDevices[$selectedIndex - 1].id
        }
        else {
            $DeviceId = $selection
        }
    }
}

$selectedDevice = $androidDevices | Where-Object { $_.id -eq $DeviceId } | Select-Object -First 1
if ($null -eq $selectedDevice) {
    [Console]::Error.WriteLine('The selected device is not among Flutter’s supported connected Android devices.')
    exit 1
}

Write-Output ('Starting AZKAR with Supabase development configuration on {0}.' -f $selectedDevice.id)
& flutter run -d $selectedDevice.id --dart-define-from-file=config/dev.json
exit $LASTEXITCODE
