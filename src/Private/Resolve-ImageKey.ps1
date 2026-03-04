function Resolve-ImageKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$ContainerOS
    )

    $userConfig = Get-DClaudeUserConfig

    if (-not $userConfig -or -not $userConfig.images) {
        throw "Cannot resolve image key '$Key'. No user config found at ~/.dclaude/settings.json or it has no 'images' property."
    }

    if (-not $userConfig.images.PSObject.Properties[$Key]) {
        throw "Image key '$Key' not found in ~/.dclaude/settings.json. Available keys: $($userConfig.images.PSObject.Properties.Name -join ', ')"
    }

    $entry = $userConfig.images.$Key

    $platformKey = $ContainerOS.ToLower()
    if (-not $entry.PSObject.Properties[$platformKey]) {
        $available = ($entry.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
        throw "Image key '$Key' has no '$platformKey' platform entry in ~/.dclaude/settings.json. Available platforms: $available"
    }

    $platformEntry = $entry.$platformKey

    if (-not $platformEntry.tag) {
        throw "Image key '$Key' platform '$platformKey' in ~/.dclaude/settings.json is missing the required 'tag' property."
    }

    $volumes = if ($platformEntry.volumes) { @($platformEntry.volumes) } else { @() }

    return [PSCustomObject]@{
        tag     = $platformEntry.tag
        volumes = $volumes
    }
}
