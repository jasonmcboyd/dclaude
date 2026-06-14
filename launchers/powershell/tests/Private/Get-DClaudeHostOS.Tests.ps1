BeforeAll {
    . "$PSScriptRoot/../../Private/Get-DClaudeHostOS.ps1"
}

Describe 'Get-DClaudeHostOS' {
    It 'returns a known host OS value' {
        Get-DClaudeHostOS | Should -BeIn @('windows', 'linux', 'macos')
    }

    It 'returns windows on a Windows host' {
        # The suite runs on Windows; both PowerShell 7 ($IsWindows) and 5.1 (no $IsWindows)
        # resolve to 'windows'.
        Get-DClaudeHostOS | Should -Be 'windows'
    }
}
