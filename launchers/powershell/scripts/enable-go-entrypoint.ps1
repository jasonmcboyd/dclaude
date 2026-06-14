<#
.SYNOPSIS
    Enable and run the Go container entrypoint from this working tree (dev convenience).

.DESCRIPTION
    Detects the active Docker container mode (Linux or Windows), builds the matching
    entrypoint binary, points dclaude at it via DCLAUDE_ENTRYPOINT_SRC, turns on
    DCLAUDE_USE_GO_ENTRYPOINT, and imports the module from this repo. The launcher mounts the
    host binary directly at run time (see Invoke-DClaude's DCLAUDE_ENTRYPOINT_SRC handling), so a
    rebuilt binary takes effect on the next launch without touching the (immutable, read-only)
    runtime volume or disturbing other running instances.

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
    Rebuild the entrypoint binary for the active Docker mode (requires Go on PATH). Implied when
    the binary doesn't exist yet. The launcher mounts the rebuilt binary directly, so no volume
    refresh is needed.

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

# Match the active Docker mode so we build and inject the right OS binary.
$containerOS = "$(docker info --format '{{.OSType}}' 2>$null)".Trim().ToLower()
if (-not $containerOS) {
    throw 'Docker is not responding. Is Docker Desktop running?'
}
if ($containerOS -notin @('linux', 'windows')) {
    throw "Unsupported Docker container mode: $containerOS"
}

$binaryName = if ($containerOS -eq 'windows') { 'dclaude-entrypoint.exe' } else { 'dclaude-entrypoint' }
$binary     = Join-Path $entrypointDir $binaryName

if ($Build -or -not (Test-Path $binary)) {
    if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
        throw "Go is not on PATH (e.g. 'choco install golang'). Cannot build the entrypoint binary."
    }

    Write-Host "[dev] Building $containerOS/amd64 entrypoint binary..." -ForegroundColor Cyan
    Push-Location $entrypointDir
    try {
        $env:GOOS = $containerOS
        $env:GOARCH = 'amd64'
        go build -trimpath -ldflags '-s -w -X main.version=dev' -o $binary .
        if ($LASTEXITCODE -ne 0) { throw 'go build failed.' }
    }
    finally {
        Remove-Item Env:GOOS, Env:GOARCH -ErrorAction SilentlyContinue
        Pop-Location
    }
    Write-Host "[dev] Built $binary" -ForegroundColor Green
    # No volume swap: the launcher mounts this binary directly via DCLAUDE_ENTRYPOINT_SRC, so the
    # rebuild takes effect on the next launch with the runtime volume left untouched.
}

$env:DCLAUDE_USE_GO_ENTRYPOINT = '1'
$env:DCLAUDE_ENTRYPOINT_SRC = $binary
Import-Module $manifest -Force

Write-Host "[dev] Go entrypoint ENABLED ($containerOS, binary: $binary)" -ForegroundColor Green

if ($dotSourced) {
    Write-Host '[dev] Shell configured. Run:  dclaude' -ForegroundColor Green
    Write-Host '[dev] To disable:  $env:DCLAUDE_USE_GO_ENTRYPOINT = $null  (or open a new shell)' -ForegroundColor DarkGray
}
else {
    Write-Warning 'Not dot-sourced: these env vars will not persist after this script exits.'
    Write-Host '[dev] Launching dclaude in this process...' -ForegroundColor Cyan
    Invoke-DClaude -ClaudeArgs $DClaudeArgs
}
