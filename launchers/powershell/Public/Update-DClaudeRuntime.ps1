<#
.SYNOPSIS
    Provisions a fresh dclaude runtime volume with an updated Claude Code.

.DESCRIPTION
    Creates a brand-new runtime volume at the next revision for the current module
    version, fully provisioning Node.js + Claude Code (+ MinGit on Windows) into it.

    Running containers are unaffected: they keep mounting their existing, lower-revision
    volume read-only. New containers launched by Invoke-DClaude automatically select the
    highest-revision populated volume, so they pick up the update. Superseded lower
    revisions are reclaimed automatically once no container references them.

.PARAMETER ContainerOS
    Target container platform: 'windows' or 'linux'. Defaults to the active Docker
    daemon's OS type.

.PARAMETER Version
    Specific @anthropic-ai/claude-code version to install. Defaults to latest.

.EXAMPLE
    Update-DClaudeRuntime

    Provisions a new runtime volume for the current Docker platform with the latest
    Claude Code.

.EXAMPLE
    Update-DClaudeRuntime -ContainerOS linux -Version 1.2.3

    Provisions a new Linux runtime volume pinned to Claude Code 1.2.3.
#>
function Update-DClaudeRuntime {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter()]
        [string]$Version
    )

    # Resolve into a plain local. Assigning back into the [ValidateSet] parameter would
    # re-run validation, so a $null/unsupported result from Get-DockerContainerOS would
    # throw a ValidationMetadataException instead of returning cleanly. Invoke-DClaude
    # uses the same plain-local pattern for this reason.
    $os = $ContainerOS
    if (-not $os) {
        $os = Get-DockerContainerOS
        if (-not $os) { return }
        $os = "$os".ToLower()
        if ($os -notin @('windows', 'linux')) {
            Write-Error "Unsupported Docker OS type '$os'. Only 'windows' and 'linux' are supported."
            return
        }
    }

    $moduleVersion = Get-DClaudeModuleVersion

    # Determine the next revision across ALL volumes for this os+version (populated or not).
    # The --filter name= match is a prefix match, so Get-RuntimeVolumeRevision applies an
    # anchored regex and returns -1 for names that aren't an exact match.
    $prefix = "dclaude-runtime-$os-v$moduleVersion"
    $names = docker volume ls --filter "name=$prefix" --format '{{.Name}}' 2>$null

    $maxRevision = 0
    foreach ($name in $names) {
        $revision = Get-RuntimeVolumeRevision -Name $name -ContainerOS $os -Version $moduleVersion
        if ($revision -gt $maxRevision) { $maxRevision = $revision }
    }
    $newName = "$prefix-r$($maxRevision + 1)"

    if (-not $PSCmdlet.ShouldProcess($newName, 'Provision runtime volume')) { return }

    if (-not (New-RuntimeVolume -ContainerOS $os -VolumeName $newName -ClaudeCodeVersion $Version)) {
        Write-Error 'Failed to provision runtime volume. Check network connectivity.'
        return
    }

    Write-Host "[dclaude] Provisioned new runtime volume: $newName" -ForegroundColor Green
    Write-Host '[dclaude] New containers will use it; running containers are unaffected.' -ForegroundColor DarkGray

    # Reclaim superseded lower revisions that no container references.
    Remove-StaleRuntimeVolumes -CurrentVersion $moduleVersion
}
