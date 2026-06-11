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
        Write-Error "Cannot resolve image key '$Key'. No user config found at ~/.dclaude/settings.json or it has no 'images' property."
        return
    }

    if (-not $userConfig.images.PSObject.Properties[$Key]) {
        Write-Error "Image key '$Key' not found in ~/.dclaude/settings.json. Available keys: $($userConfig.images.PSObject.Properties.Name -join ', ')"
        return
    }

    $entry = $userConfig.images.$Key

    $platformKey = $ContainerOS.ToLower()
    if (-not $entry.PSObject.Properties[$platformKey]) {
        $available = ($entry.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
        Write-Error "Image key '$Key' has no '$platformKey' platform entry in ~/.dclaude/settings.json. Available platforms: $available"
        return
    }

    $platformEntry = $entry.$platformKey

    if (-not $platformEntry.tag) {
        Write-Error "Image key '$Key' platform '$platformKey' in ~/.dclaude/settings.json is missing the required 'tag' property."
        return
    }

    $volumes = if ($platformEntry.volumes) { @($platformEntry.volumes) } else { @() }
    $envPassthrough = if ($platformEntry.envPassthrough) { @($platformEntry.envPassthrough) } else { @() }
    $env = if ($platformEntry.PSObject.Properties['env'] -and $platformEntry.env) { $platformEntry.env } else { $null }

    return [PSCustomObject]@{
        tag            = $platformEntry.tag
        volumes        = $volumes
        envPassthrough = $envPassthrough
        env            = $env
    }
}
