<#
.SYNOPSIS
    Enable and run the Go container entrypoint from this working tree (dev convenience).

.DESCRIPTION
    Detects the active Docker container mode (Linux or Windows), builds the matching
    entrypoint binary, points dclaude at it via DCLAUDE_ENTRYPOINT_SRC, turns on
    DCLAUDE_USE_GO_ENTRYPOINT, and imports the module from this repo. With -Build it also
    hot-swaps the fresh binary into existing runtime volumes for that OS, so a rebuild takes
    effect without a full re-provision.

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
    Rebuild the entrypoint binary for the active Docker mode (requires Go on PATH) and refresh
    it into existing runtime volumes for that OS. Implied when the binary doesn't exist yet.

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

    # Hot-swap the fresh binary into existing runtime volumes for this OS (just a file copy, no
    # node/claude re-download). First-run volumes don't exist yet; provisioning injects the
    # binary via DCLAUDE_ENTRYPOINT_SRC.
    $vols = docker volume ls --filter "name=dclaude-runtime-$containerOS-" --format '{{.Name}}' 2>$null
    foreach ($vol in @($vols | Where-Object { $_ })) {
        Write-Host "[dev] Refreshing binary in volume $vol" -ForegroundColor DarkGray
        if ($containerOS -eq 'linux') {
            docker run --rm -v "${vol}:/out" -v "${binary}:/in/dclaude-entrypoint:ro" alpine `
                sh -c 'mkdir -p /out/bin && cp /in/dclaude-entrypoint /out/bin/dclaude-entrypoint && chmod +x /out/bin/dclaude-entrypoint' | Out-Null
        }
        else {
            # Windows can't mount a single file, so mount the binary's directory and copy the
            # exe. Use servercore (the provisioning identity) to avoid nanoserver's restrictive
            # volume ACLs.
            docker run --rm -v "${vol}:C:\out" -v "${entrypointDir}:C:\in:ro" mcr.microsoft.com/windows/servercore:ltsc2022 `
                cmd /c "if not exist C:\out\bin mkdir C:\out\bin & copy /Y C:\in\$binaryName C:\out\bin\dclaude-entrypoint.exe" | Out-Null
        }
    }
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
