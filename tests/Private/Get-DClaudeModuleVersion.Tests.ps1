BeforeAll {
    . "$PSScriptRoot/../../src/Private/Get-DClaudeModuleVersion.ps1"

    # The real manifest version, used to assert the psd1 fallback path.
    $script:manifestVersion = [version](Import-PowerShellDataFile "$PSScriptRoot/../../src/dclaude.psd1").ModuleVersion
}

Describe 'Get-DClaudeModuleVersion' {

    Context 'psd1 fallback (dot-sourced, no loaded module)' {
        It 'reads ModuleVersion from src/dclaude.psd1' {
            # When dot-sourced, $MyInvocation.MyCommand.Module.Version is null, so the
            # function falls back to reading the manifest relative to its own location.
            $result = Get-DClaudeModuleVersion

            $result | Should -BeOfType ([version])
            $result | Should -Be $script:manifestVersion
        }
    }

    Context 'final 0.0.0 fallback' {
        It 'returns 0.0.0 when the manifest cannot be found' {
            Mock Test-Path { return $false }

            Get-DClaudeModuleVersion | Should -Be ([version]'0.0.0')
        }
    }
}
