<#
.SYNOPSIS
    Removes a Docker image entry from the dclaude user configuration.

.DESCRIPTION
    Removes an image or a specific platform entry from ~/.dclaude/settings.json.
    If removing a specific platform leaves no platforms, the entire image entry
    is removed.

.PARAMETER Name
    Name of the image entry to remove.

.PARAMETER Platform
    Remove only this platform (Windows or Linux). If omitted, removes the
    entire image entry with all platforms.

.EXAMPLE
    Remove-DClaudeImage -Name 'pwsh'

    Removes the 'pwsh' image entry entirely (all platforms).

.EXAMPLE
    Remove-DClaudeImage -Name 'pwsh' -Platform Linux

    Removes only the Linux platform entry for 'pwsh'.
#>
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
        Write-Error "Image '$Name' not found in user config."
        return
    }

    if (-not $config.images.PSObject.Properties[$Name]) {
        Write-Error "Image '$Name' not found in user config."
        return
    }

    if ($Platform) {
        $platformKey = $Platform.ToLower()
        if (-not $config.images.$Name.PSObject.Properties[$platformKey]) {
            Write-Error "Image '$Name' does not have a '$platformKey' platform entry in user config."
            return
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
