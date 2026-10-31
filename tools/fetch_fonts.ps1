# Fetches the 10 approved Arabic font families from the official google/fonts
# repository into assets/fonts/<family>/ and copies each SIL Open Font License
# into licenses/fonts/.
#
# Every one of these families is distributed under the SIL Open Font License 1.1,
# which allows bundling and redistribution inside an application. The license
# text is downloaded alongside the binaries so the obligation is documented in
# the repository.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools/fetch_fonts.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$fontRoot = Join-Path $root 'assets\fonts'
$licenseRoot = Join-Path $root 'licenses\fonts'
New-Item -ItemType Directory -Force -Path $fontRoot, $licenseRoot | Out-Null

$base = 'https://raw.githubusercontent.com/google/fonts/main'
$log = New-Object System.Collections.ArrayList

# family folder, file name, google/fonts directory
$fonts = @(
  @('amiri', 'Amiri-Regular.ttf', 'ofl/amiri'),
  @('amiri', 'Amiri-Bold.ttf', 'ofl/amiri'),
  @('cairo', 'Cairo-VariableFont.ttf', 'ofl/cairo'),
  @('tajawal', 'Tajawal-Regular.ttf', 'ofl/tajawal'),
  @('tajawal', 'Tajawal-Medium.ttf', 'ofl/tajawal'),
  @('tajawal', 'Tajawal-Bold.ttf', 'ofl/tajawal'),
  @('noto_naskh_arabic', 'NotoNaskhArabic-VariableFont.ttf', 'ofl/notonaskharabic'),
  @('noto_kufi_arabic', 'NotoKufiArabic-VariableFont.ttf', 'ofl/notokufiarabic'),
  @('scheherazade_new', 'ScheherazadeNew-Regular.ttf', 'ofl/scheherazadenew'),
  @('scheherazade_new', 'ScheherazadeNew-Bold.ttf', 'ofl/scheherazadenew'),
  @('reem_kufi', 'ReemKufi-VariableFont.ttf', 'ofl/reemkufi'),
  @('lateef', 'Lateef-Regular.ttf', 'ofl/lateef'),
  @('lateef', 'Lateef-Bold.ttf', 'ofl/lateef'),
  @('aref_ruqaa', 'ArefRuqaa-Regular.ttf', 'ofl/arefruqaa'),
  @('aref_ruqaa', 'ArefRuqaa-Bold.ttf', 'ofl/arefruqaa'),
  @('ibm_plex_sans_arabic', 'IBMPlexSansArabic-Regular.ttf', 'ofl/ibmplexsansarabic'),
  @('ibm_plex_sans_arabic', 'IBMPlexSansArabic-Medium.ttf', 'ofl/ibmplexsansarabic'),
  @('ibm_plex_sans_arabic', 'IBMPlexSansArabic-Bold.ttf', 'ofl/ibmplexsansarabic')
)

# Variable font upstream file names (the bracketed axis notation is URL encoded).
$variableSource = @{
  'ofl/cairo'            = 'ofl/cairo/Cairo%5Bslnt%2Cwght%5D.ttf'
  'ofl/notonaskharabic'  = 'ofl/notonaskharabic/NotoNaskhArabic%5Bwght%5D.ttf'
  'ofl/notokufiarabic'   = 'ofl/notokufiarabic/NotoKufiArabic%5Bwght%5D.ttf'
  'ofl/reemkufi'         = 'ofl/reemkufi/ReemKufi%5Bwght%5D.ttf'
}

foreach ($f in $fonts) {
  $folder = $f[0]; $file = $f[1]; $dir = $f[2]
  $dest = Join-Path $fontRoot (Join-Path $folder $file)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
  $remote = if ($file -like '*VariableFont*') { $variableSource[$dir] } else { "$dir/$file" }
  if (-not $remote) { [void]$log.Add("SKIP  $folder/$file (no source mapping)"); continue }
  try {
    Invoke-WebRequest -Uri "$base/$remote" -OutFile $dest -UseBasicParsing -TimeoutSec 120
    $size = (Get-Item $dest).Length
    [void]$log.Add("OK    $folder/$file  $([math]::Round($size/1024))KB")
  } catch {
    [void]$log.Add("FAIL  $folder/$file  $($_.Exception.Message)")
  }
}

# One OFL license file per family folder.
foreach ($dir in ($fonts | ForEach-Object { $_[2] } | Select-Object -Unique)) {
  $family = Split-Path $dir -Leaf
  $dest = Join-Path $licenseRoot "$family-OFL.txt"
  try {
    Invoke-WebRequest -Uri "$base/$dir/OFL.txt" -OutFile $dest -UseBasicParsing -TimeoutSec 60
    [void]$log.Add("OK    license $family-OFL.txt")
  } catch {
    [void]$log.Add("FAIL  license $family  $($_.Exception.Message)")
  }
}

$log | Out-File -FilePath (Join-Path $root '_fonts_log.txt') -Encoding utf8
$log | ForEach-Object { Write-Output $_ }
