BeforeAll {
    . "$PSScriptRoot/../../Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../Public/Remove-DClaudeVolume.ps1"
}

Describe 'Remove-DClaudeVolume' {

    BeforeEach {
        $script:savedConfig = $null
        Mock Save-SettingsFile { $script:savedConfig = $Config }
    }

    Context 'when removing an existing volume' {
        It 'removes the volume and saves' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ linux = @('/a:/a:ro', '/b:/b:rw') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a:ro' -Platform Linux -Scope Project

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.volumes.linux | Should -HaveCount 1
            $script:savedConfig.volumes.linux[0] | Should -Be '/b:/b:rw'
        }
    }

    Context 'when removing the last volume for a platform' {
        It 'removes the platform key' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{
                        linux   = @('/a:/a:ro')
                        windows = @('C:/x:C:/x:ro')
                    }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a:ro' -Platform Linux -Scope Project

            $script:savedConfig.volumes.PSObject.Properties['linux'] | Should -BeNullOrEmpty
            $script:savedConfig.volumes.windows | Should -HaveCount 1
        }
    }

    Context 'when removing the last volume across all platforms' {
        It 'removes the volumes property entirely' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes        = [PSCustomObject]@{ linux = @('/a:/a:ro') }
                    defaultImageKey = 'pwsh'
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a:ro' -Platform Linux -Scope Project

            $script:savedConfig.PSObject.Properties['volumes'] | Should -BeNullOrEmpty
            $script:savedConfig.defaultImageKey | Should -Be 'pwsh'
        }
    }

    Context 'when volume is not found' {
        It 'writes an error and does not save' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ linux = @('/a:/a:ro') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/nonexistent:/path' -Platform Linux -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike "*not found*"
            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'when no volumes exist for the platform' {
        It 'writes an error' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ windows = @('C:/a:C:/a:ro') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a' -Platform Linux -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'when no volumes exist at all' {
        It 'writes an error' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{ defaultImageKey = 'pwsh' }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a' -Platform Linux -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'WhatIf support' {
        It 'does not save when -WhatIf is used' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ linux = @('/a:/a:ro') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -Volume '/a:/a:ro' -Platform Linux -Scope Project -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }
}
