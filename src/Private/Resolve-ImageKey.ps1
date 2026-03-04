function Resolve-ImageKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $userConfig = Get-DClaudeUserConfig

    if (-not $userConfig -or -not $userConfig.images) {
        throw "Cannot resolve image key '$Key'. No user config found at ~/.dclaude/settings.json or it has no 'images' property."
    }

    if (-not $userConfig.images.PSObject.Properties[$Key]) {
        throw "Image key '$Key' not found in ~/.dclaude/settings.json. Available keys: $($userConfig.images.PSObject.Properties.Name -join ', ')"
    }

    $entry = $userConfig.images.$Key

    if ($entry -is [string]) {
        throw "Image key '$Key' in ~/.dclaude/settings.json must be an object with at least a 'tag' property, not a bare string. Example: { `"$Key`": { `"tag`": `"$entry`" } }"
    }

    if (-not $entry.tag) {
        throw "Image key '$Key' in ~/.dclaude/settings.json is missing the required 'tag' property."
    }

    $volumes = if ($entry.volumes) { @($entry.volumes) } else { @() }

    return [PSCustomObject]@{
        tag     = $entry.tag
        volumes = $volumes
    }
}
