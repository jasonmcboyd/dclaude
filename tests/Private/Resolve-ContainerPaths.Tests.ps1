BeforeAll {
    . "$PSScriptRoot/../../src/Private/ConvertTo-ContainerPath.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-ContainerPaths.ps1"
}

Describe 'Resolve-ContainerPaths' {

    BeforeEach {
        $script:claudeDir = Join-Path $TestDrive '.claude'
        New-Item -Path $script:claudeDir -ItemType Directory -Force | Out-Null

        $script:claudeJson = Join-Path $TestDrive '.claude.json'
        '{}' | Set-Content $script:claudeJson
    }

    Context 'container path selection' {
        It 'converts the resolved path via ConvertTo-ContainerPath for the workspace' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }

            $result = Resolve-ContainerPaths -ContainerOS 'windows' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            # On Windows containers, the path is passed through unchanged
            $expectedWorkspace = ConvertTo-ContainerPath -HostPath $TestDrive -ContainerOS 'windows'
            $result.Workspace | Should -Be $expectedWorkspace
        }

        It 'returns Linux-converted paths when ContainerOS is linux' {
            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $expectedWorkspace = ConvertTo-ContainerPath -HostPath $TestDrive -ContainerOS 'linux'
            $result.Workspace | Should -Be $expectedWorkspace
        }

        It 'converts a Windows-style resolved path to Linux container path' {
            Mock Test-Path { $true }
            Mock Get-Item { [PSCustomObject]@{ Target = $null } } -ParameterFilter { $Path -like '*.claude.json' }

            $windowsPath = 'C:\Users\jason\repos\myproject'
            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $windowsPath -ClaudeConfigPath $script:claudeDir
            $result.Workspace | Should -Be '/c/Users/jason/repos/myproject'
        }
    }

    Context 'Claude config directory mount' {
        It 'mounts directly at ContainerAdministrator home on Windows' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }

            $result = Resolve-ContainerPaths -ContainerOS 'windows' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike "*$($script:claudeDir):C:/Users/ContainerAdministrator/.claude:rw*"
        }

        It 'mounts directly at claude home on Linux' {
            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike "*$($script:claudeDir):/home/claude/.claude:rw*"
        }

        It 'emits a warning when claude config path does not exist' {
            $nonexistent = Join-Path $TestDrive 'nonexistent-claude'

            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $nonexistent -WarningVariable warn -WarningAction SilentlyContinue
            $warn | Should -Not -BeNullOrEmpty
            $result.Errors | Should -HaveCount 0
        }
    }

    Context '.claude.json on Linux' {
        It 'mounts .claude.json inside the direct mount as read-only' {
            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike '*:/home/claude/.claude/.claude.json:ro*'
        }
    }

    Context '.claude.json on Windows' {
        It 'returns an error when .claude.json is not a symlink' {
            Mock Get-Item { [PSCustomObject]@{ Target = $null } } -ParameterFilter { $Path -like '*.claude.json' }

            $result = Resolve-ContainerPaths -ContainerOS 'windows' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $result.Errors | Should -HaveCount 1
            $result.Errors[0] | Should -BeLike '*not symlinked*'
        }

        It 'returns no error when .claude.json is a symlink' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }

            $result = Resolve-ContainerPaths -ContainerOS 'windows' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $result.Errors | Should -HaveCount 0
        }
    }

    Context 'cross-platform directory masking' {
        It 'adds tmpfs overlays for plugins and session-env on Linux' {
            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike '*type=tmpfs,destination=/home/claude/.claude/plugins*'
            $argsString | Should -BeLike '*type=tmpfs,destination=/home/claude/.claude/session-env*'
        }

        It 'does not add tmpfs overlays on Windows' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }

            $result = Resolve-ContainerPaths -ContainerOS 'windows' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -Not -BeLike '*tmpfs*'
        }
    }

    Context 'project directory bind-mount' {
        It 'derives container key from converted workspace path on Linux' {
            $hostKey = $TestDrive -replace '[/\\:]', '-'
            $projectDir = Join-Path $script:claudeDir 'projects' $hostKey
            New-Item -Path $projectDir -ItemType Directory -Force | Out-Null

            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir

            $convertedWorkspace = ConvertTo-ContainerPath -HostPath $TestDrive -ContainerOS 'linux'
            $expectedContainerKey = $convertedWorkspace -replace '[/\\:]', '-'
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike "*:/home/claude/.claude/projects/$expectedContainerKey*"
        }

        It 'derives container key from workspace path on Windows' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }

            $hostKey = $TestDrive -replace '[/\\:]', '-'
            $projectDir = Join-Path $script:claudeDir 'projects' $hostKey
            New-Item -Path $projectDir -ItemType Directory -Force | Out-Null

            $result = Resolve-ContainerPaths -ContainerOS 'windows' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir

            $convertedWorkspace = ConvertTo-ContainerPath -HostPath $TestDrive -ContainerOS 'windows'
            $expectedContainerKey = $convertedWorkspace -replace '[/\\:]', '-'
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike "*:C:/Users/ContainerAdministrator/.claude/projects/$expectedContainerKey*"
        }

        It 'uses cross-platform converted path for container key when Windows path targets Linux container' {
            Mock Test-Path { $true }
            Mock Get-Item { [PSCustomObject]@{ Target = $null } } -ParameterFilter { $Path -like '*.claude.json' }

            $windowsPath = 'C:\Users\jason\repos'
            $hostKey = $windowsPath -replace '[/\\:]', '-'
            $projectDir = Join-Path $script:claudeDir 'projects' $hostKey
            New-Item -Path $projectDir -ItemType Directory -Force | Out-Null

            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $windowsPath -ClaudeConfigPath $script:claudeDir

            $expectedContainerKey = '/c/Users/jason/repos' -replace '[/\\:]', '-'
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike "*:/home/claude/.claude/projects/$expectedContainerKey*"
        }

        It 'does not add project volume when host project dir does not exist' {
            $otherDir = Join-Path $TestDrive 'other-workspace'
            New-Item -Path $otherDir -ItemType Directory -Force | Out-Null

            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $otherDir -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -Not -BeLike '*projects/*'
        }
    }

    Context 'when .claude.json does not exist' {
        It 'skips the .claude.json volume and produces no error' {
            $noJsonDir = Join-Path $TestDrive 'nojson'
            $claudeConfigDir = Join-Path $noJsonDir '.claude'
            New-Item -Path $claudeConfigDir -ItemType Directory -Force | Out-Null

            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $claudeConfigDir
            $result.Errors | Should -HaveCount 0
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -Not -BeLike '*.claude.json:ro*'
        }
    }
}
