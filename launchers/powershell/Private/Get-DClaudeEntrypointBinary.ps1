function Get-DClaudeEntrypointBinary {
    <#
    .SYNOPSIS
        Resolves the host path to the Go entrypoint binary for a given container OS.
    .DESCRIPTION
        The runtime volume carries only Node.js + Claude Code; the entrypoint binary is shipped
        inside this module (under bin/) and mounted into the container from the host at launch.
        The binary is version-locked to the module, so a module update (which forces a fresh
        runtime volume anyway) is the only thing that changes it.

        Resolution order:
        1. DCLAUDE_ENTRYPOINT_SRC (development override) — a locally built binary, for fast
           iteration without rebuilding the module package.
        2. The module-bundled binary: bin/dclaude-entrypoint-<os>-<arch>[.exe].

        Returns $null (with Write-Error) if no binary can be found, so the caller aborts rather
        than launching a container with no entrypoint.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS
    )

    # Dev override wins: a host-built binary for fast local iteration.
    $override = $env:DCLAUDE_ENTRYPOINT_SRC
    if ($override) {
        if (Test-Path $override) {
            Write-Debug "dclaude: using DCLAUDE_ENTRYPOINT_SRC override: $override"
            return $override
        }
        Write-Warning "DCLAUDE_ENTRYPOINT_SRC '$override' not found; falling back to the bundled binary."
    }

    # Container arch tracks the host arch for non-emulated Docker Desktop containers.
    $arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        'Arm64' { 'arm64' }
        default { 'amd64' }
    }
    $ext = if ($ContainerOS -eq 'windows') { '.exe' } else { '' }
    $name = "dclaude-entrypoint-$ContainerOS-$arch$ext"

    # bin/ is a sibling of Private/ in both the repo (launchers/powershell/) and installed module.
    $binDir = Join-Path (Split-Path $PSScriptRoot) 'bin'
    $path = Join-Path $binDir $name
    Write-Debug "dclaude: resolving bundled entrypoint binary: $path"
    if (-not (Test-Path $path)) {
        Write-Error "Bundled entrypoint binary not found: $path. The module package is missing its binaries for $ContainerOS/$arch."
        return $null
    }
    return $path
}
