BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../src/Public/Set-DClaudeDefaultImageKey.ps1"
}

Describe 'Set-DClaudeDefaultImageKey' {

    BeforeEach {
        $script:savedConfig = $null
        $script:savedDirectory = $null
        $script:savedFileName = $null
        Mock Save-SettingsFile {
            $script:savedConfig = $Config
            $script:savedDirectory = $Directory
            $script:savedFileName = $FileName
        }
    }

    Context 'when setting at User scope' {
        It 'writes defaultImageKey to user config' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{
                    Directory = (Join-Path $HOME '.dclaude')
                    FileName  = 'settings.json'
                }
            }

            Set-DClaudeDefaultImageKey -ImageKey 'pwsh' -Scope User

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.defaultImageKey | Should -Be 'pwsh'
            $script:savedFileName | Should -Be 'settings.json'
        }
    }

    Context 'when setting at ProjectLocal scope (default)' {
        It 'writes defaultImageKey to project settings.local.json' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{
                    Directory = (Join-Path $TestDrive '.dclaude')
                    FileName  = 'settings.local.json'
                }
            }

            Set-DClaudeDefaultImageKey -ImageKey 'dotnet'

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.defaultImageKey | Should -Be 'dotnet'
            $script:savedFileName | Should -Be 'settings.local.json'
        }
    }

    Context 'when config already has a defaultImageKey' {
        It 'overwrites the existing value' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ defaultImageKey = 'old-image' }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{
                    Directory = (Join-Path $HOME '.dclaude')
                    FileName  = 'settings.json'
                }
            }

            Set-DClaudeDefaultImageKey -ImageKey 'new-image' -Scope User

            $script:savedConfig.defaultImageKey | Should -Be 'new-image'
        }
    }

    Context 'when scope resolution fails' {
        It 'does not save anything' {
            Mock Resolve-SettingsScope { return $null }

            Set-DClaudeDefaultImageKey -ImageKey 'pwsh' -ErrorAction SilentlyContinue

            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'WhatIf support' {
        It 'does not save when -WhatIf is used' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{
                    Directory = (Join-Path $HOME '.dclaude')
                    FileName  = 'settings.json'
                }
            }

            Set-DClaudeDefaultImageKey -ImageKey 'pwsh' -Scope User -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }
}
