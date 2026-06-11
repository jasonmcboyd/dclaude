BeforeAll {
    . "$PSScriptRoot/../../src/Private/Get-EnvironmentPassthroughArgs.ps1"
}

Describe 'Get-EnvironmentPassthroughArgs' {

    AfterEach {
        foreach ($key in @('ANTHROPIC_API_KEY', 'CLAUDE_CODE_TEST', 'CLOUD_ML_REGION',
                'AZURE_DEVOPS_PAT', 'NUGET_TOKEN', 'MY_CUSTOM_VAR')) {
            [Environment]::SetEnvironmentVariable($key, $null)
        }
    }

    Context 'built-in patterns' {
        It 'always passes ANTHROPIC_ prefixed variables' {
            [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', 'test-key')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path'
            $result | Should -Contain 'ANTHROPIC_API_KEY'
        }

        It 'always passes CLAUDE_CODE_ prefixed variables' {
            [Environment]::SetEnvironmentVariable('CLAUDE_CODE_TEST', 'val')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path'
            $result | Should -Contain 'CLAUDE_CODE_TEST'
        }

        It 'always passes CLOUD_ML_ prefixed variables' {
            [Environment]::SetEnvironmentVariable('CLOUD_ML_REGION', 'us-east1')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path'
            $result | Should -Contain 'CLOUD_ML_REGION'
        }

        It 'does not pass unmatched variables without patterns' {
            [Environment]::SetEnvironmentVariable('MY_CUSTOM_VAR', 'secret')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path'
            $result | Should -Not -Contain 'MY_CUSTOM_VAR'
        }
    }

    Context 'custom patterns' {
        It 'passes exact name match' {
            [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PAT', 'test-pat')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path' -Patterns @('AZURE_DEVOPS_PAT')
            $result | Should -Contain 'AZURE_DEVOPS_PAT'
        }

        It 'passes glob pattern match' {
            [Environment]::SetEnvironmentVariable('NUGET_TOKEN', 'abc')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path' -Patterns @('NUGET_*')
            $result | Should -Contain 'NUGET_TOKEN'
        }

        It 'does not pass vars that do not match patterns' {
            [Environment]::SetEnvironmentVariable('MY_CUSTOM_VAR', 'secret')

            $result = Get-EnvironmentPassthroughArgs -HostPath '/some/path' -Patterns @('NUGET_*')
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

    Context 'always includes DCLAUDE_HOST_PATH' {
        It 'includes DCLAUDE_HOST_PATH even with no other user vars' {
            $result = Get-EnvironmentPassthroughArgs -HostPath '/path'
            $result | Should -Contain 'DCLAUDE_HOST_PATH=/path'
        }
    }
}
