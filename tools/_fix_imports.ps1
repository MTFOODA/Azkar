$projectRoot = Split-Path -Parent $PSScriptRoot
$libRoot = Join-Path $projectRoot 'lib'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$changed = 0
foreach ($file in Get-ChildItem -Recurse $libRoot -Filter *.dart) {
  $text = [System.IO.File]::ReadAllText($file.FullName)
  $directory = $file.DirectoryName
  $result = [System.Text.RegularExpressions.Regex]::Replace(
    $text,
    "(?m)(import|export)\s+'([^']+)'",
    {
      param($match)
      $kind = $match.Groups[1].Value
      $path = $match.Groups[2].Value
      if (-not $path.StartsWith('.')) { return $match.Value }
      $suffix = $path
      while ($suffix.StartsWith('../')) { $suffix = $suffix.Substring(3) }
      if ($suffix.StartsWith('./')) { $suffix = $suffix.Substring(2) }
      for ($level = 0; $level -le 8; $level++) {
        $prefix = '../' * $level
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $directory ($prefix + $suffix)))
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
          return "$kind '$prefix$suffix'"
        }
      }
      return $match.Value
    }
  )
  if ($result -ne $text) {
    [System.IO.File]::WriteAllText($file.FullName, $result, $utf8)
    $changed++
  }
}
Write-Output "Normalized imports in $changed files."
