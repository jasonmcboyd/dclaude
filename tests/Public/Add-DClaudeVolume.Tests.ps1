BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../src/Public/Add-DClaudeVolume.ps1"
}

Describe 'Add-DClaudeVolume' {

    BeforeEach {
        $script:savedConfig = $null
        Mock Save-SettingsFile { $script:savedConfig = $Config }
    }

    Context 'when no config exists' {
        It 'creates config with volumes array' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeVolume -Volume '/host:/container:ro'

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.volumes | Should -HaveCount 1
            $script:savedConfig.volumes[0] | Should -Be '/host:/container:ro'
        }
    }

    Context 'when adding to existing volumes' {
        It 'appends without duplicating existing entries' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ volumes = @('/data:/data:rw') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Add-DClaudeVolume -Volume '/new:/new:ro', '/data:/data:rw' -Scope Project

            $script:savedConfig.volumes | Should -HaveCount 2
            $script:savedConfig.volumes | Should -Contain '/data:/data:rw'
            $script:savedConfig.volumes | Should -Contain '/new:/new:ro'
        }
    }

    Context 'when all volumes already exist' {
        It 'does not save' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ volumes = @('/data:/data:rw') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Add-DClaudeVolume -Volume '/data:/data:rw' -Scope Project

            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'when adding multiple volumes' {
        It 'adds all new volumes at once' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeVolume -Volume '/a:/a:ro', '/b:/b:rw'

            $script:savedConfig.volumes | Should -HaveCount 2
        }
    }

    Context 'WhatIf support' {
        It 'does not save when -WhatIf is used' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeVolume -Volume '/host:/container' -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }
}
