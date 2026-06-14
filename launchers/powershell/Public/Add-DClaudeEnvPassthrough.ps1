<#
.SYNOPSIS
    Adds environment variable passthrough patterns to dclaude settings.

.DESCRIPTION
    Appends one or more environment variable name patterns to the 'envPassthrough'
    array in the specified dclaude settings file. Patterns can be exact names
    (e.g. 'AZURE_DEVOPS_PAT') or globs (e.g. 'NUGET_*'). Duplicate patterns
    are skipped.

.PARAMETER Pattern
    One or more environment variable name patterns to add.

.PARAMETER Scope
    Target settings file: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Add-DClaudeEnvPassthrough -Pattern 'NUGET_*', 'AZURE_DEVOPS_PAT'

    Adds two passthrough patterns to the project's settings.local.json.

.EXAMPLE
    Add-DClaudeEnvPassthrough -Pattern 'VSS_NUGET_*' -Scope User

    Adds a passthrough pattern to the user config.
#>
function Add-DClaudeEnvPassthrough {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$Pattern,

        [Parameter()]
        [ValidateSet('User', 'Project', 'ProjectLocal')]
        [string]$Scope = 'ProjectLocal'
    )

    $resolved = Resolve-SettingsScope -Scope $Scope
    if (-not $resolved) { return }

    $config = Read-SettingsFile -Directory $resolved.Directory -FileName $resolved.FileName
    if (-not $config) {
        $config = [PSCustomObject]@{}
    }

    $existing = if ($config.PSObject.Properties['envPassthrough'] -and $config.envPassthrough -is [array]) {
        , [array]$config.envPassthrough
    } else { , @() }

    $toAdd = @($Pattern | Where-Object { $_ -notin $existing })
    if ($toAdd.Count -eq 0) {
        Write-Verbose 'All patterns already present; nothing to add.'
        return
    }

    if ($PSCmdlet.ShouldProcess("$Scope config", "Add envPassthrough patterns: $($toAdd -join ', ')")) {
        $newList = $existing + $toAdd
        $config | Add-Member -MemberType NoteProperty -Name 'envPassthrough' -Value @($newList) -Force
        Save-SettingsFile -Directory $resolved.Directory -Config $config -FileName $resolved.FileName
    }
}
