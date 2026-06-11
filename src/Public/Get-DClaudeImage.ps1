<#
.SYNOPSIS
    Lists Docker images registered in the dclaude user configuration.

.DESCRIPTION
    Returns image entries from ~/.dclaude/settings.json (merged with
    settings.local.json). Each entry is expanded to one row per platform,
    showing the image name, platform, tag, and volumes.

.PARAMETER Name
    Filter by image name. If omitted, all images are returned.

.EXAMPLE
    Get-DClaudeImage

    Lists all registered images across all platforms.

.EXAMPLE
    Get-DClaudeImage -Name 'pwsh'

    Shows platform entries for the 'pwsh' image only.
#>
function Get-DClaudeImage {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name
    )

    $config = Get-DClaudeUserConfig

    if (-not $config -or -not $config.PSObject.Properties['images'] -or -not $config.images) {
        return
    }

    $imageNames = if ($Name) {
        if (-not $config.images.PSObject.Properties[$Name]) { return }
        @($Name)
    }
    else {
        @($config.images.PSObject.Properties | ForEach-Object { $_.Name })
    }

    foreach ($imageName in $imageNames) {
        $imageEntry = $config.images.$imageName
        foreach ($platformProp in $imageEntry.PSObject.Properties) {
            $platformName = $platformProp.Name
            $platformValue = $platformProp.Value
            [PSCustomObject]@{
                Name     = $imageName
                Platform = $platformName
                Tag      = $platformValue.tag
                Volumes  = if ($platformValue.volumes) { @($platformValue.volumes) } else { @() }
                Env      = if ($platformValue.PSObject.Properties['env'] -and $platformValue.env) { $platformValue.env } else { $null }
            }
        }
    }
}
