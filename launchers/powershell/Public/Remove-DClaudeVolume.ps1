<#
.SYNOPSIS
    Removes volume mount specifications from dclaude settings.

.DESCRIPTION
    Removes one or more volume mount specifications from the 'volumes' object
    in the specified dclaude settings file under the given platform key.
    Matches on the local (host) path — you don't need to specify the full
    volume spec string.

.PARAMETER LocalPath
    One or more host paths to remove. Each is matched against the local-path
    portion of stored volume specs (the part before the first colon separator).

.PARAMETER Platform
    Target platform: Windows or Linux.

.PARAMETER Scope
    Target settings file: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Remove-DClaudeVolume C:\data -Platform Linux

    Removes the volume whose local path is C:\data from the project's
    settings.local.json Linux entries.
#>
function Remove-DClaudeVolume {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$LocalPath,

        [Parameter(Mandatory)]
        [ValidateSet('Windows', 'Linux')]
        [string]$Platform,

        [Parameter()]
        [ValidateSet('User', 'Project', 'ProjectLocal')]
        [string]$Scope = 'ProjectLocal'
    )

    $resolved = Resolve-SettingsScope -Scope $Scope -ForWrite
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

    $toRemove = @()
    foreach ($path in $LocalPath) {
        $normalized = $path.TrimEnd('\', '/')
        $matched = @($existing | Where-Object {
            if ($_ -match '^([A-Za-z]:)?([^:]+):') {
                $specLocal = "$($Matches[1])$($Matches[2])"
            } else {
                $specLocal = $_
            }
            $specLocal.TrimEnd('\', '/') -eq $normalized
        })
        if ($matched.Count -eq 0) {
            Write-Error "No volume with local path '$path' found in $Scope config ($platKey)."
            return
        }
        $toRemove += $matched
    }

    if ($PSCmdlet.ShouldProcess("$Scope config ($platKey)", "Remove volumes: $($toRemove -join ', ')")) {
        $newList = @($existing | Where-Object { $_ -notin $toRemove })
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
