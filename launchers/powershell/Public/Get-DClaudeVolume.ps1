<#
.SYNOPSIS
    Gets volume mount specifications from dclaude settings.

.DESCRIPTION
    Returns volume mount specifications from the dclaude settings for the
    specified scope and platform. For project scopes, returns the merged
    effective value (base + local override). For User scope, also checks
    the deprecated 'commonVolumes' property.

.PARAMETER Platform
    Target platform: Windows or Linux.

.PARAMETER Scope
    Target settings scope: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Get-DClaudeVolume -Platform Linux

    Lists Linux volumes from the project's local settings.

.EXAMPLE
    Get-DClaudeVolume -Platform Windows -Scope User

    Lists Windows volumes from the user config.
#>
function Get-DClaudeVolume {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Windows', 'Linux')]
        [string]$Platform,

        [Parameter()]
        [ValidateSet('User', 'Project', 'ProjectLocal')]
        [string]$Scope = 'ProjectLocal'
    )

    $resolved = Resolve-SettingsScope -Scope $Scope
    if (-not $resolved) { return }

    $platKey = $Platform.ToLower()

    if ($Scope -eq 'User') {
        $config = Merge-SettingsFiles -Directory $resolved.Directory -Label 'user config'
    }
    else {
        $config = Merge-SettingsFiles -Directory $resolved.Directory -Label 'project config'
    }

    $volumesProp = if ($config -and $config.PSObject.Properties['volumes']) {
        $config.volumes
    } elseif ($Scope -eq 'User' -and $config -and $config.PSObject.Properties['commonVolumes']) {
        $config.commonVolumes
    } else { $null }

    if ($volumesProp -is [PSCustomObject] -and $volumesProp.PSObject.Properties[$platKey]) {
        return , [array]$volumesProp.$platKey
    }

    return , @()
}
