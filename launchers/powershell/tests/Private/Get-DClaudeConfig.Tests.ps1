BeforeAll {
    . "$PSScriptRoot/../../Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../Private/Get-DClaudeConfig.ps1"
}

Describe 'Get-DClaudeConfig' {

    Context 'when .dclaude folder exists in the given path' {
        BeforeEach {
            $projectDir = Join-Path $TestDrive 'project'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'pwsh' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')
        }

        It 'returns the config from that directory' {
            $result = Get-DClaudeConfig -Path $projectDir
            $result.imageKey | Should -Be 'pwsh'
        }
    }

    Context 'when .dclaude folder exists in a parent directory' {
        BeforeEach {
            $rootDir = Join-Path $TestDrive 'repo'
            $childDir = Join-Path $rootDir 'src/components'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $configDir = Join-Path $rootDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'root-image' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')
        }

        It 'walks up the directory tree and finds it' {
            $result = Get-DClaudeConfig -Path $childDir
            $result.imageKey | Should -Be 'root-image'
        }
    }

    Context 'when .dclaude folders exist at multiple levels' {
        It 'returns only the nearest config' {
            $rootDir = Join-Path $TestDrive 'multi-nearest'
            $childDir = Join-Path $rootDir 'packages/app'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'root-image' } | ConvertTo-Json |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'child-image' } | ConvertTo-Json |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Get-DClaudeConfig -Path $childDir
            $result.defaultImageKey | Should -Be 'child-image'
            $result.PSObject.Properties.Name | Should -Not -Contain 'envPassthrough'
        }
    }

    Context 'when no .dclaude folder exists' {
        It 'returns null' {
            $emptyDir = Join-Path $TestDrive 'empty'
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            # $TestDrive lives under the real user profile; without this the walk-up
            # would discover the developer's real ~/.dclaude and return its config
            # instead of $null.
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*.dclaude' }

            $result = Get-DClaudeConfig -Path $emptyDir
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when .dclaude folder exists but is empty (no settings files)' {
        BeforeEach {
            $projectDir = Join-Path $TestDrive 'project'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        }

        It 'returns null (Merge-SettingsFiles returns null for empty dir)' {
            $result = Get-DClaudeConfig -Path $projectDir
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'config merging integration' {
        BeforeEach {
            $projectDir = Join-Path $TestDrive 'project'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        }

        It 'merges settings.json and settings.local.json' {
            @{ imageKey = 'pwsh'; someBase = 'value' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')
            @{ imageKey = 'custom' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.local.json')

            $result = Get-DClaudeConfig -Path $projectDir
            $result.imageKey | Should -Be 'custom'
            $result.someBase | Should -Be 'value'
        }
    }
}
