param(
    [Parameter(Mandatory)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Strip leading 'v' and split on '-' to extract version and optional prerelease
$versionString = $Version -replace '^v', ''
$parts = $versionString -split '-', 2
$moduleVersion = $parts[0]
$prerelease = if ($parts.Length -gt 1) { $parts[1] } else { $null }

Write-Host "Module version: $moduleVersion"
Write-Host "Prerelease: $($prerelease ?? '(none)')"

# Create publish directory and copy module files. The module root is the parent of this
# scripts/ directory (launchers/powershell). Only the shippable parts are copied — not
# tests/ or scripts/.
$moduleRoot = Split-Path $PSScriptRoot
$publishDir = './publish/dclaude'
New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
Copy-Item -Path (Join-Path $moduleRoot 'Public') -Destination $publishDir -Recurse -Force
Copy-Item -Path (Join-Path $moduleRoot 'Private') -Destination $publishDir -Recurse -Force
Copy-Item -Path (Join-Path $moduleRoot 'dclaude.psm1') -Destination $publishDir -Force

# Bundle the SQL MCP sidecar (Dockerfiles + server code). The sidecar lives at the repo root
# under sidecars/; copy it into the module so Start-SqlMcpSidecar can find it at install time.
$repoRoot = Split-Path (Split-Path $moduleRoot)
$sidecarsDir = Join-Path $repoRoot 'sidecars'
if (Test-Path $sidecarsDir) {
    Copy-Item -Path $sidecarsDir -Destination $publishDir -Recurse -Force
}

# Bundle the Go entrypoint binaries (built into bin/ before packaging — by CI or the local
# deploy-test harness). They are mounted into the container at launch, so the module is
# non-functional without them: fail loudly rather than ship a broken package.
$binDir = Join-Path $moduleRoot 'bin'
if (-not (Test-Path $binDir) -or -not (Get-ChildItem -Path $binDir -File -ErrorAction SilentlyContinue)) {
    throw "Entrypoint binaries not found in '$binDir'. Build them before packaging (CI build step, or scripts/test-package-deploy.ps1)."
}
Copy-Item -Path $binDir -Destination $publishDir -Recurse -Force

# Build New-ModuleManifest parameters
$manifestParams = @{
    Path              = "$publishDir/dclaude.psd1"
    RootModule        = 'dclaude.psm1'
    ModuleVersion     = $moduleVersion
    GUID              = '3a624731-85ed-4119-ac0b-b31add03fe23'
    Author            = 'Jason Boyd'
    CompanyName       = 'Jason Boyd'
    Copyright         = '(c) Jason Boyd. All rights reserved.'
    Description       = 'Launch Docker containers with Claude Code pre-installed for isolated development environments.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Add-DClaudeEnvPassthrough'
        'Add-DClaudeImage'
        'Add-DClaudeVolume'
        'Get-DClaudeDefaultImageKey'
        'Get-DClaudeEnvPassthrough'
        'Get-DClaudeImage'
        'Get-DClaudeVolume'
        'Initialize-DClaudeWindowsContainers'
        'Invoke-DClaude'
        'Remove-DClaudeEnvPassthrough'
        'Remove-DClaudeImage'
        'Remove-DClaudeVolume'
        'Resolve-DClaudeConfig'
        'Set-DClaudeDefaultImageKey'
        'Update-DClaudeRuntime'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('dclaude')
    Tags              = @('Docker', 'Claude', 'AI', 'Development', 'Container')
    LicenseUri        = 'https://raw.githubusercontent.com/jasonmcboyd/dclaude/main/LICENSE'
    ProjectUri        = 'https://github.com/jasonmcboyd/dclaude'
}

if ($prerelease) {
    $manifestParams['Prerelease'] = $prerelease
}

New-ModuleManifest @manifestParams

Write-Host "Module manifest created at $publishDir/dclaude.psd1"
