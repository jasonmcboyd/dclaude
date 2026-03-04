function Get-DClaudeConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $PWD
    )

    $configDir = Join-Path $Path '.dclaude'
    return Merge-SettingsFiles -Directory $configDir -Label 'project config'
}
