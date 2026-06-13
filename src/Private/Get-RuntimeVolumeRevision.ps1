function Get-RuntimeVolumeRevision {
    <#
    .SYNOPSIS
        Parses the revision number from a runtime volume name.
    .DESCRIPTION
        Runtime volumes are named 'dclaude-runtime-{os}-v{version}' (legacy, revision 0)
        or 'dclaude-runtime-{os}-v{version}-r{N}' (revision N). Returns the revision as an
        integer when the name matches the given os+version exactly, otherwise -1.

        The match is anchored so that version 0.6.4 does not match 0.6.40, and a trailing
        '-r<digits>' is the only suffix permitted.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter(Mandatory)]
        [version]$Version
    )

    $prefix = [regex]::Escape("dclaude-runtime-$ContainerOS-v$Version")
    if ($Name -match "^$prefix(?:-r(\d+))?$") {
        # No '-r' suffix means a legacy volume, which we treat as revision 0.
        if ($Matches[1]) { return [int]$Matches[1] }
        return 0
    }
    return -1
}
