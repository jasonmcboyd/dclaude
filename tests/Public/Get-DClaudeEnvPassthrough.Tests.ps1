BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../src/Public/Get-DClaudeEnvPassthrough.ps1"
}

Describe 'Get-DClaudeEnvPassthrough' {

    Context 'when envPassthrough is set' {
        It 'returns the patterns' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }
            @{ envPassthrough = @('NUGET_*', 'AZURE_*') } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeEnvPassthrough -Scope User
            $result | Should -HaveCount 2
            $result | Should -Contain 'NUGET_*'
        }
    }

    Context 'when envPassthrough is not set' {
        It 'returns empty array' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }
            @{ defaultImageKey = 'pwsh' } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeEnvPassthrough -Scope User
            $result | Should -HaveCount 0
        }
    }

    Context 'when no config exists' {
        It 'returns empty array' {
            $emptyDir = Join-Path $TestDrive 'empty'
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $emptyDir; FileName = 'settings.json' }
            }

            $result = Get-DClaudeEnvPassthrough -Scope User
            $result | Should -HaveCount 0
        }
    }

    Context 'when local override has envPassthrough' {
        It 'returns the local override value' {
            $dir = Join-Path $TestDrive 'merged'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            @{ envPassthrough = @('BASE_*') } | ConvertTo-Json | Set-Content "$dir/settings.json"
            @{ envPassthrough = @('LOCAL_*') } | ConvertTo-Json | Set-Content "$dir/settings.local.json"

            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $dir; FileName = 'settings.json' }
            }

            $result = Get-DClaudeEnvPassthrough -Scope Project
            $result | Should -HaveCount 1
            $result[0] | Should -Be 'LOCAL_*'
        }
    }
}
