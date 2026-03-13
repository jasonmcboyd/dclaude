BeforeAll {
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeConfig.ps1"
    . "$PSScriptRoot/../../src/Public/Get-DClaudeProject.ps1"
}

Describe 'Get-DClaudeProject' {

    Context 'when no project config exists' {
        It 'returns null' {
            Mock Get-DClaudeConfig { return $null }

            $result = Get-DClaudeProject -Path $TestDrive
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when project config has imageKey' {
        It 'returns the ImageKey' {
            $projectDir = Join-Path $TestDrive 'project-ik'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'pwsh' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')

            $result = Get-DClaudeProject -Path $projectDir
            $result.ImageKey | Should -Be 'pwsh'
            $result.Image | Should -BeNullOrEmpty
        }
    }

    Context 'when project config has image' {
        It 'returns the Image' {
            $projectDir = Join-Path $TestDrive 'project-img'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ image = 'custom:v1' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')

            $result = Get-DClaudeProject -Path $projectDir
            $result.Image | Should -Be 'custom:v1'
            $result.ImageKey | Should -BeNullOrEmpty
        }
    }

    Context 'when project config has volumes' {
        It 'returns the volumes' {
            $projectDir = Join-Path $TestDrive 'project-vol'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{
                imageKey = 'pwsh'
                volumes  = @('C:/a:C:/b', 'C:/c:C:/d:rw')
            } | ConvertTo-Json -Depth 5 |
                Set-Content (Join-Path $configDir 'settings.json')

            $result = Get-DClaudeProject -Path $projectDir
            $result.Volumes | Should -HaveCount 2
        }
    }

    Context 'when project config has no volumes' {
        It 'returns an empty array for Volumes' {
            $projectDir = Join-Path $TestDrive 'project-novol'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'pwsh' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')

            $result = Get-DClaudeProject -Path $projectDir
            $result.Volumes | Should -HaveCount 0
        }
    }

    Context 'config merging for project' {
        It 'returns merged config with local override' {
            $projectDir = Join-Path $TestDrive 'project-merge'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null

            @{ imageKey = 'base' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')
            @{ imageKey = 'override' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.local.json')

            $result = Get-DClaudeProject -Path $projectDir
            $result.ImageKey | Should -Be 'override'
        }
    }
}
