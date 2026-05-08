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

        # Check if any container (running or stopped) references this volume
        $containers = docker ps -a --filter "volume=$vol" --format '{{.ID}}' 2>$null
        if ($containers) { continue }

        Write-Host "[dclaude] Removing stale runtime volume $vol" -ForegroundColor DarkGray
        docker volume rm $vol 2>$null | Out-Null
    }
}
