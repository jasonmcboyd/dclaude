BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DockerContainerOS.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeUserConfig.ps1"
    . "$PSScriptRoot/../../src/Public/Add-DClaudeImage.ps1"
}

Describe 'Add-DClaudeImage' {

    BeforeEach {
        # Capture what Save-SettingsFile receives instead of writing to real $HOME
        $script:savedConfig = $null
        Mock Save-SettingsFile { $script:savedConfig = $Config }

        # Mock Docker so platform auto-detection doesn't need a real daemon
        Mock Get-DockerContainerOS { return 'windows' }
    }

    Context 'when no user config exists' {
        It 'creates a new config with the image entry' {
            Mock Read-SettingsFile { return $null }
            Mock Get-DClaudeUserConfig { return $null }

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
            Mock Get-DClaudeUserConfig {
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
            Mock Get-DClaudeUserConfig {
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
            Mock Get-DClaudeUserConfig {
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
            Mock Get-DClaudeUserConfig { return $null }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:latest' -Platform Windows -Volumes @('C:/host:C:/container', 'C:/data:C:/data:rw')

            $script:savedConfig.images.pwsh.windows.volumes | Should -HaveCount 2
            $script:savedConfig.images.pwsh.windows.volumes[0] | Should -Be 'C:/host:C:/container'
        }
    }

    Context 'when adding with env' {
        It 'includes env in the platform entry' {
            Mock Read-SettingsFile { return $null }
            Mock Get-DClaudeUserConfig { return $null }

            Add-DClaudeImage -Name 'vertex' -Tag 'python:3.12-slim' -Platform Linux -Env @{ CLOUD_ML_REGION = 'us-east1'; ANTHROPIC_VERTEX_PROJECT_ID = 'my-project' }

            $script:savedConfig.images.vertex.linux.env | Should -Not -BeNullOrEmpty
            $script:savedConfig.images.vertex.linux.env.CLOUD_ML_REGION | Should -Be 'us-east1'
            $script:savedConfig.images.vertex.linux.env.ANTHROPIC_VERTEX_PROJECT_ID | Should -Be 'my-project'
        }

        It 'does not include env when not specified' {
            Mock Read-SettingsFile { return $null }
            Mock Get-DClaudeUserConfig { return $null }

            Add-DClaudeImage -Name 'pwsh' -Tag 'pwsh:latest' -Platform Linux

            $script:savedConfig.images.pwsh.linux.PSObject.Properties['env'] | Should -BeNullOrEmpty
        }
    }

    Context 'platform auto-detection' {
        BeforeEach {
            Mock Read-SettingsFile { return $null }
            Mock Get-DClaudeUserConfig { return $null }
        }

        It 'infers Windows platform from Docker when -Platform is not specified' {
            Mock Get-DockerContainerOS { return 'windows' }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:latest'

            $script:savedConfig.images.pwsh.PSObject.Properties['windows'] | Should -Not -BeNullOrEmpty
        }

        It 'infers Linux platform from Docker when -Platform is not specified' {
            Mock Get-DockerContainerOS { return 'linux' }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh-linux:latest'

            $script:savedConfig.images.pwsh.PSObject.Properties['linux'] | Should -Not -BeNullOrEmpty
        }

        It 'returns early without saving when Docker is unavailable' {
            Mock Get-DockerContainerOS { return $null }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:latest' -ErrorVariable err -ErrorAction SilentlyContinue

            Should -Not -Invoke Save-SettingsFile
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
            Mock Get-DClaudeUserConfig {
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

    Context 'WhatIf support' {
        It 'does not invoke Save-SettingsFile when -WhatIf is used' {
            Mock Read-SettingsFile { return $null }
            Mock Get-DClaudeUserConfig { return $null }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:latest' -Platform Windows -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }

        It 'does not invoke Save-SettingsFile when -WhatIf is used with -Force on existing entry' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:old' }
                        }
                    }
                }
            }
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:old' }
                        }
                    }
                }
            }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:new' -Platform Windows -Force -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'when platform exists only in local override' {
        It 'detects the duplicate from merged config and errors without -Force' {
            # Base settings.json has no images
            Mock Read-SettingsFile { return $null }
            # But merged config (including settings.local.json) has the image
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh-local:latest' }
                        }
                    }
                }
            }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:new' -Platform Windows -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*already has*'
            Should -Not -Invoke Save-SettingsFile
        }

        It 'allows overwrite with -Force even when only in local override' {
            Mock Read-SettingsFile { return $null }
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh-local:latest' }
                        }
                    }
                }
            }

            Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:new' -Platform Windows -Force

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.images.pwsh.windows.tag | Should -Be 'dclaude-pwsh:new'
        }
    }
}
