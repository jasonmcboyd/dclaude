BeforeAll {
    . "$PSScriptRoot/../../src/Public/Set-DClaudeProject.ps1"
}

Describe 'Set-DClaudeProject' {

    Context 'when setting imageKey' {
        It 'writes imageKey to settings.local.json' {
            Set-DClaudeProject -ImageKey 'pwsh' -Path $TestDrive

            $filePath = Join-Path $TestDrive '.dclaude/settings.local.json'
            $filePath | Should -Exist
            $config = Get-Content $filePath -Raw | ConvertFrom-Json
            $config.imageKey | Should -Be 'pwsh'
        }

        It 'removes image property when setting imageKey' {
            # Pre-populate with image
            $dir = Join-Path $TestDrive '.dclaude'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ image = 'old:tag' } | ConvertTo-Json |
                Set-Content (Join-Path $dir 'settings.local.json')

            Set-DClaudeProject -ImageKey 'pwsh' -Path $TestDrive

            $config = Get-Content (Join-Path $dir 'settings.local.json') -Raw | ConvertFrom-Json
            $config.imageKey | Should -Be 'pwsh'
            $config.PSObject.Properties['image'] | Should -BeNullOrEmpty
        }
    }

    Context 'when setting image' {
        It 'writes image to settings.local.json' {
            Set-DClaudeProject -Image 'custom:v1' -Path $TestDrive

            $filePath = Join-Path $TestDrive '.dclaude/settings.local.json'
            $config = Get-Content $filePath -Raw | ConvertFrom-Json
            $config.image | Should -Be 'custom:v1'
        }

        It 'removes imageKey property when setting image' {
            $dir = Join-Path $TestDrive '.dclaude'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'old-key' } | ConvertTo-Json |
                Set-Content (Join-Path $dir 'settings.local.json')

            Set-DClaudeProject -Image 'custom:v1' -Path $TestDrive

            $config = Get-Content (Join-Path $dir 'settings.local.json') -Raw | ConvertFrom-Json
            $config.image | Should -Be 'custom:v1'
            $config.PSObject.Properties['imageKey'] | Should -BeNullOrEmpty
        }
    }

    Context 'volume handling' {
        It 'writes volumes when provided' {
            Set-DClaudeProject -ImageKey 'pwsh' -Volumes @('C:/a:C:/b', 'C:/c:C:/d:rw') -Path $TestDrive

            $filePath = Join-Path $TestDrive '.dclaude/settings.local.json'
            $config = Get-Content $filePath -Raw | ConvertFrom-Json
            $config.volumes | Should -HaveCount 2
        }

        It 'removes volumes when empty array passed explicitly' {
            $dir = Join-Path $TestDrive '.dclaude'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'pwsh'; volumes = @('C:/x:C:/y') } | ConvertTo-Json -Depth 5 |
                Set-Content (Join-Path $dir 'settings.local.json')

            Set-DClaudeProject -ImageKey 'pwsh' -Volumes @() -Path $TestDrive

            $config = Get-Content (Join-Path $dir 'settings.local.json') -Raw | ConvertFrom-Json
            $config.PSObject.Properties['volumes'] | Should -BeNullOrEmpty
        }

        It 'preserves existing volumes when -Volumes is not specified' {
            $dir = Join-Path $TestDrive '.dclaude'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'old'; volumes = @('C:/keep:C:/this') } | ConvertTo-Json -Depth 5 |
                Set-Content (Join-Path $dir 'settings.local.json')

            Set-DClaudeProject -ImageKey 'new' -Path $TestDrive

            $config = Get-Content (Join-Path $dir 'settings.local.json') -Raw | ConvertFrom-Json
            $config.imageKey | Should -Be 'new'
            $config.volumes | Should -HaveCount 1
            $config.volumes[0] | Should -Be 'C:/keep:C:/this'
        }
    }

    Context 'directory creation' {
        It 'creates .dclaude directory if it does not exist' {
            $newDir = Join-Path $TestDrive 'newproject'
            New-Item -Path $newDir -ItemType Directory -Force | Out-Null

            Set-DClaudeProject -ImageKey 'pwsh' -Path $newDir

            Join-Path $newDir '.dclaude' | Should -Exist
            Join-Path $newDir '.dclaude/settings.local.json' | Should -Exist
        }
    }

    Context 'writes to settings.local.json, not settings.json' {
        It 'only writes settings.local.json' {
            Set-DClaudeProject -ImageKey 'pwsh' -Path $TestDrive

            Join-Path $TestDrive '.dclaude/settings.local.json' | Should -Exist
            Join-Path $TestDrive '.dclaude/settings.json' | Should -Not -Exist
        }
    }
}
