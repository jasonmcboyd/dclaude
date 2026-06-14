<#
.SYNOPSIS
    Removes volume mount specifications from dclaude settings.

.DESCRIPTION
    Removes one or more volume mount specifications from the 'volumes' object
    in the specified dclaude settings file under the given platform key.
    Errors if a spec is not found in the target file.

.PARAMETER Volume
    One or more volume mount specifications to remove.

.PARAMETER Platform
    Target platform: Windows or Linux.

.PARAMETER Scope
    Target settings file: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Remove-DClaudeVolume -Volume 'C:\data:/data:rw' -Platform Linux

    Removes the volume from the project's settings.local.json Linux entries.
#>
function Remove-DClaudeVolume {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$Volume,

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

    $config = Read-SettingsFile -Directory $resolved.Directory -FileName $resolved.FileName
    if (-not $config -or
        -not $config.PSObject.Properties['volumes'] -or
        $config.volumes -isnot [PSCustomObject] -or
        -not $config.volumes.PSObject.Properties[$platKey] -or
        $config.volumes.$platKey -isnot [array]) {
        Write-Error "No $platKey volumes found in $Scope config."
        return
    }

    $existing = [array]$config.volumes.$platKey
    foreach ($v in $Volume) {
        if ($v -notin $existing) {
            Write-Error "Volume '$v' not found in $Scope config ($platKey)."
            return
        }
    }

    if ($PSCmdlet.ShouldProcess("$Scope config ($platKey)", "Remove volumes: $($Volume -join ', ')")) {
        $newList = @($existing | Where-Object { $_ -notin $Volume })
        if ($newList.Count -eq 0) {
            $config.volumes.PSObject.Properties.Remove($platKey)
            $remainingKeys = @($config.volumes.PSObject.Properties)
            if ($remainingKeys.Count -eq 0) {
                $config.PSObject.Properties.Remove('volumes')
            }
        }
        else {
            $config.volumes | Add-Member -MemberType NoteProperty -Name $platKey -Value @($newList) -Force
        }
        Save-SettingsFile -Directory $resolved.Directory -Config $config -FileName $resolved.FileName
    }
}
