<#
.SYNOPSIS
    Removes volume mount specifications from dclaude settings.

.DESCRIPTION
    Removes one or more volume mount specifications from the 'volumes' array
    in the specified dclaude settings file. Errors if a spec is not found in
    the target file.

.PARAMETER Volume
    One or more volume mount specifications to remove.

.PARAMETER Scope
    Target settings file: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Remove-DClaudeVolume -Volume 'C:\data:/data:rw'

    Removes the volume from the project's settings.local.json.
#>
function Remove-DClaudeVolume {
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
    if (-not $config -or -not $config.PSObject.Properties['volumes'] -or $config.volumes -isnot [array]) {
        Write-Error "No volumes found in $Scope config."
        return
    }

    $existing = [array]$config.volumes
    foreach ($v in $Volume) {
        if ($v -notin $existing) {
            Write-Error "Volume '$v' not found in $Scope config."
            return
        }
    }

    if ($PSCmdlet.ShouldProcess("$Scope config", "Remove volumes: $($Volume -join ', ')")) {
        $newList = @($existing | Where-Object { $_ -notin $Volume })
        if ($newList.Count -eq 0) {
            $config.PSObject.Properties.Remove('volumes')
        }
        else {
            $config | Add-Member -MemberType NoteProperty -Name 'volumes' -Value @($newList) -Force
        }
        Save-SettingsFile -Directory $resolved.Directory -Config $config -FileName $resolved.FileName
    }
}
