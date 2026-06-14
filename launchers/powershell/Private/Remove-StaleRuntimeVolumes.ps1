function Remove-StaleRuntimeVolumes {
    <#
    .SYNOPSIS
        Removes runtime volumes that have been superseded and are no longer referenced.
    .DESCRIPTION
        Reclaims two kinds of stale volumes, never touching one a container still references:
          - Volumes from OLDER module versions (the current version re-provisions them).
          - Lower revisions of the CURRENT module version — the launcher and updates always
            mount/create the highest revision, so superseded lower ones can be reclaimed once
            nothing references them. The highest revision of the current version is always kept.

        Volumes from NEWER module versions are left alone so a rollback does not force a
        re-provision.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [version]$CurrentVersion
    )

    $allVolumes = docker volume ls --filter 'name=dclaude-runtime-' --format '{{.Name}}' 2>$null
    if (-not $allVolumes) { return }

    # Match the version + optional -rN suffix. The version part allows 2-4 dot-separated
    # components because volume names are built from [version] stringification ("$Version"),
    # which renders e.g. 1.0 as "1.0" and 1.0.0.5 as "1.0.0.5" — not always three parts.
    # This must stay consistent with the name built in New-RuntimeVolume / the launcher.
    $versionPattern = '-v(\d+(?:\.\d+){1,3})(?:-r(\d+))?$'

    # Find the highest revision of the current module version so we never remove it.
    $highestCurrentRevision = -1
    foreach ($vol in $allVolumes) {
        if ($vol -match $versionPattern -and [version]$Matches[1] -eq $CurrentVersion) {
            $revision = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
            if ($revision -gt $highestCurrentRevision) { $highestCurrentRevision = $revision }
        }
    }

    foreach ($vol in $allVolumes) {
        if ($vol -notmatch $versionPattern) { continue }
        $volVersion = [version]$Matches[1]
        $volRevision = if ($Matches[2]) { [int]$Matches[2] } else { 0 }

        if ($volVersion -eq $CurrentVersion) {
            # Current version: keep the highest revision, reclaim superseded lower ones.
            if ($volRevision -ge $highestCurrentRevision) { continue }
        }
        elseif ($volVersion -gt $CurrentVersion) {
            # Newer version — the user may have rolled back; leave it alone.
            continue
        }
        # Older version falls through to the in-use guard and removal.

        # Never remove a volume any container (running or stopped) still references.
        $containers = docker ps -a --filter "volume=$vol" --format '{{.ID}}' 2>$null
        if ($containers) { continue }

        Write-Host "[dclaude] Removing stale runtime volume $vol" -ForegroundColor DarkGray
        # MinGit files carry restrictive ACLs that prevent the Docker daemon from deleting
        # the volume's VHD backing directory. Changing ACLs inside the container doesn't
        # reliably propagate to the daemon's view, so instead take ownership and delete
        # the content from inside a container — the daemon then removes an empty directory.
        if ($vol -match '-windows-') {
            docker run --rm -v "${vol}:C:\vol" $script:DClaudeImages.ProvisionWindows `
                cmd /c "takeown /f C:\vol /r /d y >nul 2>&1 & icacls C:\vol /grant ContainerAdministrator:(OI)(CI)F /t /q >nul 2>&1 & rd /s /q C:\vol\mingit 2>nul & rd /s /q C:\vol\node 2>nul & exit 0" 2>$null | Out-Null
        }
        $rmOutput = docker volume rm $vol 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[dclaude] WARN: Could not remove $vol`: $rmOutput" -ForegroundColor Yellow
        }
    }
}
