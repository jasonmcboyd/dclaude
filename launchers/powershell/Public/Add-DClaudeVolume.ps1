<#
.SYNOPSIS
    Adds a volume mount to dclaude settings.

.DESCRIPTION
    Appends a volume mount specification to the 'volumes' object in the
    specified dclaude settings file under the given platform key. By default
    the container path matches the local path and the mount is read-only.
    Use -ContainerPath to mount at a different location, and -ReadWrite for
    a writable mount.

.PARAMETER LocalPath
    Host path to mount. Environment variables (%VAR%) are expanded at
    container launch time.

.PARAMETER ContainerPath
    Container-side mount path. Defaults to the same as LocalPath.

.PARAMETER ReadWrite
    Mount the volume read-write instead of the default read-only.

.PARAMETER Platform
    Target platform: Windows or Linux.

.PARAMETER Scope
    Target settings file: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Add-DClaudeVolume C:\Users\me\source\repos\jboyd-fcm -Platform Linux

    Mounts the directory read-only at the same path inside Linux containers.

.EXAMPLE
    Add-DClaudeVolume C:\Users\me\.nuget -ContainerPath /home/claude/.nuget -Platform Linux

    Mounts .nuget read-only at a different container path in Linux containers.

.EXAMPLE
    Add-DClaudeVolume C:\wrk\data -ReadWrite -Platform Windows -Scope User

    Adds a writable mount to the user config for Windows containers.
#>
function Add-DClaudeVolume {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$LocalPath,

        [Parameter(Position = 1)]
        [string]$ContainerPath,

        [Parameter()]
        [switch]$ReadWrite,

        [Parameter(Mandatory)]
        [ValidateSet('Windows', 'Linux')]
        [string]$Platform,

        [Parameter()]
        [ValidateSet('User', 'Project', 'ProjectLocal')]
        [string]$Scope = 'ProjectLocal'
    )

    $resolved = Resolve-SettingsScope -Scope $Scope
    if (-not $resolved) { return }

    if (-not $ContainerPath) {
        $ContainerPath = $LocalPath
    }
    $mode = if ($ReadWrite) { 'rw' } else { 'ro' }
    $volumeSpec = "${LocalPath}:${ContainerPath}:${mode}"

    $platKey = $Platform.ToLower()

    $config = Read-SettingsFile -Directory $resolved.Directory -FileName $resolved.FileName
    if (-not $config) {
        $config = [PSCustomObject]@{}
    }

    $volumesObj = if ($config.PSObject.Properties['volumes'] -and $config.volumes -is [PSCustomObject]) {
        $config.volumes
    } else {
        [PSCustomObject]@{}
    }

    $existing = if ($volumesObj.PSObject.Properties[$platKey] -and $volumesObj.$platKey -is [array]) {
        , [array]$volumesObj.$platKey
    } else { , @() }

    if ($volumeSpec -in $existing) {
        Write-Verbose "Volume '$volumeSpec' already present under '$platKey'; nothing to add."
        return
    }

    if ($PSCmdlet.ShouldProcess("$Scope config ($platKey)", "Add volume: $volumeSpec")) {
        $newList = $existing + @($volumeSpec)
        $volumesObj | Add-Member -MemberType NoteProperty -Name $platKey -Value @($newList) -Force
        $config | Add-Member -MemberType NoteProperty -Name 'volumes' -Value $volumesObj -Force
        Save-SettingsFile -Directory $resolved.Directory -Config $config -FileName $resolved.FileName
    }
}
