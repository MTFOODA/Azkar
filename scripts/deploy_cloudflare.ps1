[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildDirectory = Join-Path $projectRoot 'build\web'
$configPath = Join-Path $projectRoot 'wrangler.jsonc'
$buildScriptPath = Join-Path $PSScriptRoot 'build_web_production.ps1'
$indexPath = Join-Path $buildDirectory 'index.html'
$bootstrapPath = Join-Path $buildDirectory 'flutter_bootstrap.js'
$applicationPath = Join-Path $buildDirectory 'main.dart.js'

foreach ($requiredPath in @($configPath, $buildScriptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw 'The Wrangler configuration and production build script are required.'
    }
}

$npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
if (-not $npx) {
    throw 'Node.js/npm was not found on PATH. Install Node.js LTS and reopen PowerShell.'
}

Set-Location $projectRoot
& $buildScriptPath
foreach ($requiredPath in @($indexPath, $bootstrapPath, $applicationPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw 'The production Flutter Web output is incomplete; no Cloudflare deployment was attempted.'
    }
}

$wranglerArgs = @('--yes', 'wrangler@4.156.0')

Write-Output 'Target Worker: azkar-sadaqa'
Write-Output 'Production URL: https://azkar-sadaqa.mohamed-fooda-mtf.workers.dev'
Write-Output 'Checking Cloudflare authentication...'
& $npx.Source @wranglerArgs whoami
if ($LASTEXITCODE -ne 0) {
    throw 'Wrangler authentication or account access check failed.'
}

Write-Output 'Validating the Worker deployment without uploading files...'
& $npx.Source @wranglerArgs deploy --config wrangler.jsonc --dry-run
if ($LASTEXITCODE -ne 0) {
    throw 'Wrangler dry-run validation failed; no production deployment was attempted.'
}

$confirmation = Read-Host "Type DEPLOY PRODUCTION to update the existing Worker 'azkar-sadaqa'"
if ($confirmation -cne 'DEPLOY PRODUCTION') {
    Write-Output 'Deployment cancelled. No files were uploaded.'
    exit 0
}

& $npx.Source @wranglerArgs deploy --config wrangler.jsonc
if ($LASTEXITCODE -ne 0) {
    throw 'Cloudflare Worker deployment failed.'
}

Write-Output 'Cloudflare Workers Static Assets deployment completed.'
