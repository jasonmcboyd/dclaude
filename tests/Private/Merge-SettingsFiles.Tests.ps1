BeforeAll {
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
}

Describe 'Merge-SettingsFiles' {

    Context 'when no files exist' {
        It 'returns null' {
            $dir = Join-Path $TestDrive 'empty'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when only settings.json exists' {
        It 'returns the base config' {
            $dir = Join-Path $TestDrive 'base-only'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'pwsh' } | ConvertTo-Json | Set-Content "$dir/settings.json"

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'
            $result.imageKey | Should -Be 'pwsh'
        }
    }

    Context 'when only settings.local.json exists' {
        It 'returns the local config' {
            $dir = Join-Path $TestDrive 'local-only'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'custom' } | ConvertTo-Json | Set-Content "$dir/settings.local.json"

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'
            $result.imageKey | Should -Be 'custom'
        }
    }

    Context 'when both files exist' {
        It 'local properties override base properties' {
            $dir = Join-Path $TestDrive 'both-override'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'pwsh'; someOther = 'base' } | ConvertTo-Json | Set-Content "$dir/settings.json"
            @{ imageKey = 'custom' } | ConvertTo-Json | Set-Content "$dir/settings.local.json"

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'
            $result.imageKey | Should -Be 'custom'
        }

        It 'preserves base properties not present in local' {
            $dir = Join-Path $TestDrive 'both-preserve'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'pwsh'; someOther = 'base' } | ConvertTo-Json | Set-Content "$dir/settings.json"
            @{ imageKey = 'custom' } | ConvertTo-Json | Set-Content "$dir/settings.local.json"

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'
            $result.someOther | Should -Be 'base'
        }

        It 'shallow-merges: local replaces entire top-level property including sibling keys' {
            # This documents the known gotcha: if base has images with pwsh
            # and local has images with vertex, the merge REPLACES the entire
            # images property -- pwsh is lost.
            $dir = Join-Path $TestDrive 'shallow-merge'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null

            $base = @{
                images = @{
                    pwsh = @{
                        windows = @{ tag = 'dclaude-pwsh:latest' }
                    }
                }
            }
            $local = @{
                images = @{
                    vertex = @{
                        windows = @{ tag = 'dclaude-vertex:latest' }
                    }
                }
            }
            $base | ConvertTo-Json -Depth 5 | Set-Content "$dir/settings.json"
            $local | ConvertTo-Json -Depth 5 | Set-Content "$dir/settings.local.json"

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'

            $result.images.PSObject.Properties['vertex'] | Should -Not -BeNullOrEmpty
            $result.images.PSObject.Properties['pwsh'] | Should -BeNullOrEmpty
        }
    }

    Context 'when files are empty or whitespace' {
        It 'treats empty settings.json as non-existent' {
            $dir = Join-Path $TestDrive 'empty-base'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            '' | Set-Content "$dir/settings.json"
            @{ imageKey = 'local' } | ConvertTo-Json | Set-Content "$dir/settings.local.json"

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'
            $result.imageKey | Should -Be 'local'
        }

        It 'treats whitespace-only settings.json as non-existent' {
            $dir = Join-Path $TestDrive 'whitespace-base'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            '   ' | Set-Content "$dir/settings.json"

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'
            $result | Should -BeNullOrEmpty
        }

        It 'treats empty settings.local.json as non-existent' {
            $dir = Join-Path $TestDrive 'empty-local'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'base' } | ConvertTo-Json | Set-Content "$dir/settings.json"
            '' | Set-Content "$dir/settings.local.json"

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'
            $result.imageKey | Should -Be 'base'
        }

        It 'returns null when both files are empty' {
            $dir = Join-Path $TestDrive 'both-empty'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            '' | Set-Content "$dir/settings.json"
            '' | Set-Content "$dir/settings.local.json"

            $result = Merge-SettingsFiles -Directory $dir -Label 'test'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when files contain invalid JSON' {
        It 'throws on invalid settings.json' {
            $dir = Join-Path $TestDrive 'bad-base'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            'not json' | Set-Content "$dir/settings.json"

            { Merge-SettingsFiles -Directory $dir -Label 'test' } |
                Should -Throw '*Failed to parse*'
        }

        It 'throws on invalid settings.local.json' {
            $dir = Join-Path $TestDrive 'bad-local'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ valid = $true } | ConvertTo-Json | Set-Content "$dir/settings.json"
            'not json' | Set-Content "$dir/settings.local.json"

            { Merge-SettingsFiles -Directory $dir -Label 'test' } |
                Should -Throw '*Failed to parse*'
        }
    }
}
