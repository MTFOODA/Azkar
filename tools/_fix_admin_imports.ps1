$projectRoot = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -Recurse (Join-Path $projectRoot 'lib\features\admin') -Filter *.dart
foreach ($file in $files) {
  $text = [System.IO.File]::ReadAllText($file.FullName)
  $text = $text.Replace("'../../../core/", "'../../../../core/")
  $text = $text.Replace("'../../content/", "'../../../content/")
  $text = $text.Replace("'../../home/", "'../../../home/")
  $text = $text.Replace("'../../quran/", "'../../../quran/")

  $relative = $file.FullName.Replace($projectRoot + '\', '')
  if ($relative -like 'lib\features\admin\content_management\presentation\*') {
    $text = $text.Replace("'../content_management/providers/", "'../providers/")
  } else {
    $text = $text.Replace("'../content_management/providers/", "'../../content_management/providers/")
  }
  if ($relative -like 'lib\features\admin\dashboard\presentation\*') {
    # dashboard_page needs the sibling feature, while admin_shell has no such import
    $text = $text.Replace("'../content_management/providers/", "'../../content_management/providers/")
  }
  if ($relative -notlike 'lib\features\admin\dashboard\presentation\*') {
    $text = $text.Replace("'../dashboard/presentation/", "'../../dashboard/presentation/")
  }
  if ($relative -like 'lib\features\admin\appearance\presentation\*') {
    $text = $text.Replace("'../content_management/presentation/", "'../../content_management/presentation/")
  }
  [System.IO.File]::WriteAllText($file.FullName, $text, (New-Object System.Text.UTF8Encoding($false)))
}
Write-Output 'Admin import paths normalized.'
