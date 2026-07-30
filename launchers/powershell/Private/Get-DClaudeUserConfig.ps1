function Get-DClaudeUserConfig {
    [CmdletBinding()]
    param()

    $configDir = Join-Path $HOME '.dclaude'
    return Merge-SettingsFiles -Directory $configDir -Label 'user config'
}
