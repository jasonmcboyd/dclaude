function Resolve-ImageKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $userConfig = Get-DClaudeUserConfig

    if (-not $userConfig -or -not $userConfig.images) {
        throw "Cannot resolve image key '$Key'. No user config found at ~/.dclaude/dclaude.json or it has no 'images' property."
    }

    if (-not $userConfig.images.PSObject.Properties[$Key]) {
        throw "Image key '$Key' not found in ~/.dclaude/dclaude.json. Available keys: $($userConfig.images.PSObject.Properties.Name -join ', ')"
    }

    return $userConfig.images.$Key
}
