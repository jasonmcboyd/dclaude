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

    $base = Read-SettingsFile -Directory $Directory -FileName 'settings.json'
    if ($base) {
        $schemaErrors = Test-DClaudeSettingsSchema -Config $base -Label "$Label ($basePath)"
        foreach ($e in $schemaErrors) { Write-Warning $e }
    }

    $local = Read-SettingsFile -Directory $Directory -FileName 'settings.local.json'
    if ($local) {
        $schemaErrors = Test-DClaudeSettingsSchema -Config $local -Label "$Label ($localPath)"
        foreach ($e in $schemaErrors) { Write-Warning $e }
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
