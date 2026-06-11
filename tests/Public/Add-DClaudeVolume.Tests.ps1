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

    Context 'with just a local path' {
        It 'uses the same path for container and defaults to read-only' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeVolume 'C:\Users\me\repos\project' -Platform Linux

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.volumes | Should -BeOfType [PSCustomObject]
            $script:savedConfig.volumes.linux | Should -HaveCount 1
            $script:savedConfig.volumes.linux[0] | Should -Be 'C:\Users\me\repos\project:C:\Users\me\repos\project:ro'
        }
    }

    Context 'with a container path' {
        It 'uses different host and container paths' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeVolume 'C:\Users\me\.nuget' -ContainerPath '/home/claude/.nuget' -Platform Linux

            $script:savedConfig.volumes.linux[0] | Should -Be 'C:\Users\me\.nuget:/home/claude/.nuget:ro'
        }
    }

    Context 'with -ReadWrite switch' {
        It 'sets mode to rw' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeVolume '/data' -ReadWrite -Platform Linux

            $script:savedConfig.volumes.linux[0] | Should -Be '/data:/data:rw'
        }
    }

    Context 'when adding to existing volumes' {
        It 'appends without disturbing existing entries' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ linux = @('/old:/old:ro') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Add-DClaudeVolume '/new' -Platform Linux -Scope Project

            $script:savedConfig.volumes.linux | Should -HaveCount 2
            $script:savedConfig.volumes.linux | Should -Contain '/old:/old:ro'
            $script:savedConfig.volumes.linux | Should -Contain '/new:/new:ro'
        }

        It 'preserves other platform entries' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{
                        windows = @('C:/win:C:/win:ro')
                        linux   = @('/old:/old:ro')
                    }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Add-DClaudeVolume '/new' -Platform Linux -Scope Project

            $script:savedConfig.volumes.windows | Should -HaveCount 1
            $script:savedConfig.volumes.windows[0] | Should -Be 'C:/win:C:/win:ro'
            $script:savedConfig.volumes.linux | Should -HaveCount 2
        }
    }

    Context 'when volume already exists' {
        It 'does not save' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ linux = @('/data:/data:ro') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Add-DClaudeVolume '/data' -Platform Linux -Scope Project

            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'WhatIf support' {
        It 'does not save when -WhatIf is used' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeVolume '/host' -Platform Linux -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'positional parameters' {
        It 'accepts local and container paths positionally' {
            Mock Read-SettingsFile { return $null }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.local.json' }
            }

            Add-DClaudeVolume '/local' '/container' -Platform Linux

            $script:savedConfig.volumes.linux[0] | Should -Be '/local:/container:ro'
        }
    }

    Context 'adding to a new platform on existing volumes object' {
        It 'creates the platform key' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    volumes = [PSCustomObject]@{ linux = @('/a:/a:ro') }
                }
            }
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }

            Add-DClaudeVolume 'C:\data' -Platform Windows -Scope Project

            $script:savedConfig.volumes.linux | Should -HaveCount 1
            $script:savedConfig.volumes.windows | Should -HaveCount 1
            $script:savedConfig.volumes.windows[0] | Should -Be 'C:\data:C:\data:ro'
        }
    }
}
