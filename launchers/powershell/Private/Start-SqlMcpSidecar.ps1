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
        [version]$ModuleVersion,

        [Parameter(Mandatory)]
        [ValidateSet('linux', 'windows')]
        [string]$ContainerOS
    )

    $imageTag = "dclaude-sql-mcp-${ContainerOS}:v$ModuleVersion"
    $sidecarName = "sql-mcp-$($NetworkName -replace '^dclaude-net-', '')"

    # Track what we've created so cleanup on failure is precise.
    $networkCreated = $false
    $sidecarStarted = $false

    try {
        # Build the sidecar image if it doesn't already exist.
        $existing = docker image inspect $imageTag 2>$null
        if (-not $existing) {
            $moduleRoot = Split-Path $PSScriptRoot
            $sidecarDir = Join-Path $moduleRoot 'sidecars/sql-mcp'
            if (-not (Test-Path (Join-Path $sidecarDir 'Dockerfile'))) {
                $repoRoot = Split-Path (Split-Path $moduleRoot)
                $sidecarDir = Join-Path $repoRoot 'sidecars/sql-mcp'
            }
            $dockerfile = if ($ContainerOS -eq 'windows') { 'Dockerfile.windows' } else { 'Dockerfile' }
            $dockerfileFull = Join-Path $sidecarDir $dockerfile
            if (-not (Test-Path $dockerfileFull)) {
                Write-Error "SQL MCP sidecar Dockerfile not found. Expected at: $dockerfileFull"
                return
            }
            Write-Host '[dclaude] Building SQL MCP sidecar image...' -ForegroundColor DarkGray
            $buildOutput = docker build -t $imageTag -f $dockerfileFull -q $sidecarDir 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to build SQL MCP sidecar image: $buildOutput"
                return
            }
        }

        # Clean up any stale resources from a previous crashed run.
        $staleContainer = docker inspect --format '{{.State.Status}}' $sidecarName 2>$null
        if ($staleContainer) {
            Write-Verbose "Removing stale sidecar container '$sidecarName'."
            docker rm -f $sidecarName 2>&1 | Out-Null
        }
        $staleNetwork = docker network inspect $NetworkName 2>$null
        if ($staleNetwork) {
            Write-Verbose "Removing stale network '$NetworkName'."
            docker network rm $NetworkName 2>&1 | Out-Null
        }

        # Create the Docker network. Windows containers require 'nat'; Linux uses 'bridge'.
        $driver = if ($ContainerOS -eq 'windows') { 'nat' } else { 'bridge' }
        $networkOutput = docker network create -d $driver $NetworkName 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create Docker network '$NetworkName': $networkOutput"
            return
        }
        $networkCreated = $true

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

        $runOutput = docker @sidecarArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to start SQL MCP sidecar container: $runOutput"
            return
        }
        $sidecarStarted = $true

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
            $logs = docker logs $sidecarName 2>&1
            Write-Error "SQL MCP sidecar failed to become healthy within ${timeout}s. Logs:`n$logs"
            return
        }

        Write-Host '[dclaude] SQL MCP sidecar ready.' -ForegroundColor DarkGray

        return [PSCustomObject]@{
            NetworkName = $NetworkName
            SidecarName = $sidecarName
            McpUrl      = 'http://sql-mcp:3100/mcp'
        }
    }
    finally {
        # If we're returning successfully (healthy sidecar), don't clean up.
        # Only clean up if we hit a failure after creating resources.
        if (-not $healthy) {
            if ($sidecarStarted) {
                docker rm -f $sidecarName 2>&1 | Out-Null
            }
            if ($networkCreated) {
                docker network rm $NetworkName 2>&1 | Out-Null
            }
        }
    }
}
