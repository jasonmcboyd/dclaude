BeforeAll {
    . "$PSScriptRoot/../../src/Private/Save-SettingsFile.ps1"
}

Describe 'Save-SettingsFile' {

    Context 'when directory exists' {
        It 'writes settings.json' {
            $config = [PSCustomObject]@{ imageKey = 'pwsh' }

            Save-SettingsFile -Directory $TestDrive -Config $config

            $filePath = Join-Path $TestDrive 'settings.json'
            $filePath | Should -Exist
            $content = Get-Content $filePath -Raw | ConvertFrom-Json
            $content.imageKey | Should -Be 'pwsh'
        }
    }

    Context 'when directory does not exist' {
        It 'creates the directory and writes settings.json' {
            $newDir = Join-Path $TestDrive 'subdir/.dclaude'
            $config = [PSCustomObject]@{ imageKey = 'pwsh' }

            Save-SettingsFile -Directory $newDir -Config $config

            $filePath = Join-Path $newDir 'settings.json'
            $filePath | Should -Exist
        }
    }

    Context 'JSON serialization' {
        It 'preserves nested objects up to depth 10' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{
                    pwsh = [PSCustomObject]@{
                        windows = [PSCustomObject]@{
                            tag     = 'dclaude-pwsh:latest'
                            volumes = @('C:/host:C:/container:ro')
                        }
                    }
                }
            }

            Save-SettingsFile -Directory $TestDrive -Config $config

            $filePath = Join-Path $TestDrive 'settings.json'
            $content = Get-Content $filePath -Raw | ConvertFrom-Json
            $content.images.pwsh.windows.tag | Should -Be 'dclaude-pwsh:latest'
            $content.images.pwsh.windows.volumes | Should -Contain 'C:/host:C:/container:ro'
        }

        It 'overwrites existing settings.json' {
            $first = [PSCustomObject]@{ version = 1 }
            $second = [PSCustomObject]@{ version = 2 }

            Save-SettingsFile -Directory $TestDrive -Config $first
            Save-SettingsFile -Directory $TestDrive -Config $second

            $filePath = Join-Path $TestDrive 'settings.json'
            $content = Get-Content $filePath -Raw | ConvertFrom-Json
            $content.version | Should -Be 2
        }
    }

    Context 'custom FileName parameter' {
        It 'writes to the specified filename instead of settings.json' {
            $config = [PSCustomObject]@{ imageKey = 'pwsh' }

            Save-SettingsFile -Directory $TestDrive -Config $config -FileName 'settings.local.json'

            $filePath = Join-Path $TestDrive 'settings.local.json'
            $filePath | Should -Exist
            $content = Get-Content $filePath -Raw | ConvertFrom-Json
            $content.imageKey | Should -Be 'pwsh'

            $defaultPath = Join-Path $TestDrive 'settings.json'
            $defaultPath | Should -Not -Exist
        }
    }
}
