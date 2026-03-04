function Get-DClaudeConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $PWD
    )

    $configPath = Join-Path (Join-Path $Path '.dclaude') 'dclaude.json'

    if (Test-Path $configPath) {
        $content = Get-Content -Path $configPath -Raw
        try {
            return $content | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse config file '$configPath': $_"
        }
    }

    return $null
}
