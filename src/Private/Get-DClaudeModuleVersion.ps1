function Get-DClaudeModuleVersion {
    <#
    .SYNOPSIS
        Resolves the dclaude module version used for runtime volume naming.
    .DESCRIPTION
        Prefers the loaded module's version. Falls back to reading ModuleVersion from
        dclaude.psd1 (for dot-sourced use outside a loaded module), and finally to 0.0.0.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param()

    $version = $MyInvocation.MyCommand.Module.Version
    if ($version) { return $version }

    # Fallback: read from .psd1 when running outside a loaded module (e.g. dot-sourced).
    # This file lives in src/Private/, the manifest lives in src/.
    $psdPath = Join-Path (Split-Path $PSScriptRoot) 'dclaude.psd1'
    if (Test-Path $psdPath) {
        return [version](Import-PowerShellDataFile $psdPath).ModuleVersion
    }

    return [version]'0.0.0'
}
