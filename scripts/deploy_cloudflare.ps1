[CmdletBinding()]
param(
    [string]$ProjectName = $env:CLOUDFLARE_PAGES_PROJECT_NAME
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildDirectory = Join-Path $projectRoot 'build\web'

if ([string]::IsNullOrWhiteSpace($ProjectName) -or
    $ProjectName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') {
    throw 'Set CLOUDFLARE_PAGES_PROJECT_NAME or pass -ProjectName using the existing Pages project name.'
}
if (-not (Test-Path -LiteralPath (Join-Path $buildDirectory 'index.html') -PathType Leaf)) {
    throw 'Production Web build is missing. Run scripts/build_web_production.ps1 first.'
}
if (-not (Test-Path -LiteralPath (Join-Path $buildDirectory 'flutter_bootstrap.js') -PathType Leaf)) {
    throw 'Production Web build is incomplete: flutter_bootstrap.js is missing.'
}
if (Test-Path -LiteralPath (Join-Path $buildDirectory '404.html')) {
    throw 'A top-level 404.html disables the Cloudflare Pages SPA fallback; review the production build.'
}

$wrangler = Get-Command wrangler -ErrorAction SilentlyContinue
if (-not $wrangler) {
    throw 'Wrangler was not found on PATH. Install it with npm install --global wrangler, then reopen PowerShell.'
}

Write-Output ('Target Pages project: ' + $ProjectName)
Write-Output 'Target environment: production'
Write-Output 'The selected project must already exist and use Direct Upload.'
Write-Output 'Checking Cloudflare authentication...'
& wrangler whoami
if ($LASTEXITCODE -ne 0) {
    throw 'Wrangler is not authenticated. Run wrangler login and retry.'
}

$projectListOutput = & wrangler pages project list --json 2>&1
if ($LASTEXITCODE -ne 0) {
    $projectListOutput | ForEach-Object { Write-Output $_ }
    throw 'Could not list Pages projects. Verify Wrangler account access and project setup.'
}
try {
    $projectList = ($projectListOutput -join "`n") | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw 'Wrangler returned an unreadable Pages project list.'
}

$projects = if ($projectList -is [Array]) {
    $projectList
}
elseif ($projectList.result) {
    @($projectList.result)
}
else {
    @($projectList)
}
$projectExists = @($projects | Where-Object {
    $_.name -eq $ProjectName -or $_.project_name -eq $ProjectName
}).Count -gt 0
if (-not $projectExists) {
    throw 'The named Pages project was not found in the authenticated account. Create it manually after choosing a deployment mode; this script never creates projects.'
}

$confirmation = Read-Host "Type DEPLOY PRODUCTION to upload build/web to '$ProjectName'"
if ($confirmation -cne 'DEPLOY PRODUCTION') {
    Write-Output 'Deployment cancelled. No files were uploaded.'
    exit 0
}

$deployOutput = & wrangler pages deploy $buildDirectory --project-name $ProjectName 2>&1
$deployExitCode = $LASTEXITCODE
$deployOutput | ForEach-Object { Write-Output $_ }
if ($deployExitCode -ne 0) {
    throw "Cloudflare Pages deployment failed with exit code $deployExitCode."
}

$deployedUrl = [regex]::Match(
    ($deployOutput -join "`n"),
    'https://[a-zA-Z0-9.-]+\.pages\.dev'
).Value
if ($deployedUrl) {
    Write-Output ('Deployment URL: ' + $deployedUrl)
}
else {
    Write-Output 'Deployment succeeded. Find the production URL under Workers & Pages > the Pages project > Deployments.'
}
