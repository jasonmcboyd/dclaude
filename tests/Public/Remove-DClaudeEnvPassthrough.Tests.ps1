BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../src/Public/Remove-DClaudeEnvPassthrough.ps1"
}

Describe 'Remove-DClaudeEnvPassthrough' {

    BeforeEach {
        $script:savedConfig = $null
        Mock Save-SettingsFile { $script:savedConfig = $Config }
    }

    Context 'when removing an existing pattern' {
        It 'removes the pattern and saves' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ envPassthrough = @('NUGET_*', 'AZURE_*') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeEnvPassthrough -Pattern 'NUGET_*' -Scope Project

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.envPassthrough | Should -HaveCount 1
            $script:savedConfig.envPassthrough[0] | Should -Be 'AZURE_*'
        }
    }

    Context 'when removing the last pattern' {
        It 'removes the envPassthrough property entirely' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ envPassthrough = @('NUGET_*'); defaultImageKey = 'pwsh' }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeEnvPassthrough -Pattern 'NUGET_*' -Scope Project

            $script:savedConfig.PSObject.Properties['envPassthrough'] | Should -BeNullOrEmpty
            $script:savedConfig.defaultImageKey | Should -Be 'pwsh'
        }
    }

    Context 'when pattern is not found' {
        It 'writes an error and does not save' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ envPassthrough = @('AZURE_*') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeEnvPassthrough -Pattern 'NONEXISTENT' -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike "*not found*"
            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'when no envPassthrough exists' {
        It 'writes an error' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ defaultImageKey = 'pwsh' }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeEnvPassthrough -Pattern 'NUGET_*' -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'WhatIf support' {
        It 'does not save when -WhatIf is used' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ envPassthrough = @('NUGET_*') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeEnvPassthrough -Pattern 'NUGET_*' -Scope Project -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }
}
