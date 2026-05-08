BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeUserConfig.ps1"
}

Describe 'Get-DClaudeUserConfig' {

    Context 'when no user config exists' {
        It 'returns null' {
            Mock Merge-SettingsFiles { return $null }

            $result = Get-DClaudeUserConfig
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when user config exists' {
        It 'returns the merged config' {
            Mock Merge-SettingsFiles {
                return [PSCustomObject]@{
                    images = [PSCustomObject]@{
                        pwsh = [PSCustomObject]@{
                            linux = [PSCustomObject]@{ tag = 'test:latest' }
                        }
                    }
                }
            }

            $result = Get-DClaudeUserConfig
            $result | Should -Not -BeNullOrEmpty
            $result.images.pwsh.linux.tag | Should -Be 'test:latest'
        }
    }

    Context 'calls Merge-SettingsFiles correctly' {
        It 'passes ~/.dclaude directory and user config label' {
            Mock Merge-SettingsFiles { return $null }

            Get-DClaudeUserConfig

            Should -Invoke Merge-SettingsFiles -Times 1 -ParameterFilter {
                $Directory -eq (Join-Path $HOME '.dclaude') -and
                $Label -eq 'user config'
            }
        }
    }
}
