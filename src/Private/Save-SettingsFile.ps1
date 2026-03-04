function Save-SettingsFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    if (-not (Test-Path $Directory)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }

    $filePath = Join-Path $Directory 'settings.json'
    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
}
