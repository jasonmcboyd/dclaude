BeforeAll {
    . "$PSScriptRoot/../../Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../Public/Add-DClaudeEnvPassthrough.ps1"
}

Describe 'Add-DClaudeEnvPassthrough' {

    BeforeEach {
        $script:savedConfig = $null
        Mock Save-SettingsFile { $script:savedConfig = $Config }
    }

    Context 'when no config exists' {
        It 'creates config with envPassthrough array' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeEnvPassthrough -Pattern 'NUGET_*'

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.envPassthrough | Should -HaveCount 1
            $script:savedConfig.envPassthrough[0] | Should -Be 'NUGET_*'
        }
    }

    Context 'when adding to existing patterns' {
        It 'appends without duplicating existing entries' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ envPassthrough = @('AZURE_*') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Add-DClaudeEnvPassthrough -Pattern 'NUGET_*', 'AZURE_*' -Scope Project

            $script:savedConfig.envPassthrough | Should -HaveCount 2
            $script:savedConfig.envPassthrough | Should -Contain 'AZURE_*'
            $script:savedConfig.envPassthrough | Should -Contain 'NUGET_*'
        }
    }

    Context 'when all patterns already exist' {
        It 'does not save' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ envPassthrough = @('NUGET_*') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Add-DClaudeEnvPassthrough -Pattern 'NUGET_*' -Scope Project

            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'when adding multiple new patterns' {
        It 'adds all new patterns at once' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeEnvPassthrough -Pattern 'FOO_*', 'BAR_*', 'BAZ'

            $script:savedConfig.envPassthrough | Should -HaveCount 3
        }
    }

    Context 'WhatIf support' {
        It 'does not save when -WhatIf is used' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeEnvPassthrough -Pattern 'TEST_*' -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }
}
