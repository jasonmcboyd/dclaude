function Stop-SqlMcpSidecar {
    <#
    .SYNOPSIS
        Stops the SQL MCP sidecar container and removes the Docker network.
    .DESCRIPTION
        Idempotent cleanup: safe to call even if the sidecar already stopped or the
        network was already removed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SidecarName,

        [Parameter(Mandatory)]
        [string]$NetworkName
    )

    docker stop $SidecarName 2>&1 | Out-Null
    docker network rm $NetworkName 2>&1 | Out-Null
    Write-Host '[dclaude] Cleaned up SQL MCP sidecar.' -ForegroundColor DarkGray
}
