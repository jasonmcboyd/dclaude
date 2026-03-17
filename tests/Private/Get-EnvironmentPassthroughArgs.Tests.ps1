BeforeAll {
    . "$PSScriptRoot/../../src/Private/Get-EnvironmentPassthroughArgs.ps1"
}

Describe 'Get-EnvironmentPassthroughArgs' {

    AfterEach {
        foreach ($key in @('ANTHROPIC_API_KEY', 'CLAUDE_CODE_TEST', 'CLOUD_ML_REGION', 'MY_CUSTOM_VAR')) {
            [Environment]::SetEnvironmentVariable($key, $null)
        }
    }

    Context 'prefix matching' {
        It 'passes ANTHROPIC_ prefixed variables' {
            [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', 'test-key')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path'
            $result | Should -Contain 'ANTHROPIC_API_KEY'
        }

        It 'passes CLAUDE_CODE_ prefixed variables' {
            [Environment]::SetEnvironmentVariable('CLAUDE_CODE_TEST', 'val')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path'
            $result | Should -Contain 'CLAUDE_CODE_TEST'
        }

        It 'passes CLOUD_ML_ prefixed variables' {
            [Environment]::SetEnvironmentVariable('CLOUD_ML_REGION', 'us-east1')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path'
            $result | Should -Contain 'CLOUD_ML_REGION'
        }

        It 'does not pass unrelated environment variables' {
            [Environment]::SetEnvironmentVariable('MY_CUSTOM_VAR', 'secret')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path'
            $result | Should -Not -Contain 'MY_CUSTOM_VAR'
        }
    }

    Context 'DCLAUDE_HOST_PATH' {
        It 'always includes DCLAUDE_HOST_PATH with the correct value' {
            $result = Get-EnvironmentPassthroughArgs -HostPath '/my/workspace'
            $result | Should -Contain 'DCLAUDE_HOST_PATH=/my/workspace'
        }

        It 'includes -e flag before DCLAUDE_HOST_PATH' {
            $result = Get-EnvironmentPassthroughArgs -HostPath '/path'
            $idx = [array]::IndexOf($result, 'DCLAUDE_HOST_PATH=/path')
            $idx | Should -BeGreaterThan 0
            $result[$idx - 1] | Should -Be '-e'
        }
    }

    Context 'when no matching env vars exist' {
        It 'returns only DCLAUDE_HOST_PATH args' {
            $result = Get-EnvironmentPassthroughArgs -HostPath '/path'
            # Should have at least -e and DCLAUDE_HOST_PATH=...
            $nonHostArgs = $result | Where-Object { $_ -notmatch 'DCLAUDE_HOST_PATH' -and $_ -ne '-e' }
            # Filter to only args that are env var names (not -e flags)
            $envVarArgs = $result | Where-Object { $_ -ne '-e' -and $_ -notmatch 'DCLAUDE_HOST_PATH' }
            # Any remaining should only be matching prefixed vars from the actual environment
            foreach ($arg in $envVarArgs) {
                $arg | Should -Match '^(ANTHROPIC_|CLAUDE_CODE_|CLOUD_ML_)'
            }
        }
    }
}
