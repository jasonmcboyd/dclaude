function Update-RuntimeIfOutdated {
    <#
    .SYNOPSIS
        Provisions a fresh runtime volume when the selected one's Claude Code is outdated.
    .DESCRIPTION
        Backs the -Update switch on Invoke-DClaude. Compares the Claude Code version baked
        into the currently-selected runtime volume (read from its Docker label, no container
        start) against the latest published version, and provisions a new revision via
        Update-DClaudeRuntime only when they differ.

        This never blocks the launch: if there is no populated volume yet, or the latest
        version cannot be determined, it reports and returns so normal lazy provisioning
        proceeds. ShouldProcess is handled by Update-DClaudeRuntime, which this delegates to.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter(Mandatory)]
        [version]$ModuleVersion
    )

    $selected = Get-CurrentRuntimeVolume -ContainerOS $ContainerOS -Version $ModuleVersion
    if (-not $selected) {
        # No populated volume — lazy provisioning will install latest, so nothing to update.
        Write-Verbose 'dclaude: no populated runtime volume yet; lazy provisioning will install latest'
        return
    }

    $latest = Get-LatestClaudeCodeVersion
    if (-not $latest) {
        Write-Host '[dclaude] Could not determine latest Claude Code version; using existing runtime.' -ForegroundColor Yellow
        return
    }

    $installed = Get-RuntimeVolumeClaudeVersion -VolumeName $selected.Name
    # Intentional string equality, not semver ordering: -Update means "track latest". Version
    # strings can carry prerelease tags that [version] can't order, and the rare case where the
    # volume is somehow newer than the registry's 'latest' should re-pin to latest by design.
    # Do not "fix" this into a greater-than comparison.
    if ($installed -eq $latest) {
        Write-Host "[dclaude] Claude Code is up to date ($installed)." -ForegroundColor DarkGray
        return
    }

    $from = if ($installed) { $installed } else { '(unlabeled)' }
    Write-Host "[dclaude] Updating Claude Code: $from -> $latest" -ForegroundColor Cyan
    # Update-DClaudeRuntime resolves latest again from the now-warm cache (free) and provisions
    # a new revision. It Write-Errors on its own failures; we just return either way.
    Update-DClaudeRuntime -ContainerOS $ContainerOS
}
