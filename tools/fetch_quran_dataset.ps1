# Downloads the complete, verified Quranic text (Tanzil Uthmani edition, served
# by the Al Quran Cloud API) and writes it to assets/data/quran_uthmani.json.
#
# This is the authoritative dataset used by the admin Quran editor to validate
# every verse before publication. Quranic text is NEVER generated or corrected
# by the application: administrators either paste text that matches this dataset
# exactly (after diacritic-aware normalisation) or publication is blocked.
#
# Source: https://api.alquran.cloud  ->  edition "quran-uthmani" (Tanzil Uthmani)
# Tanzil Quran Text is made available under the Tanzil license:
#   https://tanzil.net/docs/quran_terms  (verbatim, no modification).
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools/fetch_quran_dataset.ps1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
$outFile = Join-Path $root 'assets\data\quran_uthmani.json'
$tmpRaw = Join-Path $env:TEMP 'azkar_quran_uthmani_raw.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outFile) | Out-Null

$url = 'https://api.alquran.cloud/v1/quran/quran-uthmani'
Write-Output "Fetching $url"

# IMPORTANT: download raw bytes and decode them explicitly as UTF-8.
# Windows PowerShell 5.1 decodes Invoke-WebRequest.Content as ISO-8859-1 when the
# response charset is missing, which corrupts Arabic text (double encoding).
Invoke-WebRequest -Uri $url -OutFile $tmpRaw -UseBasicParsing -TimeoutSec 300

$bytes = [System.IO.File]::ReadAllBytes($tmpRaw)
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$text = $utf8.GetString($bytes)
# Strip a UTF-8 BOM that may have been decoded into U+FEFF.
$text = $text.TrimStart([char]0xFEFF, ' ', "`r", "`n", "`t")

$payload = $text | ConvertFrom-Json
if ($payload.status -ne 'OK') { throw "Unexpected API status: $($payload.status)" }

$surahs = New-Object System.Collections.ArrayList
foreach ($surah in $payload.data.surahs) {
  $ayahs = New-Object System.Collections.ArrayList
  foreach ($ayah in $surah.ayahs) {
    $ayahText = ([string]$ayah.text).Trim([char]0xFEFF).TrimEnd([char]0x20)
    [void]$ayahs.Add([ordered]@{ n = [int]$ayah.numberInSurah; text = $ayahText })
  }
  [void]$surahs.Add([ordered]@{
    number      = [int]$surah.number
    name        = [string]$surah.name
    englishName = [string]$surah.englishName
    ayahCount   = $ayahs.Count
    ayahs       = $ayahs
  })
}

if ($surahs.Count -ne 114) { throw "Expected 114 surahs, received $($surahs.Count)" }
$totalAyahs = ($surahs | ForEach-Object { $_.ayahCount } | Measure-Object -Sum).Sum
if ($totalAyahs -ne 6236) { throw "Expected 6236 ayahs, received $totalAyahs" }

$document = [ordered]@{
  dataset     = 'Tanzil Uthmani Quran text'
  edition     = 'quran-uthmani'
  provider    = 'Al Quran Cloud (https://api.alquran.cloud)'
  sourceUrl   = $url
  license     = 'Tanzil Quran Text - https://tanzil.net/docs/quran_terms'
  retrievedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
  surahCount  = $surahs.Count
  ayahCount   = $totalAyahs
  surahs      = $surahs
}

$json = $document | ConvertTo-Json -Depth 8 -Compress
[System.IO.File]::WriteAllText($outFile, $json, (New-Object System.Text.UTF8Encoding($false)))
$size = [math]::Round((Get-Item $outFile).Length / 1024)

# Post-write integrity check: the first surah name must start with U+0633 (س)
# and no C0/C1 control characters may remain in the text.
$check = $json | ConvertFrom-Json
$firstChar = [int]($check.surahs[0].name[0])
$controlCount = 0
foreach ($s in $check.surahs) {
  foreach ($a in $s.ayahs) {
    foreach ($ch in $a.text.ToCharArray()) {
      $c = [int]$ch
      if (($c -lt 0x20) -or (($c -ge 0x7F) -and ($c -le 0x9F))) { $controlCount++ }
    }
  }
}

Write-Output "Wrote $outFile ($size KB) - $($surahs.Count) surahs, $totalAyahs ayahs"
Write-Output "Integrity: firstSurahChar=U+$($firstChar.ToString('X4')) controlChars=$controlCount"
if ($firstChar -ne 0x0633) { throw 'Integrity check failed: Arabic text is not valid UTF-8.' }
if ($controlCount -ne 0) { throw 'Integrity check failed: control characters found in Quran text.' }

