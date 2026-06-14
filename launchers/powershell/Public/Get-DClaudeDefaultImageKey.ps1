<#
.SYNOPSIS
    Gets the default Docker image key for dclaude.

.DESCRIPTION
    Returns the 'defaultImageKey' value from the dclaude settings for the
    specified scope. For project scopes, returns the merged effective value
    (base + local override).

.PARAMETER Scope
    Target settings scope: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Get-DClaudeDefaultImageKey

    Returns the effective default image key from the project's local settings.

.EXAMPLE
    Get-DClaudeDefaultImageKey -Scope User

    Returns the default image key from the user config.
#>
function Get-DClaudeDefaultImageKey {
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

    if ($config -and $config.PSObject.Properties['defaultImageKey']) {
        return $config.defaultImageKey
    }

    return $null
}
