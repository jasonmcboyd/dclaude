BeforeAll {
    . "$PSScriptRoot/../../src/Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-SettingsScope.ps1"
    . "$PSScriptRoot/../../src/Public/Get-DClaudeVolume.ps1"
}

Describe 'Get-DClaudeVolume' {

    Context 'when volumes is set for the platform' {
        It 'returns the platform volumes' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }
            @{
                volumes = @{
                    linux   = @('/data:/data:rw', '/logs:/logs:ro')
                    windows = @('C:/data:C:/data:ro')
                }
            } | ConvertTo-Json -Depth 3 | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeVolume -Platform Linux -Scope User
            $result | Should -HaveCount 2
            $result | Should -Contain '/data:/data:rw'
        }
    }

    Context 'when volumes has no entries for the requested platform' {
        It 'returns empty array' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }
            @{
                volumes = @{ windows = @('C:/data:C:/data:ro') }
            } | ConvertTo-Json -Depth 3 | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeVolume -Platform Linux -Scope User
            $result | Should -HaveCount 0
        }
    }

    Context 'when volumes is not set' {
        It 'returns empty array' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }
            @{ defaultImageKey = 'pwsh' } | ConvertTo-Json | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeVolume -Platform Linux -Scope User
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

            $result = Get-DClaudeVolume -Platform Linux -Scope User
            $result | Should -HaveCount 0
        }
    }

    Context 'when User scope has deprecated commonVolumes' {
        It 'falls back to commonVolumes platform key' {
            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $TestDrive; FileName = 'settings.json' }
            }
            @{
                commonVolumes = @{ linux = @('/old:/old:ro') }
            } | ConvertTo-Json -Depth 3 | Set-Content "$TestDrive/settings.json"

            $result = Get-DClaudeVolume -Platform Linux -Scope User
            $result | Should -HaveCount 1
            $result[0] | Should -Be '/old:/old:ro'
        }
    }

    Context 'when local override has volumes' {
        It 'returns the local override value' {
            $dir = Join-Path $TestDrive 'merged'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            @{
                volumes = @{ linux = @('/base:/base:ro') }
            } | ConvertTo-Json -Depth 3 | Set-Content "$dir/settings.json"
            @{
                volumes = @{ linux = @('/local:/local:ro') }
            } | ConvertTo-Json -Depth 3 | Set-Content "$dir/settings.local.json"

            Mock Resolve-SettingsScope {
                return [PSCustomObject]@{ Directory = $dir; FileName = 'settings.json' }
            }

            $result = Get-DClaudeVolume -Platform Linux -Scope Project
            $result | Should -HaveCount 1
            $result[0] | Should -Be '/local:/local:ro'
        }
    }
}
