function Get-DClaudeUserConfig {
    [CmdletBinding()]
    param()

    $configPath = Join-Path (Join-Path $HOME '.dclaude') 'dclaude.json'

    if (Test-Path $configPath) {
        $content = Get-Content -Path $configPath -Raw
        try {
            return $content | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse user config file '$configPath': $_"
        }
    }

    return $null
}
