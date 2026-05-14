function Remove-StaleRuntimeVolumes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [version]$CurrentVersion
    )

    $allVolumes = docker volume ls --filter 'name=dclaude-runtime-' --format '{{.Name}}' 2>$null
    if (-not $allVolumes) { return }

    $currentSuffix = "-v$CurrentVersion"
    foreach ($vol in $allVolumes) {
        if ($vol -like "*$currentSuffix") { continue }

        # Leave volumes from newer versions alone — the user may have rolled back
        # and we don't want to force a re-provision on upgrade.
        if ($vol -match '-v(\d+\.\d+\.\d+)$') {
            if ([version]$Matches[1] -gt $CurrentVersion) { continue }
        }

        # Check if any container (running or stopped) references this volume
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
