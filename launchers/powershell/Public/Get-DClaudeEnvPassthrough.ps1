<#
.SYNOPSIS
    Gets environment variable passthrough patterns from dclaude settings.

.DESCRIPTION
    Returns the 'envPassthrough' array from the dclaude settings for the
    specified scope. For project scopes, returns the merged effective value
    (base + local override).

.PARAMETER Scope
    Target settings scope: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Get-DClaudeEnvPassthrough

    Lists env passthrough patterns from the project's local settings.

.EXAMPLE
    Get-DClaudeEnvPassthrough -Scope User

    Lists env passthrough patterns from the user config.
#>
function Get-DClaudeEnvPassthrough {
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

    if ($config -and $config.PSObject.Properties['envPassthrough'] -and $config.envPassthrough -is [array]) {
        return , [array]$config.envPassthrough
    }

    return , @()
}
