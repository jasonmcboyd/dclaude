function Get-CurrentRuntimeVolume {
    <#
    .SYNOPSIS
        Selects the highest-revision populated runtime volume for an os+module version.
    .DESCRIPTION
        Enumerates existing runtime volumes for the given os+version, routes each name
        through Get-RuntimeVolumeRevision (an anchored match, so v0.6.4 never matches
        v0.6.40), and returns the highest-revision volume that is actually populated.

        Returns [PSCustomObject]@{ Name; Revision }, or $null when none is populated.
        This is SELECTION ONLY — it never provisions. Both Initialize-RuntimeVolume (lazy
        first-run provisioning) and the -Update outdated-check share this one algorithm so
        they cannot drift.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter(Mandatory)]
        [version]$Version
    )

    # The --filter name= match is a prefix match (so v0.6.4 would also surface v0.6.40),
    # so Get-RuntimeVolumeRevision applies an anchored regex and returns -1 for names that
    # aren't an exact os+version (+optional -rN) match.
    $prefix = "dclaude-runtime-$ContainerOS-v$Version"
    $names = docker volume ls --filter "name=$prefix" --format '{{.Name}}' 2>$null

    $best = $null   # highest-revision populated volume
    foreach ($name in $names) {
        $revision = Get-RuntimeVolumeRevision -Name $name -ContainerOS $ContainerOS -Version $Version
        if ($revision -lt 0) { continue }

        if ((Test-RuntimeVolumePopulated -ContainerOS $ContainerOS -VolumeName $name) -and
            ($null -eq $best -or $revision -gt $best.Revision)) {
            $best = [PSCustomObject]@{ Name = $name; Revision = $revision }
        }
    }

    return $best
}
