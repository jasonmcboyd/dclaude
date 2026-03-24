BeforeAll {
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeUserConfig.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-ImageKey.ps1"
}

Describe 'Resolve-ImageKey' {

    Context 'when no user config exists' {
        It 'writes an error' {
            Mock Get-DClaudeUserConfig { return $null }

            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'windows' -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*No user config found*'
        }
    }

    Context 'when user config has no images property' {
        It 'writes an error mentioning images property' {
            Mock Get-DClaudeUserConfig { return [PSCustomObject]@{ somethingElse = 'value' } }

            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'windows' -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike "*no 'images' property*"
        }
    }

    Context 'when the requested key does not exist' {
        It 'writes an error listing available keys' {
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        dotnet = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-dotnet:latest' }
                        }
                    }
                }
            }

            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'windows' -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*not found*'
            $err[0].ToString() | Should -BeLike '*dotnet*'
        }
    }

    Context 'when the requested platform does not exist for the key' {
        It 'writes an error listing available platforms' {
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            linux = [PSCustomObject]@{ tag = 'dclaude-pwsh-linux:latest' }
                        }
                    }
                }
            }

            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'windows' -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike "*no 'windows' platform*"
            $err[0].ToString() | Should -BeLike '*linux*'
        }
    }

    Context 'when the platform entry is missing the tag property' {
        It 'writes an error about missing tag' {
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ volumes = @('C:/foo:C:/bar') }
                        }
                    }
                }
            }

            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'windows' -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike "*missing the required 'tag'*"
        }
    }

    Context 'when the key and platform are valid' {
        BeforeAll {
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{
                                tag     = 'dclaude-pwsh:latest'
                                volumes = @('C:/host:C:/container:ro', 'C:/data:C:/data:rw')
                            }
                        }
                    }
                }
            }
        }

        It 'returns the tag' {
            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'windows'
            $result.tag | Should -Be 'dclaude-pwsh:latest'
        }

        It 'returns the volumes' {
            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'windows'
            $result.volumes | Should -HaveCount 2
            $result.volumes[0] | Should -Be 'C:/host:C:/container:ro'
        }

        It 'returns null env when not configured' {
            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'windows'
            $result.env | Should -BeNullOrEmpty
        }
    }

    Context 'when the platform entry has env' {
        It 'returns the env object' {
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        vertex = [PSCustomObject]@{
                            linux = [PSCustomObject]@{
                                tag = 'python:3.12-slim'
                                env = [PSCustomObject]@{
                                    CLOUD_ML_REGION = 'us-east1'
                                    ANTHROPIC_VERTEX_PROJECT_ID = 'my-project'
                                }
                            }
                        }
                    }
                }
            }

            $result = Resolve-ImageKey -Key 'vertex' -ContainerOS 'linux'
            $result.env | Should -Not -BeNullOrEmpty
            $result.env.CLOUD_ML_REGION | Should -Be 'us-east1'
            $result.env.ANTHROPIC_VERTEX_PROJECT_ID | Should -Be 'my-project'
        }
    }

    Context 'when the platform entry has no volumes' {
        It 'returns an empty array for volumes' {
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                        }
                    }
                }
            }

            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'windows'
            $result.volumes | Should -HaveCount 0
        }
    }

    Context 'ContainerOS case handling' {
        It 'normalizes ContainerOS to lowercase for lookup' {
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                        }
                    }
                }
            }

            $result = Resolve-ImageKey -Key 'pwsh' -ContainerOS 'Windows'
            $result.tag | Should -Be 'dclaude-pwsh:latest'
        }
    }
}
