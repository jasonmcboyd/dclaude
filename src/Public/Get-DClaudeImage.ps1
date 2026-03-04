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
            }
        }
    }
}
