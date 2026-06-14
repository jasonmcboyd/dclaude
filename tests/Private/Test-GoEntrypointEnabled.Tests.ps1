BeforeAll {
    . "$PSScriptRoot/../../src/Private/Test-GoEntrypointEnabled.ps1"
}

Describe 'Test-GoEntrypointEnabled' {

    AfterEach { $env:DCLAUDE_USE_GO_ENTRYPOINT = $null }

    It 'is false when the variable is unset' {
        $env:DCLAUDE_USE_GO_ENTRYPOINT = $null
        Test-GoEntrypointEnabled | Should -BeFalse
    }

    It 'is false for empty or whitespace' {
        $env:DCLAUDE_USE_GO_ENTRYPOINT = '   '
        Test-GoEntrypointEnabled | Should -BeFalse
    }

    It "is false for explicit falsey values" -ForEach @('0', 'false', 'no', 'off', 'OFF', 'False') {
        $env:DCLAUDE_USE_GO_ENTRYPOINT = $_
        Test-GoEntrypointEnabled | Should -BeFalse
    }

    It "is true for truthy values" -ForEach @('1', 'true', 'yes', 'on', 'anything') {
        $env:DCLAUDE_USE_GO_ENTRYPOINT = $_
        Test-GoEntrypointEnabled | Should -BeTrue
    }
}
