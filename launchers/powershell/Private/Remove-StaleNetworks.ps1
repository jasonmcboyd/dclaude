function Remove-StaleNetworks {
    <#
    .SYNOPSIS
        Removes orphaned dclaude Docker networks that have no containers attached.
    .DESCRIPTION
        Each dclaude -SqlConnection invocation creates a uniquely named Docker network.
        On graceful shutdown the finally block removes it, but hard terminations (terminal
        close, machine sleep, crashes) leave orphans. This sweep runs at startup and
        removes any dclaude-net-* network with no connected containers.
    #>
    [CmdletBinding()]
    param()

    $networks = docker network ls --filter 'name=dclaude-net-' --format '{{.Name}}' 2>$null
    if (-not $networks) { return }

    foreach ($net in $networks) {
        $containers = docker network inspect $net --format '{{range .Containers}}{{.Name}} {{end}}' 2>$null
        if ($containers -and $containers.Trim()) { continue }

        Write-Host "[dclaude] Removing stale network $net" -ForegroundColor DarkGray
        $rmOutput = docker network rm $net 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[dclaude] WARN: Could not remove ${net}: $rmOutput" -ForegroundColor Yellow
        }
    }
}
