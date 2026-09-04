<#
.SYNOPSIS
    Build the module package (with bundled Go binaries) and install it from a LOCAL PowerShell
    repository, to validate the real deploy experience before publishing to PSGallery.

.DESCRIPTION
    Mirrors what CI does on a tag, but entirely locally and isolated:
      1. Builds the Go entrypoint binaries into launchers/powershell/bin/ (amd64; -AllArch adds arm64).
      2. Runs create-module-manifest.ps1 to assemble ./publish/dclaude (bundling bin/).
      3. Publishes that package to a local file-based PSRepository.
      4. Saves it into an ISOLATED module path (your normal module locations are untouched).

    Dot-source it to point the current shell at the installed copy with DCLAUDE_ENTRYPOINT_SRC
    UNSET, so a subsequent `dclaude` exercises the bundled binary exactly as an end user would:
      . ./launchers/powershell/scripts/test-package-deploy.ps1
      dclaude

.PARAMETER Version
    Module version to package. Defaults to the version in dclaude.psd1.

.PARAMETER AllArch
    Also build arm64 binaries (default: amd64 only, for speed).
#>
[CmdletBinding()]
param(
    [string]$Version,
    [switch]$AllArch
)

$ErrorActionPreference = 'Stop'
$dotSourced = $MyInvocation.InvocationName -eq '.'

$moduleRoot    = Split-Path $PSScriptRoot
$repoRoot      = Split-Path (Split-Path $moduleRoot)
$entrypointDir = Join-Path $repoRoot 'entrypoint'
$binDir        = Join-Path $moduleRoot 'bin'

if (-not $Version) {
    $Version = (Import-PowerShellDataFile (Join-Path $moduleRoot 'dclaude.psd1')).ModuleVersion
}
$tag = "v$Version"
Write-Host "[pkg] packaging dclaude $tag" -ForegroundColor Cyan

# 1. Build the entrypoint binaries into the module's bin/ (same layout CI ships).
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw "Go is not on PATH (e.g. 'choco install golang'). Cannot build the entrypoint binaries."
}
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
$targets = @('linux/amd64', 'windows/amd64')
if ($AllArch) { $targets += @('linux/arm64', 'windows/arm64') }
Push-Location $entrypointDir
try {
    foreach ($t in $targets) {
        $parts = $t -split '/'
        $os = $parts[0]; $arch = $parts[1]
        $ext = if ($os -eq 'windows') { '.bin' } else { '' }
        $out = Join-Path $binDir "dclaude-entrypoint-$os-$arch$ext"
        # CGO_ENABLED=0 to match CI exactly: a static binary, so the gate tests what ships.
        $env:GOOS = $os; $env:GOARCH = $arch; $env:CGO_ENABLED = '0'
        Write-Host "[pkg] building $out" -ForegroundColor DarkGray
        go build -trimpath -ldflags "-s -w -X main.version=$tag" -o $out .
        if ($LASTEXITCODE -ne 0) { throw "go build failed for $t" }
        if ($os -eq 'windows') {
            $gzPath = "$out.gz"
            Write-Host "[pkg] gzipping $out -> $gzPath" -ForegroundColor DarkGray
            $fsIn = [IO.File]::OpenRead($out)
            $fsOut = [IO.File]::Create($gzPath)
            $gz = [IO.Compression.GZipStream]::new($fsOut, [IO.Compression.CompressionMode]::Compress)
            try { $fsIn.CopyTo($gz) }
            finally { $gz.Dispose(); $fsOut.Dispose(); $fsIn.Dispose() }
            Remove-Item $out -Force
        }
    }
}
finally {
    Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED -ErrorAction SilentlyContinue
    Pop-Location
}

# 2. Assemble the publishable module (fails if bin/ is empty; bundles it otherwise).
Push-Location $repoRoot
try {
    if (Test-Path ./publish) { Remove-Item ./publish -Recurse -Force }
    & (Join-Path $moduleRoot 'scripts/create-module-manifest.ps1') -Version $tag
}
finally { Pop-Location }
$packageDir = Join-Path $repoRoot 'publish/dclaude'

# 3. Publish to a local file-based repository and 4. Save into an isolated path.
$repoName     = 'dclaude-localtest'
$testRoot     = Join-Path $env:LOCALAPPDATA 'dclaude\test-deploy'
$localRepoDir = Join-Path $testRoot 'localrepo'
$installRoot  = Join-Path $testRoot 'modules'
New-Item -ItemType Directory -Path $localRepoDir, $installRoot -Force | Out-Null

if (Get-PSRepository -Name $repoName -ErrorAction SilentlyContinue) {
    Unregister-PSRepository -Name $repoName
}
Register-PSRepository -Name $repoName -SourceLocation $localRepoDir -InstallationPolicy Trusted
try {
    Get-ChildItem $localRepoDir -Filter 'dclaude*.nupkg' -ErrorAction SilentlyContinue | Remove-Item -Force
    Write-Host "[pkg] publishing to local repo: $localRepoDir" -ForegroundColor DarkGray
    Publish-Module -Path $packageDir -Repository $repoName

    if (Test-Path (Join-Path $installRoot 'dclaude')) {
        Remove-Item (Join-Path $installRoot 'dclaude') -Recurse -Force
    }
    Write-Host "[pkg] saving installed copy to: $installRoot" -ForegroundColor DarkGray
    Save-Module -Name dclaude -Repository $repoName -Path $installRoot -Force
}
finally {
    Unregister-PSRepository -Name $repoName -ErrorAction SilentlyContinue
}

$installed = Join-Path $installRoot "dclaude\$Version"
$bundled = @(Get-ChildItem (Join-Path $installed 'bin') -ErrorAction SilentlyContinue)
Write-Host "[pkg] installed package: $installed" -ForegroundColor Green
Write-Host "[pkg] bundled binaries:  $($bundled.Count)" -ForegroundColor Green
$bundled | ForEach-Object { Write-Host "        $($_.Name)" -ForegroundColor DarkGray }
if ($bundled.Count -eq 0) { throw "Installed package has no bundled binaries -- packaging is broken." }

if ($dotSourced) {
    # Exercise the BUNDLED binary (no dev override) from the INSTALLED package.
    $env:DCLAUDE_ENTRYPOINT_SRC = $null
    if ($env:PSModulePath -notlike "*$installRoot*") {
        $env:PSModulePath = "$installRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"
    }
    Remove-Module dclaude -ErrorAction SilentlyContinue
    Import-Module (Join-Path $installed 'dclaude.psd1') -Force
    Write-Host ''
    Write-Host '[pkg] Shell configured to the INSTALLED package (bundled binary, no dev override).' -ForegroundColor Green
    Write-Host '[pkg] Run:  dclaude     # provisions a fresh runtime volume + mounts the bundled binary' -ForegroundColor Green
    Write-Host '[pkg] Done? Open a new shell to drop the test module from PSModulePath.' -ForegroundColor DarkGray
}
else {
    Write-Host ''
    Write-Host '[pkg] Dot-source this script so it can configure your shell for the test:' -ForegroundColor Yellow
    Write-Host '        . ./launchers/powershell/scripts/test-package-deploy.ps1' -ForegroundColor Yellow
    Write-Host '        dclaude' -ForegroundColor Yellow
}
