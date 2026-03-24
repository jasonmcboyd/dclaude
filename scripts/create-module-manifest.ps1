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

# Create publish directory and copy module files
$publishDir = './publish/dclaude'
New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
Copy-Item -Path './src/*' -Destination $publishDir -Recurse -Force
Copy-Item -Path './Entrypoints' -Destination $publishDir -Recurse -Force

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
        'Add-DClaudeImage'
        'Get-DClaudeImage'
        'Get-DClaudeProject'
        'Initialize-DClaudeWindowsContainers'
        'Invoke-DClaude'
        'Remove-DClaudeImage'
        'Set-DClaudeProject'
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
