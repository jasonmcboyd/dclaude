BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
}

Describe 'Read-SettingsFile' {

    Context 'when settings.json does not exist' {
        It 'returns null' {
            $result = Read-SettingsFile -Directory $TestDrive
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when settings.json is empty' {
        It 'returns null' {
            '' | Set-Content "$TestDrive/settings.json"

            $result = Read-SettingsFile -Directory $TestDrive
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when settings.json is whitespace-only' {
        It 'returns null' {
            '   ' | Set-Content "$TestDrive/settings.json"

            $result = Read-SettingsFile -Directory $TestDrive
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when settings.json contains valid JSON' {
        It 'returns parsed object' {
            @{ imageKey = 'pwsh'; count = 42 } | ConvertTo-Json |
                Set-Content "$TestDrive/settings.json"

            $result = Read-SettingsFile -Directory $TestDrive
            $result.imageKey | Should -Be 'pwsh'
            $result.count | Should -Be 42
        }

        It 'preserves nested structures' {
            $data = @{
                images = @{
                    pwsh = @{
                        windows = @{ tag = 'dclaude-pwsh:latest' }
                    }
                }
            }
            $data | ConvertTo-Json -Depth 5 | Set-Content "$TestDrive/settings.json"

            $result = Read-SettingsFile -Directory $TestDrive
            $result.images.pwsh.windows.tag | Should -Be 'dclaude-pwsh:latest'
        }
    }

    Context 'when settings.json contains invalid JSON' {
        It 'throws with descriptive message' {
            'this is not json {{{' | Set-Content "$TestDrive/settings.json"

            { Read-SettingsFile -Directory $TestDrive } |
                Should -Throw '*Failed to parse*'
        }
    }

    It 'only reads settings.json, ignores settings.local.json' {
        @{ source = 'base' } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"
        @{ source = 'local' } | ConvertTo-Json | Set-Content "$TestDrive/settings.local.json"

        $result = Read-SettingsFile -Directory $TestDrive
        $result.source | Should -Be 'base'
    }

    Context 'when -FileName specifies a custom file' {
        It 'reads the specified file instead of settings.json' {
            @{ source = 'base' } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"
            @{ source = 'local' } | ConvertTo-Json | Set-Content "$TestDrive/settings.local.json"

            $result = Read-SettingsFile -Directory $TestDrive -FileName 'settings.local.json'
            $result.source | Should -Be 'local'
        }
    }
}
