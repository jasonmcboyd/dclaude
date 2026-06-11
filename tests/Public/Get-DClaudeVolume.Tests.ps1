BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../src/Public/Get-DClaudeVolume.ps1"
}

Describe 'Get-DClaudeVolume' {

    Context 'when volumes is set' {
        It 'returns the volumes' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }
            @{ volumes = @('/data:/data:rw', '/logs:/logs:ro') } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeVolume -Scope User
            $result | Should -HaveCount 2
            $result | Should -Contain '/data:/data:rw'
        }
    }

    Context 'when volumes is not set' {
        It 'returns empty array' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }
            @{ defaultImageKey = 'pwsh' } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeVolume -Scope User
            $result | Should -HaveCount 0
        }
    }

    Context 'when no config exists' {
        It 'returns empty array' {
            $emptyDir = Join-Path $TestDrive 'empty'
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $emptyDir; FileName = 'settings.json' }
            }

            $result = Get-DClaudeVolume -Scope User
            $result | Should -HaveCount 0
        }
    }

    Context 'when User scope has deprecated commonVolumes' {
        It 'falls back to commonVolumes' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }
            @{ commonVolumes = @('/old:/old:ro') } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeVolume -Scope User
            $result | Should -HaveCount 1
            $result[0] | Should -Be '/old:/old:ro'
        }
    }

    Context 'when local override has volumes' {
        It 'returns the local override value' {
            $dir = Join-Path $TestDrive 'merged'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            @{ volumes = @('/base:/base') } | ConvertTo-Json | Set-Content "$dir/settings.json"
            @{ volumes = @('/local:/local') } | ConvertTo-Json | Set-Content "$dir/settings.local.json"

            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $dir; FileName = 'settings.json' }
            }

            $result = Get-DClaudeVolume -Scope Project
            $result | Should -HaveCount 1
            $result[0] | Should -Be '/local:/local'
        }
    }
}
