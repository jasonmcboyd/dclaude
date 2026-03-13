<#
.SYNOPSIS
    Gets the dclaude configuration for a project.

.DESCRIPTION
    Reads the project-level dclaude settings by walking up the directory tree
    from the specified path looking for a .dclaude folder. Returns the merged
    result of settings.json and settings.local.json.

.PARAMETER Path
    Starting directory for the config search. Defaults to the current directory.

.EXAMPLE
    Get-DClaudeProject

    Shows the dclaude config for the current directory.

.EXAMPLE
    Get-DClaudeProject -Path C:\repos\my-project

    Shows the dclaude config for the specified project.
#>
function Get-DClaudeProject {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $PWD
    )

    $config = Get-DClaudeConfig -Path $Path

    if (-not $config) {
        return
    }

    $result = [PSCustomObject]@{
        ImageKey = if ($config.PSObject.Properties['imageKey']) { $config.imageKey } else { $null }
        Image    = if ($config.PSObject.Properties['image']) { $config.image } else { $null }
        Volumes  = if ($config.PSObject.Properties['volumes']) { @($config.volumes) } else { @() }
    }

    return $result
}
