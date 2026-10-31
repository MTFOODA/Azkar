# Derives assets/data/quran_index.json (surah metadata only) from the full
# verified dataset so the surah picker never has to download the full text.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_quran_index.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'assets\data\quran_uthmani.json'
$target = Join-Path $root 'assets\data\quran_index.json'

if (-not (Test-Path $source)) { throw "Missing $source - run tools/fetch_quran_dataset.ps1 first." }

$doc = Get-Content -Path $source -Raw -Encoding UTF8 | ConvertFrom-Json
$index = New-Object System.Collections.ArrayList
foreach ($s in $doc.surahs) {
  [void]$index.Add([ordered]@{
    number      = [int]$s.number
    name        = [string]$s.name
    englishName = [string]$s.englishName
    ayahCount   = [int]$s.ayahCount
  })
}
$json = $index | ConvertTo-Json -Depth 4 -Compress
[System.IO.File]::WriteAllText($target, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Wrote $target ($($index.Count) surahs)"

# Extract the homepage Bismillah from the verified dataset rather than
# hard-coding sacred text in Dart source. Kept as a tiny, lazily loaded asset.
$bismillah = $doc.surahs[0].ayahs[0].text
$bismillahPath = Join-Path $root 'assets\data\bismillah.txt'
[System.IO.File]::WriteAllText($bismillahPath, $bismillah, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Wrote $bismillahPath"
