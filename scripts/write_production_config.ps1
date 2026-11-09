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

$supabaseUri = $null
$validSupabaseUrl = [Uri]::TryCreate(
    $env:AZKAR_SUPABASE_URL,
    [UriKind]::Absolute,
    [ref]$supabaseUri
) -and $supabaseUri.Scheme -eq 'https' -and
    $supabaseUri.Host -eq 'akublcdzlmwyyelwtzrb.supabase.co' -and
    [string]::IsNullOrEmpty($supabaseUri.UserInfo) -and
    [string]::IsNullOrEmpty($supabaseUri.Query) -and
    [string]::IsNullOrEmpty($supabaseUri.Fragment) -and
    ($supabaseUri.AbsolutePath -eq '/' -or
        [string]::IsNullOrEmpty($supabaseUri.AbsolutePath))
if (-not $validSupabaseUrl) {
    throw 'AZKAR_SUPABASE_URL must target the approved Supabase project over HTTPS.'
}

if ($env:AZKAR_AUTH_SCHEMA_VERIFIED -cnotin @('true', 'false')) {
    throw 'AZKAR_AUTH_SCHEMA_VERIFIED must be explicitly true or false. Use false until production provisioning and RLS verification is complete.'
}
$authSchemaVerified = $env:AZKAR_AUTH_SCHEMA_VERIFIED -ceq 'true'

$apkDownloadUrl = ([string]$env:AZKAR_ANDROID_APK_URL).Trim()
if ($apkDownloadUrl.Length -eq 0) {
    $apkDownloadUrl = 'https://github.com/MTFOODA/Azkar/releases/download/v1.0.0/AZKAR-v1.0.0-android.apk'
}
if ($apkDownloadUrl.Length -gt 0) {
    $apkUri = $null
    $validApkDownloadUrl = [Uri]::TryCreate(
        $apkDownloadUrl,
        [UriKind]::Absolute,
        [ref]$apkUri
    ) -and $apkUri.Scheme -eq 'https' -and
        -not [string]::IsNullOrWhiteSpace($apkUri.Host) -and
        $apkUri.Host -notmatch '^(localhost|(?:[^.]+\.)+localhost|127(?:\.\d{1,3}){3}|0\.0\.0\.0|\[?::1\]?)$' -and
        [string]::IsNullOrEmpty($apkUri.UserInfo) -and
        $apkUri.AbsolutePath.EndsWith('.apk', [StringComparison]::OrdinalIgnoreCase)
    if (-not $validApkDownloadUrl) {
        throw 'AZKAR_ANDROID_APK_URL must be a public HTTPS URL ending in .apk, or left empty until a signed release is hosted.'
    }
}

$config = [ordered]@{
    SUPABASE_URL = $env:AZKAR_SUPABASE_URL
    SUPABASE_ANON_KEY = $env:AZKAR_SUPABASE_PUBLISHABLE_KEY
    AZKAR_DEMO_MODE = $false
    AZKAR_AUTH_SCHEMA_VERIFIED = $authSchemaVerified
    PUBLIC_BASE_URL = 'https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev'
    AZKAR_ANDROID_APK_URL = $apkDownloadUrl
}

$json = ConvertTo-Json -InputObject $config
[IO.File]::WriteAllText(
    $configPath,
    $json,
    (New-Object Text.UTF8Encoding($false))
)

Write-Output 'Production build configuration written locally; values were not logged.'
if (-not $authSchemaVerified) {
    Write-Output 'Registration remains gated because AZKAR_AUTH_SCHEMA_VERIFIED is false.'
}
