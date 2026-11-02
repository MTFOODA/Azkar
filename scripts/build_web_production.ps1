[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath = Join-Path $projectRoot 'config\production.json'

function Test-PublishableSupabaseKey {
    param([string]$Key)

    if ($Key.StartsWith('sb_publishable_', [StringComparison]::Ordinal) -and
        $Key.Length -gt 'sb_publishable_'.Length) {
        return $true
    }

    $segments = $Key.Split('.')
    if ($segments.Length -ne 3) {
        return $false
    }

    try {
        $payload = $segments[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }
        $claims = [Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($payload)
        ) | ConvertFrom-Json -ErrorAction Stop
        return $claims.role -eq 'anon'
    }
    catch {
        return $false
    }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found on PATH. Install Flutter and reopen PowerShell.'
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'Missing config/production.json. Copy config/production.example.json, fill in the approved production settings, and retry.'
}

try {
    $config = Get-Content -Raw -LiteralPath $configPath |
        ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw 'config/production.json is not valid JSON. Configuration values are not displayed.'
}

$supabaseUri = $null
$publicUri = $null
$validSupabaseUrl = [Uri]::TryCreate(
    [string]$config.SUPABASE_URL,
    [UriKind]::Absolute,
    [ref]$supabaseUri
) -and $supabaseUri.Scheme -eq 'https' -and
    $supabaseUri.Host -eq 'akublcdzlmwyyelwtzrb.supabase.co' -and
    [string]::IsNullOrEmpty($supabaseUri.UserInfo) -and
    [string]::IsNullOrEmpty($supabaseUri.Query) -and
    [string]::IsNullOrEmpty($supabaseUri.Fragment) -and
    ($supabaseUri.AbsolutePath -eq '/' -or
        [string]::IsNullOrEmpty($supabaseUri.AbsolutePath))
$validPublicUrl = [Uri]::TryCreate(
    [string]$config.PUBLIC_BASE_URL,
    [UriKind]::Absolute,
    [ref]$publicUri
) -and $publicUri.Scheme -eq 'https' -and
    -not [string]::IsNullOrWhiteSpace($publicUri.Host) -and
    [string]::IsNullOrEmpty($publicUri.UserInfo) -and
    [string]::IsNullOrEmpty($publicUri.Query) -and
    [string]::IsNullOrEmpty($publicUri.Fragment) -and
    ($publicUri.AbsolutePath -eq '/' -or
        [string]::IsNullOrEmpty($publicUri.AbsolutePath)) -and
    $publicUri.GetLeftPart([UriPartial]::Authority) -eq
        'https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev'

$problems = New-Object System.Collections.Generic.List[string]
if (-not $validSupabaseUrl) {
    $problems.Add('SUPABASE_URL must target the approved Supabase project over HTTPS.')
}
if (-not (Test-PublishableSupabaseKey ([string]$config.SUPABASE_ANON_KEY))) {
    $problems.Add('SUPABASE_ANON_KEY must be an anon/publishable key; secret and service-role keys are not accepted.')
}
if ([string]$config.AZKAR_DEMO_MODE -ne 'false') {
    $problems.Add('AZKAR_DEMO_MODE must be false.')
}
if ([string]$config.AZKAR_AUTH_SCHEMA_VERIFIED -notin @('true', 'false')) {
    $problems.Add('AZKAR_AUTH_SCHEMA_VERIFIED must be explicitly true or false.')
}
if (-not $validPublicUrl) {
    $problems.Add('PUBLIC_BASE_URL must be https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev without a path, query, or fragment.')
}
if ($problems.Count -gt 0) {
    throw ('Production configuration is not ready: ' + ($problems -join ' '))
}

Set-Location $projectRoot
Write-Output 'Building AZKAR Web release with validated production configuration (values redacted).'
if (-not $config.AZKAR_AUTH_SCHEMA_VERIFIED) {
    Write-Output 'Registration remains gated; no provisioning verification is being asserted.'
}
& flutter build web --release --base-href / --dart-define-from-file=config/production.json
if ($LASTEXITCODE -ne 0) {
    throw "Flutter Web release build failed with exit code $LASTEXITCODE."
}

$buildDirectory = Join-Path $projectRoot 'build\web'
$indexPath = Join-Path $buildDirectory 'index.html'
$bootstrapPath = Join-Path $buildDirectory 'flutter_bootstrap.js'
$applicationPath = Join-Path $buildDirectory 'main.dart.js'
$manifestPath = Join-Path $buildDirectory 'manifest.json'
$iconPath = Join-Path $buildDirectory 'icons\Icon-512.png'
$assetManifestPath = Join-Path $buildDirectory 'assets\AssetManifest.bin.json'
$arabicFontPath = Join-Path $buildDirectory 'assets\assets\fonts\amiri\Amiri-Regular.ttf'
if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw 'The build completed without build/web/index.html.'
}
if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
    throw 'The build is missing build/web/flutter_bootstrap.js.'
}
foreach ($requiredPath in @(
    $applicationPath,
    $manifestPath,
    $iconPath,
    $assetManifestPath,
    $arabicFontPath
)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw 'The Flutter Web output is incomplete: compiled application, manifest, icon, asset manifest, or Arabic font is missing.'
    }
}

$indexHtml = [IO.File]::ReadAllText($indexPath)
if ($indexHtml -notmatch '<base href="/">') {
    throw 'The built index.html is not configured for deployment at the site root.'
}
if ($indexHtml -notmatch '__AZKAR_PUBLIC_BASE_URL__') {
    throw 'The public metadata URL placeholder is missing from the built index.html.'
}

$publicBaseUrl = $publicUri.GetLeftPart([UriPartial]::Authority)
$indexHtml = $indexHtml.Replace('__AZKAR_PUBLIC_BASE_URL__', $publicBaseUrl)
[IO.File]::WriteAllText(
    $indexPath,
    $indexHtml,
    (New-Object Text.UTF8Encoding($false))
)
if ($indexHtml.Contains('__AZKAR_PUBLIC_BASE_URL__')) {
    throw 'The public metadata URL was not fully generated.'
}

$compiledApplication = [IO.File]::ReadAllText($applicationPath)
if (-not $compiledApplication.Contains($publicBaseUrl)) {
    throw 'The compiled Flutter application does not contain the configured public site origin.'
}
if ($indexHtml -match 'pages\.dev|localhost|127\.0\.0\.1') {
    throw 'The generated Web metadata contains a non-production hostname.'
}

Write-Output 'Validated compiled Flutter application, bootstrap, manifest, icon, asset manifest, Arabic font, and production URL.'
Write-Output 'Cloudflare Workers Static Assets will apply SPA fallback using wrangler.jsonc.'
Write-Output ('Production Worker assets: ' + $buildDirectory)
