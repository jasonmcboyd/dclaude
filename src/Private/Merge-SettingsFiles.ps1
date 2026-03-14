function Merge-SettingsFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $basePath = Join-Path $Directory 'settings.json'
    $localPath = Join-Path $Directory 'settings.local.json'

    $base = $null
    $local = $null

    if (Test-Path $basePath) {
        $content = Get-Content -Path $basePath -Raw
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            try {
                $base = $content | ConvertFrom-Json
            }
            catch {
                throw "Failed to parse $Label file '$basePath': $_"
            }
            $schemaErrors = Test-DClaudeSettingsSchema -Config $base -Label "$Label ($basePath)"
            foreach ($e in $schemaErrors) { Write-Warning $e }
        }
    }

    if (Test-Path $localPath) {
        $content = Get-Content -Path $localPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            try {
                $local = $content | ConvertFrom-Json
            }
            catch {
                throw "Failed to parse $Label local override file '$localPath': $_"
            }
            $schemaErrors = Test-DClaudeSettingsSchema -Config $local -Label "$Label ($localPath)"
            foreach ($e in $schemaErrors) { Write-Warning $e }
        }
    }

    if (-not $base -and -not $local) {
        return $null
    }

    if (-not $local) {
        return $base
    }

    if (-not $base) {
        return $local
    }

    # Shallow-merge: local properties override base
    foreach ($prop in $local.PSObject.Properties) {
        $base | Add-Member -MemberType $prop.MemberType -Name $prop.Name -Value $prop.Value -Force
    }

    return $base
}
