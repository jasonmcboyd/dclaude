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

    Context 'when removing by local path' {
        It 'matches on the local path and removes the volume' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ linux = @('/a:/a:ro', '/b:/b:rw') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -LocalPath '/a' -Platform Linux -Scope Project

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.volumes.linux | Should -HaveCount 1
            $script:savedConfig.volumes.linux[0] | Should -Be '/b:/b:rw'
        }

        It 'matches Windows drive-letter paths' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ windows = @('C:\data:C:\data:ro', 'C:\wrk:C:\wrk:rw') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -LocalPath 'C:\data' -Platform Windows -Scope Project

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.volumes.windows | Should -HaveCount 1
            $script:savedConfig.volumes.windows[0] | Should -Be 'C:\wrk:C:\wrk:rw'
        }

        It 'ignores trailing slashes when matching' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ windows = @('C:\data\:C:\data\:ro') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Remove-DClaudeVolume -LocalPath 'C:\data' -Platform Windows -Scope Project

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.PSObject.Properties['volumes'] | Should -BeNullOrEmpty
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

            Remove-DClaudeVolume -LocalPath '/a' -Platform Linux -Scope Project

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

            Remove-DClaudeVolume -LocalPath '/a' -Platform Linux -Scope Project

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

            Remove-DClaudeVolume -LocalPath '/nonexistent' -Platform Linux -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike "*No volume*found*"
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

            Remove-DClaudeVolume -LocalPath '/a' -Platform Linux -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

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

            Remove-DClaudeVolume -LocalPath '/a' -Platform Linux -Scope Project -ErrorVariable err -ErrorAction SilentlyContinue

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

            Remove-DClaudeVolume -LocalPath '/a' -Platform Linux -Scope Project -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }
}
