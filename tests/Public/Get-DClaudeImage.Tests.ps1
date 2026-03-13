BeforeAll {
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeUserConfig.ps1"
    . "$PSScriptRoot/../../src/Public/Get-DClaudeImage.ps1"
}

Describe 'Get-DClaudeImage' {

    Context 'when no user config exists' {
        It 'returns nothing' {
            Mock Get-DClaudeUserConfig { return $null }

            $result = Get-DClaudeImage
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when config has no images property' {
        It 'returns nothing' {
            Mock Get-DClaudeUserConfig { return [PSCustomObject]@{ somethingElse = 'value' } }

            $result = Get-DClaudeImage
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when images exist' {
        BeforeAll {
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest'; volumes = @('C:/foo:C:/bar') }
                            linux   = [PSCustomObject]@{ tag = 'dclaude-pwsh-linux:latest' }
                        }
                        dotnet = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'dclaude-dotnet:latest' }
                        }
                    }
                }
            }
        }

        It 'returns one row per platform per image' {
            $result = @(Get-DClaudeImage)
            # pwsh has 2 platforms, dotnet has 1 = 3 total
            $result | Should -HaveCount 3
        }

        It 'includes correct properties' {
            $result = @(Get-DClaudeImage)
            $pwshWindows = $result | Where-Object { $_.Name -eq 'pwsh' -and $_.Platform -eq 'windows' }
            $pwshWindows.Tag | Should -Be 'dclaude-pwsh:latest'
            $pwshWindows.Volumes | Should -HaveCount 1
            # Use pipe to avoid single-element array unwrapping to string
            # (indexing into a string returns a char, not the string)
            ($pwshWindows.Volumes | Select-Object -First 1) | Should -Be 'C:/foo:C:/bar'
        }

        It 'returns empty array for volumes when none defined' {
            $result = @(Get-DClaudeImage)
            $dotnetWindows = $result | Where-Object { $_.Name -eq 'dotnet' -and $_.Platform -eq 'windows' }
            $dotnetWindows.Volumes | Should -HaveCount 0
        }
    }

    Context 'filtering by -Name' {
        BeforeAll {
            Mock Get-DClaudeUserConfig {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh   = [PSCustomObject]@{ windows = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' } }
                        dotnet = [PSCustomObject]@{ windows = [PSCustomObject]@{ tag = 'dclaude-dotnet:latest' } }
                    }
                }
            }
        }

        It 'returns only the named image' {
            $result = @(Get-DClaudeImage -Name 'pwsh')
            $result | Should -HaveCount 1
            $result[0].Name | Should -Be 'pwsh'
        }

        It 'returns nothing for non-existent name' {
            $result = Get-DClaudeImage -Name 'nonexistent'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Read-SettingsFile vs Merge-SettingsFiles inconsistency' {
        # This test documents the known issue: Get-DClaudeImage uses
        # Get-DClaudeUserConfig (which calls Merge-SettingsFiles and sees
        # settings.local.json), but Add-DClaudeImage uses Read-SettingsFile
        # (which only reads settings.json). If settings.local.json overrides
        # the images property, there is a mismatch between what you add and
        # what you see.

        It 'sees images from local override via merge (shallow merge replaces base)' {
            # Simulate: base has "base" image, local has "local" image.
            # Because of shallow merge, local.images REPLACES base.images entirely.
            Mock Get-DClaudeUserConfig {
                # This is what Merge-SettingsFiles would return after shallow merge:
                # the local images property wins entirely
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        local = [PSCustomObject]@{
                            windows = [PSCustomObject]@{ tag = 'local:latest' }
                        }
                    }
                }
            }

            $result = @(Get-DClaudeImage)
            $result | Should -HaveCount 1
            $result[0].Name | Should -Be 'local'
        }
    }
}
