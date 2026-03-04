function Remove-DClaudeImage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('Windows', 'Linux')]
        [string]$Platform
    )

    $directory = Join-Path $HOME '.dclaude'
    $config = Read-SettingsFile -Directory $directory

    if (-not $config -or -not $config.PSObject.Properties['images'] -or -not $config.images) {
        throw "Image '$Name' not found in user config."
    }

    if (-not $config.images.PSObject.Properties[$Name]) {
        throw "Image '$Name' not found in user config."
    }

    if ($Platform) {
        $platformKey = $Platform.ToLower()
        if (-not $config.images.$Name.PSObject.Properties[$platformKey]) {
            throw "Image '$Name' does not have a '$platformKey' platform entry in user config."
        }
        $target = "Image '$Name' ($platformKey)"
    }
    else {
        $target = "Image '$Name' (all platforms)"
    }

    if ($PSCmdlet.ShouldProcess($target, 'Remove')) {
        if ($Platform) {
            $config.images.$Name.PSObject.Properties.Remove($platformKey)

            # If no platforms remain, remove the entire image entry
            if (@($config.images.$Name.PSObject.Properties).Count -eq 0) {
                $config.images.PSObject.Properties.Remove($Name)
            }
        }
        else {
            $config.images.PSObject.Properties.Remove($Name)
        }

        Save-SettingsFile -Directory $directory -Config $config
    }
}
