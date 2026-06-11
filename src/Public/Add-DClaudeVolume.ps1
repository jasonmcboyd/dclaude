<#
.SYNOPSIS
    Adds volume mount specifications to dclaude settings.

.DESCRIPTION
    Appends one or more volume mount specifications to the 'volumes' array
    in the specified dclaude settings file. Volume specs use the format
    'host:container[:mode]'. Duplicate specs are skipped.

.PARAMETER Volume
    One or more volume mount specifications (e.g. 'C:/data:/data:rw').

.PARAMETER Scope
    Target settings file: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Add-DClaudeVolume -Volume 'C:\Users\me\.nuget:/home/claude/.nuget:ro'

    Adds a read-only NuGet cache mount to the project's settings.local.json.

.EXAMPLE
    Add-DClaudeVolume -Volume '%USERPROFILE%\.ssh:/home/claude/.ssh:ro' -Scope User

    Adds an SSH key mount to the user config (applies to all images).
#>
function Add-DClaudeVolume {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$Volume,

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

    $existing = if ($config.PSObject.Properties['volumes'] -and $config.volumes -is [array]) {
        , [array]$config.volumes
    } else { , @() }

    $toAdd = @($Volume | Where-Object { $_ -notin $existing })
    if ($toAdd.Count -eq 0) {
        Write-Verbose 'All volumes already present; nothing to add.'
        return
    }

    if ($PSCmdlet.ShouldProcess("$Scope config", "Add volumes: $($toAdd -join ', ')")) {
        $newList = $existing + $toAdd
        $config | Add-Member -MemberType NoteProperty -Name 'volumes' -Value @($newList) -Force
        Save-SettingsFile -Directory $resolved.Directory -Config $config -FileName $resolved.FileName
    }
}
