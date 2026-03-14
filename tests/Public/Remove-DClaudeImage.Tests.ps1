BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeUserConfig.ps1"
    . "$PSScriptRoot/../../src/Public/Remove-DClaudeImage.ps1"
}

Describe 'Remove-DClaudeImage' {

    BeforeEach {
        $script:savedConfig = $null
        Mock Save-SettingsFile { $script:savedConfig = $Config }
    }

    Context 'when no config exists' {
        It 'writes an error' {
            Mock Read-SettingsFile { return $null }
            Mock Get-DClaudeUserConfig { return $null }

            Remove-DClaudeImage -Name 'pwsh' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*not found*'
        }
    }

    Context 'when the image name does not exist' {
        It 'writes an error' {
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

            Remove-DClaudeImage -Name 'pwsh' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*not found*'
        }
    }

    Context 'when removing a specific platform' {
        It 'removes only the specified platform' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                            linux   = [PSCustomObject]@{ tag = 'dclaude-pwsh-linux:latest' }
                        }
                    }
                }
            }
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                            linux   = [PSCustomObject]@{ tag = 'dclaude-pwsh-linux:latest' }
                        }
                    }
                }
            }

            Remove-DClaudeImage -Name 'pwsh' -Platform Windows

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.images.pwsh.PSObject.Properties['windows'] | Should -BeNullOrEmpty
            $script:savedConfig.images.pwsh.linux.tag | Should -Be 'dclaude-pwsh-linux:latest'
        }
    }

    Context 'when removing the last platform' {
        It 'removes the entire image entry' {
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

            Remove-DClaudeImage -Name 'pwsh' -Platform Windows

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.images.PSObject.Properties['pwsh'] | Should -BeNullOrEmpty
        }
    }

    Context 'when removing all platforms (no -Platform specified)' {
        It 'removes the entire image entry' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                            linux   = [PSCustomObject]@{ tag = 'dclaude-pwsh-linux:latest' }
                        }
                    }
                }
            }
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                            linux   = [PSCustomObject]@{ tag = 'dclaude-pwsh-linux:latest' }
                        }
                    }
                }
            }

            Remove-DClaudeImage -Name 'pwsh'

            Should -Invoke Save-SettingsFile -Times 1
            $script:savedConfig.images.PSObject.Properties['pwsh'] | Should -BeNullOrEmpty
        }
    }

    Context 'when removing a platform that does not exist' {
        It 'writes an error' {
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

            Remove-DClaudeImage -Name 'pwsh' -Platform Linux -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike "*does not have*linux*"
        }
    }

    Context 'WhatIf support' {
        It 'does not invoke Save-SettingsFile when -WhatIf is used on full removal' {
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

            Remove-DClaudeImage -Name 'pwsh' -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }

        It 'does not invoke Save-SettingsFile when -WhatIf is used on platform removal' {
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                            linux   = [PSCustomObject]@{ tag = 'dclaude-pwsh-linux:latest' }
                        }
                    }
                }
            }
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                            linux   = [PSCustomObject]@{ tag = 'dclaude-pwsh-linux:latest' }
                        }
                    }
                }
            }

            Remove-DClaudeImage -Name 'pwsh' -Platform Windows -WhatIf

            Should -Not -Invoke Save-SettingsFile
        }
    }

    Context 'when image exists only in local override' {
        It 'errors when trying to remove entire image defined only in settings.local.json' {
            # Base settings.json has no images
            Mock Read-SettingsFile { return $null }
            # Merged config sees the image from settings.local.json
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh-local:latest' }
                        }
                    }
                }
            }

            Remove-DClaudeImage -Name 'pwsh' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*settings.local.json*'
            Should -Not -Invoke Save-SettingsFile
        }

        It 'errors when trying to remove a platform defined only in settings.local.json' {
            # Base settings.json has the image but only with windows
            Mock Read-SettingsFile {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                        }
                    }
                }
            }
            # Merged config also has linux from settings.local.json
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                            linux   = [PSCustomObject]@{ tag = 'dclaude-pwsh-local-linux:latest' }
                        }
                    }
                }
            }

            Remove-DClaudeImage -Name 'pwsh' -Platform Linux -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*settings.local.json*'
            Should -Not -Invoke Save-SettingsFile
        }
    }
}
