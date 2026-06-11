BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../src/Public/Remove-DClaudeVolume.ps1"
}

Describe 'Remove-DClaudeVolume' {

    BeforeEach {
        $script:savedConfig = $null
        Mock Save-SettingsFile { $script:savedConfig = $Config }
    }

    Context 'when removing an existing volume' {
        It 'removes the volume and saves' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ volumes = @('/a:/a:ro', '/b:/b:rw') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a:ro' -Scope Project

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.volumes | Should -HaveCount 1
            $script:savedConfig.volumes[0] | Should -Be '/b:/b:rw'
        }
    }

    Context 'when removing the last volume' {
        It 'removes the volumes property entirely' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ volumes = @('/a:/a:ro'); defaultImageKey = 'pwsh' }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a:ro' -Scope Project

            $script:savedConfig.PSObject.Properties['volumes'] | Should -BeNullOrEmpty
            $script:savedConfig.defaultImageKey | Should -Be 'pwsh'
        }
    }

    Context 'when volume is not found' {
        It 'writes an error and does not save' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ volumes = @('/a:/a:ro') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/nonexistent:/path' -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike "*not found*"
            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'when no volumes exist' {
        It 'writes an error' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ defaultImageKey = 'pwsh' }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a' -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'WhatIf support' {
        It 'does not save when -WhatIf is used' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ volumes = @('/a:/a:ro') }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a:ro' -Scope Project -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }
}
