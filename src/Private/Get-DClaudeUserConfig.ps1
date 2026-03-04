function Get-DClaudeUserConfig {
    [CmdletBinding()]
    param()

    $configPath = Join-Path (Join-Path $HOME '.dclaude') 'dclaude.json'

    if (Test-Path $configPath) {
        $content = Get-Content -Path $configPath -Raw
        return $content | ConvertFrom-Json
    }

    return $null
}
