function Read-SettingsFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory
    )

    $filePath = Join-Path $Directory 'settings.json'

    if (-not (Test-Path $filePath)) {
        return $null
    }

    $content = Get-Content -Path $filePath -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }
    try {
        return $content | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse settings file '$filePath': $_"
    }
}
