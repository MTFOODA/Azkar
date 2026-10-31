$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$full = Join-Path $root 'assets\data\quran_uthmani.json'
$idx = Join-Path $root 'assets\data\quran_index.json'
$report = Join-Path $root '_quran_check.txt'
$lines = New-Object System.Collections.ArrayList

$fullText = [System.IO.File]::ReadAllText($full)
$idxText = [System.IO.File]::ReadAllText($idx)

[void]$lines.Add("full bytes=" + (Get-Item $full).Length + " chars=" + $fullText.Length)
[void]$lines.Add("full contains backslash-u escapes: " + $fullText.Contains('\u'))
[void]$lines.Add("index chars=" + $idxText.Length)
[void]$lines.Add("index contains backslash-u escapes: " + $idxText.Contains('\u'))

$doc = $fullText | ConvertFrom-Json
$idxDoc = $idxText | ConvertFrom-Json
[void]$lines.Add("surahs=" + $doc.surahs.Count + " ayahs=" + $doc.ayahCount + " indexCount=" + $idxDoc.Count)

$s1 = $doc.surahs[0]
[void]$lines.Add("s1 names: " + $s1.name + " | " + $s1.englishName + " | ayahCount=" + $s1.ayahCount)
$nameCodes = ($s1.name.ToCharArray() | ForEach-Object { 'U+' + ([int]$_).ToString('X4') }) -join ' '
[void]$lines.Add("s1 name codepoints: " + $nameCodes)

$a1 = $s1.ayahs[0]
[void]$lines.Add("s1a1 text: " + $a1.text)
[void]$lines.Add("s1a1 length=" + $a1.text.Length + " contains U+0085=" + $a1.text.Contains([char]0x0085) + " contains U+00A0=" + $a1.text.Contains([char]0x00A0))

# Scan the whole dataset for suspicious control characters.
$bad = New-Object System.Collections.ArrayList
foreach ($s in $doc.surahs) {
  foreach ($a in $s.ayahs) {
    foreach ($ch in $a.text.ToCharArray()) {
      $c = [int]$ch
      if ($c -lt 0x20 -or ($c -ge 0x7F -and $c -le 0x9F)) { [void]$bad.Add("s$($s.number):$($a.n) U+$($c.ToString('X4'))") }
    }
  }
}
[void]$lines.Add("suspicious control chars: " + $bad.Count)
if ($bad.Count -gt 0) { [void]$lines.Add(($bad | Select-Object -First 10) -join '; ') }

$lines | Out-File -FilePath $report -Encoding utf8
