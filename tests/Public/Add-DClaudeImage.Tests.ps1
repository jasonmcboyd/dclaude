BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DockerAvailable.ps1"
    . "$PSScriptRoot/../../src/Public/Add-DClaudeImage.ps1"
}

Describe 'Add-DClaudeImage' {

    BeforeEach {
        # Capture what Save-SettingsFile receives instead of writing to real $HOME
        $script:savedConfig = $null
        Mock Save-SettingsFile { $script:savedConfig = $Config }

        # Mock Docker so platform auto-detection doesn't need a real daemon
        Mock Test-DockerAvailable { return 'windows' }
    }

    Context 'when no user config exists' {
        It 'creates a new config with the image entry' {
            Mock Read-SettingsFile { return $null }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:latest' -Platform Windows

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.images.pwsh.windows.tag | Should -Be 'dclaude-pwsh:latest'
        }
    }

    Context 'when adding a new image to existing config' {
        It 'adds the new image without disturbing existing entries' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        dotnet = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-dotnet:latest' }
                        }
                    }
                }
            }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:latest' -Platform Windows

            $script:savedConfig.images.pwsh.windows.tag | Should -Be 'dclaude-pwsh:latest'
            $script:savedConfig.images.dotnet.windows.tag | Should -Be 'dclaude-dotnet:latest'
        }
    }

    Context 'when platform already exists without -Force' {
        It 'writes an error and does not overwrite' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:old' }
                        }
                    }
                }
            }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:new' -Platform Windows -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*already has*'
            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'when platform already exists with -Force' {
        It 'overwrites the existing platform entry' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:old' }
                        }
                    }
                }
            }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:new' -Platform Windows -Force

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.images.pwsh.windows.tag | Should -Be 'dclaude-pwsh:new'
        }
    }

    Context 'when adding with volumes' {
        It 'includes volumes in the platform entry' {
            Mock Read-SettingsFile { return $null }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:latest' -Platform Windows -Volumes @('C:/host:C:/container', 'C:/data:C:/data:rw')

            $script:savedConfig.images.pwsh.windows.volumes | Should -HaveCount 2
            $script:savedConfig.images.pwsh.windows.volumes[0] | Should -Be 'C:/host:C:/container'
        }
    }

    Context 'platform auto-detection' {
        BeforeEach {
            Mock Read-SettingsFile { return $null }
        }

        It 'infers Windows platform from Docker when -Platform is not specified' {
            Mock Test-DockerAvailable { return 'windows' }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:latest'

            $script:savedConfig.images.pwsh.PSObject.Properties['windows'] | Should -Not -BeNullOrEmpty
        }

        It 'infers Linux platform from Docker when -Platform is not specified' {
            Mock Test-DockerAvailable { return 'linux' }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh-linux:latest'

            $script:savedConfig.images.pwsh.PSObject.Properties['linux'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'adding a second platform to an existing image' {
        It 'adds the linux platform alongside existing windows' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                        }
                    }
                }
            }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh-linux:latest' -Platform Linux

            $script:savedConfig.images.pwsh.windows.tag | Should -Be 'dclaude-pwsh:latest'
            $script:savedConfig.images.pwsh.linux.tag | Should -Be 'dclaude-pwsh-linux:latest'
        }
    }
}
