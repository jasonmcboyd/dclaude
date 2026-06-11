<#
.SYNOPSIS
    Gets volume mount specifications from dclaude settings.

.DESCRIPTION
    Returns the 'volumes' array from the dclaude settings for the specified
    scope. For project scopes, returns the merged effective value (base +
    local override). For User scope, also checks the deprecated
    'commonVolumes' property.

.PARAMETER Scope
    Target settings scope: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Get-DClaudeVolume

    Lists volumes from the project's local settings.

.EXAMPLE
    Get-DClaudeVolume -Scope User

    Lists volumes from the user config.
#>
function Get-DClaudeVolume {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('User', 'Project', 'ProjectLocal')]
        [string]$Scope = 'ProjectLocal'
    )

    $resolved = Resolve-SettingsScope -Scope $Scope
    if (-not $resolved) { return }

    if ($Scope -eq 'User') {
        $config = Merge-SettingsFiles -Directory $resolved.Directory -Label 'user config'
    }
    else {
        $config = Merge-SettingsFiles -Directory $resolved.Directory -Label 'project config'
    }

    if ($config -and $config.PSObject.Properties['volumes']) {
        return , [array]$config.volumes
    }

    if ($Scope -eq 'User' -and $config -and $config.PSObject.Properties['commonVolumes']) {
        return , [array]$config.commonVolumes
    }

    return , @()
}
