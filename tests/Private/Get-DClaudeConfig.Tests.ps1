BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeConfig.ps1"
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
        BeforeEach {
            $rootDir = Join-Path $TestDrive 'repo'
            $childDir = Join-Path $rootDir 'packages/app'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            # Parent config
            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ imageKey = 'root-image' } | ConvertTo-Json |
                Set-Content (Join-Path $rootConfig 'settings.json')

            # Child config (closer to the starting path)
            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ imageKey = 'child-image' } | ConvertTo-Json |
                Set-Content (Join-Path $childConfig 'settings.json')
        }

        It 'returns the closest config (first found walking up)' {
            $result = Get-DClaudeConfig -Path $childDir
            $result.imageKey | Should -Be 'child-image'
        }
    }

    Context 'when no .dclaude folder exists' {
        It 'returns null' {
            $emptyDir = Join-Path $TestDrive 'empty'
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

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
