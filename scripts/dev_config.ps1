function Assert-AzkarSupabaseDevConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $configPath = Join-Path $ProjectRoot 'config\dev.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw 'Missing config/dev.json. Copy config/dev.example.json and fill in the local development settings.'
    }

    try {
        $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'config/dev.json is not valid JSON. Correct it locally; configuration values are not displayed.'
    }

    $problems = New-Object System.Collections.Generic.List[string]
    $url = [string]$config.SUPABASE_URL
    $parsedUrl = $null
    if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$parsedUrl) -or
        $parsedUrl.Scheme -ne 'https' -or
        [string]::IsNullOrWhiteSpace($parsedUrl.Host)) {
        $problems.Add('SUPABASE_URL must be a valid HTTPS URL.')
    }

    $key = [string]$config.SUPABASE_ANON_KEY
    $validKey = $key.StartsWith('sb_publishable_', [StringComparison]::Ordinal)
    if (-not $validKey) {
        $segments = $key.Split('.')
        if ($segments.Length -eq 3) {
            try {
                $payload = $segments[1].Replace('-', '+').Replace('_', '/')
                switch ($payload.Length % 4) {
                    2 { $payload += '==' }
                    3 { $payload += '=' }
                }
                $claims = [Text.Encoding]::UTF8.GetString(
                    [Convert]::FromBase64String($payload)
                ) | ConvertFrom-Json -ErrorAction Stop
                $validKey = $claims.role -eq 'anon'
            }
            catch {
                $validKey = $false
            }
        }
    }
    if (-not $validKey) {
        $problems.Add('SUPABASE_ANON_KEY must be an anon or publishable key.')
    }

    if ([string]$config.AZKAR_DEMO_MODE -ne 'false') {
        $problems.Add('AZKAR_DEMO_MODE must be false for Supabase development.')
    }
    if ([string]$config.AZKAR_AUTH_SCHEMA_VERIFIED -ne 'true') {
        $problems.Add('AZKAR_AUTH_SCHEMA_VERIFIED must be true for this verified project.')
    }

    if ($problems.Count -gt 0) {
        throw ('Invalid config/dev.json: ' + ($problems -join ' '))
    }

    return $configPath
}
