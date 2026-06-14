BeforeAll {
    . "$PSScriptRoot/../../Private/Resolve-SettingsScope.ps1"
}

Describe 'Resolve-SettingsScope' {

    Context 'User scope' {
        It 'returns ~/.dclaude with settings.json' {
            $result = Resolve-SettingsScope -Scope User
            $result.Directory | Should -Be (Join-Path $HOME '.dclaude')
            $result.FileName | Should -Be 'settings.json'
        }
    }

    Context 'Project scope' {
        It 'finds .dclaude directory in the current path' {
            $projectDir = Join-Path $TestDrive 'myproject'
            $dclaudeDir = Join-Path $projectDir '.dclaude'
            New-Item -ItemType Directory -Path $dclaudeDir -Force | Out-Null

            $result = Resolve-SettingsScope -Scope Project -Path $projectDir
            $result.Directory | Should -Be $dclaudeDir
            $result.FileName | Should -Be 'settings.json'
        }

        It 'walks up the directory tree to find .dclaude' {
            $projectDir = Join-Path $TestDrive 'myproject'
            $dclaudeDir = Join-Path $projectDir '.dclaude'
            $subDir = Join-Path $projectDir 'src' 'deep'
            New-Item -ItemType Directory -Path $dclaudeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null

            $result = Resolve-SettingsScope -Scope Project -Path $subDir
            $result.Directory | Should -Be $dclaudeDir
            $result.FileName | Should -Be 'settings.json'
        }

        It 'errors when no .dclaude directory exists' {
            $emptyDir = Join-Path $TestDrive 'empty'
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            # $TestDrive lives under the real user profile; without this the walk-up
            # would discover the developer's real ~/.dclaude and not error.
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*.dclaude' }

            $result = Resolve-SettingsScope -Scope Project -Path $emptyDir -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*No .dclaude project directory found*'
        }
    }

    Context 'ProjectLocal scope' {
        It 'returns settings.local.json filename' {
            $projectDir = Join-Path $TestDrive 'myproject2'
            $dclaudeDir = Join-Path $projectDir '.dclaude'
            New-Item -ItemType Directory -Path $dclaudeDir -Force | Out-Null

            $result = Resolve-SettingsScope -Scope ProjectLocal -Path $projectDir
            $result.Directory | Should -Be $dclaudeDir
            $result.FileName | Should -Be 'settings.local.json'
        }

        It 'errors when no .dclaude directory exists' {
            $emptyDir = Join-Path $TestDrive 'empty2'
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            # $TestDrive lives under the real user profile; without this the walk-up
            # would discover the developer's real ~/.dclaude and not error.
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*.dclaude' }

            $result = Resolve-SettingsScope -Scope ProjectLocal -Path $emptyDir -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }
    }
}
