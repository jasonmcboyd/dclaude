<#
.SYNOPSIS
    Enable and run the Go container entrypoint from this working tree (dev convenience).

.DESCRIPTION
    Builds the Linux entrypoint binary (when needed), points dclaude at it via
    DCLAUDE_ENTRYPOINT_SRC, turns on DCLAUDE_USE_GO_ENTRYPOINT, and imports the module from
    this repo. With -Build it also swaps the fresh binary into any existing Linux runtime
    volume, so a rebuild takes effect immediately without a full re-provision (node/claude
    are not re-downloaded).

    Dot-source it to configure your current shell (env vars + alias persist), or run it for a
    one-shot build-configure-launch in this process.

.EXAMPLE
    . ./launchers/powershell/scripts/enable-go-entrypoint.ps1 -Build
    dclaude
    # Configures this shell (env persists), then you run dclaude yourself.

.EXAMPLE
    ./launchers/powershell/scripts/enable-go-entrypoint.ps1 -Build
    # One-shot: build, configure, and launch dclaude in this process.

.PARAMETER Build
    Rebuild the Linux binary (requires Go on PATH) and refresh it into existing Linux runtime
    volumes. Implied automatically when the binary doesn't exist yet.

.PARAMETER DClaudeArgs
    Extra arguments forwarded to claude when this script launches dclaude (run, not dot-sourced).
#>
[CmdletBinding()]
param(
    [switch]$Build,

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$DClaudeArgs
)

$ErrorActionPreference = 'Stop'
$dotSourced = $MyInvocation.InvocationName -eq '.'

$moduleRoot    = Split-Path $PSScriptRoot                # launchers/powershell
$repoRoot      = Split-Path (Split-Path $moduleRoot)     # repo root
$manifest      = Join-Path $moduleRoot 'dclaude.psd1'
$entrypointDir = Join-Path $repoRoot 'entrypoint'
$binary        = Join-Path $entrypointDir 'dclaude-entrypoint'

if ($Build -or -not (Test-Path $binary)) {
    if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
        throw "Go is not on PATH (e.g. 'choco install golang'). Cannot build the entrypoint binary."
    }

    Write-Host '[dev] Building Linux entrypoint binary...' -ForegroundColor Cyan
    Push-Location $entrypointDir
    try {
        $env:GOOS = 'linux'
        $env:GOARCH = 'amd64'
        go build -trimpath -ldflags '-s -w -X main.version=dev' -o $binary .
        if ($LASTEXITCODE -ne 0) { throw 'go build failed.' }
    }
    finally {
        Remove-Item Env:GOOS, Env:GOARCH -ErrorAction SilentlyContinue
        Pop-Location
    }
    Write-Host "[dev] Built $binary" -ForegroundColor Green

    # Swap the fresh binary into existing Linux runtime volumes (fast: just a file copy, no
    # node/claude re-download). First-run volumes don't exist yet; provisioning injects the
    # binary via DCLAUDE_ENTRYPOINT_SRC.
    $vols = docker volume ls --filter 'name=dclaude-runtime-linux-' --format '{{.Name}}' 2>$null
    foreach ($vol in @($vols | Where-Object { $_ })) {
        Write-Host "[dev] Refreshing binary in volume $vol" -ForegroundColor DarkGray
        docker run --rm -v "${vol}:/out" -v "${binary}:/in/dclaude-entrypoint:ro" alpine `
            sh -c 'mkdir -p /out/bin && cp /in/dclaude-entrypoint /out/bin/dclaude-entrypoint && chmod +x /out/bin/dclaude-entrypoint' | Out-Null
    }
}

$env:DCLAUDE_USE_GO_ENTRYPOINT = '1'
$env:DCLAUDE_ENTRYPOINT_SRC = $binary
Import-Module $manifest -Force

Write-Host "[dev] Go entrypoint ENABLED (binary: $binary)" -ForegroundColor Green

if ($dotSourced) {
    Write-Host '[dev] Shell configured. Run:  dclaude' -ForegroundColor Green
    Write-Host '[dev] To disable:  $env:DCLAUDE_USE_GO_ENTRYPOINT = $null  (or open a new shell)' -ForegroundColor DarkGray
}
else {
    Write-Warning 'Not dot-sourced: these env vars will not persist after this script exits.'
    Write-Host '[dev] Launching dclaude in this process...' -ForegroundColor Cyan
    Invoke-DClaude -ClaudeArgs $DClaudeArgs
}
