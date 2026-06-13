function Initialize-RuntimeVolume {
    <#
    .SYNOPSIS
        Selects the runtime volume to mount, provisioning one on first run.
    .DESCRIPTION
        Runtime volumes are versioned by module version and carry a monotonic revision:
        'dclaude-runtime-{os}-v{version}' (legacy, revision 0) or
        'dclaude-runtime-{os}-v{version}-r{N}'. Selection picks the highest-revision
        populated volume so that an update provisioned by Update-DClaudeRuntime (a new,
        higher revision) is preferred without disrupting containers still mounting an
        older revision read-only.

        If no populated volume exists, a new one is provisioned at the next revision.
        Returns [PSCustomObject]@{ VolumeName; MountPath }, or $null on provisioning failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter(Mandatory)]
        [version]$Version
    )

    $mountPath = if ($ContainerOS -eq 'linux') { '/opt/dclaude-runtime' } else { 'C:\dclaude-runtime' }

    # Enumerate existing runtime volumes for this os+version. The --filter name= match is a
    # prefix match (so v0.6.4 would also surface v0.6.40), so Get-RuntimeVolumeRevision applies
    # an anchored regex and returns -1 for names that aren't an exact os+version (+optional -rN) match.
    $prefix = "dclaude-runtime-$ContainerOS-v$Version"
    $names = docker volume ls --filter "name=$prefix" --format '{{.Name}}' 2>$null

    $maxRevision = -1
    $bestPopulated = $null   # highest-revision populated volume
    foreach ($name in $names) {
        $revision = Get-RuntimeVolumeRevision -Name $name -ContainerOS $ContainerOS -Version $Version
        if ($revision -lt 0) { continue }
        if ($revision -gt $maxRevision) { $maxRevision = $revision }

        if ((Test-RuntimeVolumePopulated -ContainerOS $ContainerOS -VolumeName $name) -and
            ($null -eq $bestPopulated -or $revision -gt $bestPopulated.Revision)) {
            $bestPopulated = [PSCustomObject]@{ Name = $name; Revision = $revision }
        }
    }

    # A populated volume exists — mount the highest revision, no provisioning needed.
    if ($bestPopulated) {
        return [PSCustomObject]@{
            VolumeName = $bestPopulated.Name
            MountPath  = $mountPath
        }
    }

    # Nothing populated — provision the next revision (1 when no volumes exist at all).
    $nextRevision = if ($maxRevision -lt 0) { 1 } else { $maxRevision + 1 }
    $newName = "$prefix-r$nextRevision"

    if (-not (New-RuntimeVolume -ContainerOS $ContainerOS -VolumeName $newName)) {
        Write-Error 'Failed to provision runtime volume. Check network connectivity.'
        return
    }

    return [PSCustomObject]@{
        VolumeName = $newName
        MountPath  = $mountPath
    }
}
