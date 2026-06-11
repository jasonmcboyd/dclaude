BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../src/Public/Get-DClaudeDefaultImageKey.ps1"
}

Describe 'Get-DClaudeDefaultImageKey' {

    Context 'when defaultImageKey is set' {
        It 'returns the value' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{
                    Directory = $TestDrive
                    FileName  = 'settings.json'
                }
            }
            @{ defaultImageKey = 'pwsh' } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeDefaultImageKey -Scope User
            $result | Should -Be 'pwsh'
        }
    }

    Context 'when defaultImageKey is not set' {
        It 'returns null' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{
                    Directory = $TestDrive
                    FileName  = 'settings.json'
                }
            }
            @{ volumes = @('/host:/container') } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeDefaultImageKey -Scope User
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when no config exists' {
        It 'returns null' {
            $emptyDir = Join-Path $TestDrive 'empty'
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{
                    Directory = $emptyDir
                    FileName  = 'settings.json'
                }
            }

            $result = Get-DClaudeDefaultImageKey -Scope User
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when local override provides defaultImageKey' {
        It 'returns the local override value' {
            $dir = Join-Path $TestDrive 'merged'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            @{ defaultImageKey = 'base-image' } | ConvertTo-Json | Set-Content "$dir/settings.json"
            @{ defaultImageKey = 'local-image' } | ConvertTo-Json | Set-Content "$dir/settings.local.json"

            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{
                    Directory = $dir
                    FileName  = 'settings.json'
                }
            }

            $result = Get-DClaudeDefaultImageKey -Scope Project
            $result | Should -Be 'local-image'
        }
    }

    Context 'when scope resolution fails' {
        It 'returns nothing' {
            Mock Resolve-SettingsScope { return $null }

            $result = Get-DClaudeDefaultImageKey -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }
}
