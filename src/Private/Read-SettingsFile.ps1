function Read-SettingsFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter()]
        [string]$FileName = 'settings.json'
    )

    $filePath = Join-Path $Directory $FileName

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
