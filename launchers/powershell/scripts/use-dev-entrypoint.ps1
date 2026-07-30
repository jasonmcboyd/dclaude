<#
.SYNOPSIS
    Build the Go entrypoint binary from this working tree and run dclaude against it (dev convenience).

.DESCRIPTION
    Detects the active Docker container mode (Linux or Windows), builds the matching entrypoint
    binary, points dclaude at it via DCLAUDE_ENTRYPOINT_SRC, and imports the module from this repo.
    The launcher mounts the host binary directly at run time (see Get-DClaudeEntrypointBinary /
    Invoke-DClaude), so a rebuilt binary takes effect on the next launch without touching the
    runtime volume or disturbing other running instances. Without DCLAUDE_ENTRYPOINT_SRC, dclaude
    uses the binary bundled in the module's bin/ — this script just overrides that with a fresh
    local build for fast iteration.

    Dot-source it to configure your current shell (env vars + alias persist), or run it for a
    one-shot build-configure-launch in this process.

.EXAMPLE
    . ./launchers/powershell/scripts/use-dev-entrypoint.ps1 -Build
    dclaude
    # Configures this shell (env persists), then you run dclaude yourself.

.EXAMPLE
    ./launchers/powershell/scripts/use-dev-entrypoint.ps1 -Build
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
        # CGO_ENABLED=0 so the dev binary is statically linked, matching the CI/production build.
        $env:GOOS = $containerOS
        $env:GOARCH = 'amd64'
        $env:CGO_ENABLED = '0'
        go build -trimpath -ldflags '-s -w -X main.version=dev' -o $binary .
        if ($LASTEXITCODE -ne 0) { throw 'go build failed.' }
    }
    finally {
        Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED -ErrorAction SilentlyContinue
        Pop-Location
    }
    Write-Host "[dev] Built $binary" -ForegroundColor Green
    # The launcher mounts this binary directly via DCLAUDE_ENTRYPOINT_SRC, so the rebuild takes
    # effect on the next launch with the runtime volume left untouched.
}

$env:DCLAUDE_ENTRYPOINT_SRC = $binary
Import-Module $manifest -Force

Write-Host "[dev] Dev entrypoint binary in use ($containerOS, binary: $binary)" -ForegroundColor Green

if ($dotSourced) {
    Write-Host '[dev] Shell configured. Run:  dclaude' -ForegroundColor Green
    Write-Host '[dev] To stop using the dev binary:  $env:DCLAUDE_ENTRYPOINT_SRC = $null  (falls back to the module bin/)' -ForegroundColor DarkGray
}
else {
    Write-Warning 'Not dot-sourced: these env vars will not persist after this script exits.'
    Write-Host '[dev] Launching dclaude in this process...' -ForegroundColor Cyan
    Invoke-DClaude -ClaudeArgs $DClaudeArgs
}
