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
        $baseProps = ($base.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
        Write-Debug "[config] $basePath`: loaded ($baseProps)"
    }
    else {
        Write-Debug "[config] $basePath`: not found"
    }

    $local = Read-SettingsFile -Directory $Directory -FileName 'settings.local.json'
    if ($local) {
        $schemaErrors = Test-DClaudeSettingsSchema -Config $local -Label "$Label ($localPath)"
        foreach ($e in $schemaErrors) { Write-Warning $e }
        $localProps = ($local.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
        Write-Debug "[config] $localPath`: loaded ($localProps)"
    }
    else {
        Write-Debug "[config] $localPath`: not found"
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
        if ($base.PSObject.Properties[$prop.Name]) {
            Write-Debug "[config] $Directory`: local overrides base for '$($prop.Name)'"
        }
        else {
            Write-Debug "[config] $Directory`: local adds '$($prop.Name)'"
        }
        $base | Add-Member -MemberType $prop.MemberType -Name $prop.Name -Value $prop.Value -Force
    }

    return $base
}
