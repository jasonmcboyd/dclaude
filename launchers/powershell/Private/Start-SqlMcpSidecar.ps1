function Start-SqlMcpSidecar {
    <#
    .SYNOPSIS
        Builds the SQL MCP sidecar image (if needed), creates a Docker network, and
        starts the sidecar container.
    .DESCRIPTION
        The sidecar runs an MCP server that holds SQL Server connection strings and
        enforces read-only access. The main Claude container connects to it over the
        Docker network — the connection strings never enter the Claude container.

        Returns [PSCustomObject]@{ NetworkName; SidecarName; McpUrl }, or $null on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Security.SecureString[]]$SqlConnections,

        [Parameter(Mandatory)]
        [string]$NetworkName,

        [Parameter(Mandatory)]
        [version]$ModuleVersion
    )

    $imageTag = "dclaude-sql-mcp:v$ModuleVersion"
    $sidecarName = "sql-mcp-$($NetworkName -replace '^dclaude-net-', '')"

    # Build the sidecar image if it doesn't already exist.
    $existing = docker image inspect $imageTag 2>$null
    if (-not $existing) {
        # sidecars/ is a sibling of Private/ in the installed module layout.
        # In the dev repo it lives at the repo root; try both locations.
        $moduleRoot = Split-Path $PSScriptRoot
        $dockerfilePath = Join-Path $moduleRoot 'sidecars/sql-mcp'
        if (-not (Test-Path (Join-Path $dockerfilePath 'Dockerfile'))) {
            # Dev repo layout: launchers/powershell/Private -> repo root is 3 levels up
            $repoRoot = Split-Path (Split-Path $moduleRoot)
            $dockerfilePath = Join-Path $repoRoot 'sidecars/sql-mcp'
        }
        if (-not (Test-Path (Join-Path $dockerfilePath 'Dockerfile'))) {
            Write-Error "SQL MCP sidecar Dockerfile not found. Expected at: $dockerfilePath"
            return
        }
        Write-Host '[dclaude] Building SQL MCP sidecar image...' -ForegroundColor DarkGray
        docker build -t $imageTag -q $dockerfilePath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to build SQL MCP sidecar image."
            return
        }
    }

    # Create the Docker network.
    docker network create $NetworkName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create Docker network '$NetworkName'."
        return
    }

    # Build the sidecar docker run args with decrypted connection strings.
    $sidecarArgs = @(
        'run', '-d', '--rm'
        '--name', $sidecarName
        '--network', $NetworkName
        '--network-alias', 'sql-mcp'
    )

    for ($i = 0; $i -lt $SqlConnections.Count; $i++) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlConnections[$i])
        try {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        $n = $i + 1
        $sidecarArgs += '-e'
        $sidecarArgs += "SQL_CONN_${n}=${plain}"
    }

    $sidecarArgs += $imageTag

    docker @sidecarArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to start SQL MCP sidecar container."
        docker network rm $NetworkName 2>&1 | Out-Null
        return
    }

    # Wait for the sidecar to become healthy.
    $timeout = 30
    $elapsed = 0
    $healthy = $false
    while ($elapsed -lt $timeout) {
        $status = docker inspect --format '{{.State.Health.Status}}' $sidecarName 2>$null
        if ($status -eq 'healthy') {
            $healthy = $true
            break
        }
        if ($status -eq 'unhealthy') {
            break
        }
        Start-Sleep -Seconds 1
        $elapsed++
    }

    if (-not $healthy) {
        Write-Error "SQL MCP sidecar failed to become healthy within ${timeout}s."
        docker stop $sidecarName 2>&1 | Out-Null
        docker network rm $NetworkName 2>&1 | Out-Null
        return
    }

    Write-Host '[dclaude] SQL MCP sidecar ready.' -ForegroundColor DarkGray

    return [PSCustomObject]@{
        NetworkName = $NetworkName
        SidecarName = $sidecarName
        McpUrl      = 'http://sql-mcp:3100/mcp'
    }
}
