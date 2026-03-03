function Get-DClaudeConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $PWD
    )

    $configPath = Join-Path (Join-Path $Path '.dclaude') 'dclaude.json'

    if (Test-Path $configPath) {
        $content = Get-Content -Path $configPath -Raw
        return $content | ConvertFrom-Json
    }

    return $null
}
