BeforeAll {
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
        It 'returns Windows paths when ContainerOS is windows' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }

            $result = Resolve-ContainerPaths -ContainerOS 'windows' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $result.Workspace | Should -Be 'C:/workspace'
            $result.ClaudeMount | Should -Be 'C:/mnt/host-claude'
        }

        It 'returns Linux paths when ContainerOS is linux' {
            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $result.Workspace | Should -Be '/workspace'
            $result.ClaudeMount | Should -Be '/mnt/host-claude'
        }
    }

    Context 'Claude config directory mount' {
        It 'adds a volume arg when claude config path exists' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }

            $result = Resolve-ContainerPaths -ContainerOS 'windows' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike "*$($script:claudeDir):C:/mnt/host-claude:rw*"
        }

        It 'emits a warning when claude config path does not exist' {
            $nonexistent = Join-Path $TestDrive 'nonexistent-claude'

            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $nonexistent -WarningVariable warn -WarningAction SilentlyContinue
            $warn | Should -Not -BeNullOrEmpty
            $result.Errors | Should -HaveCount 0
        }
    }

    Context '.claude.json on Linux' {
        It 'mounts .claude.json as read-only' {
            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike '*:/mnt/host-claude.json:ro*'
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

    Context 'project directory bind-mount' {
        It 'adds volume arg when host project dir exists on Linux' {
            $hostKey = $TestDrive -replace '[/\\:]', '-'
            $projectDir = Join-Path $script:claudeDir 'projects' $hostKey
            New-Item -Path $projectDir -ItemType Directory -Force | Out-Null

            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike '*:/home/claude/.claude/projects/-workspace*'
        }

        It 'adds volume arg when host project dir exists on Windows' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }

            $hostKey = $TestDrive -replace '[/\\:]', '-'
            $projectDir = Join-Path $script:claudeDir 'projects' $hostKey
            New-Item -Path $projectDir -ItemType Directory -Force | Out-Null

            $result = Resolve-ContainerPaths -ContainerOS 'windows' -ResolvedPath $TestDrive -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -BeLike '*:C:/Users/ContainerAdministrator/.claude/projects/C--workspace*'
        }

        It 'does not add project volume when host project dir does not exist' {
            # Use a different resolved path that has no matching project dir under .claude/projects/
            $otherDir = Join-Path $TestDrive 'other-workspace'
            New-Item -Path $otherDir -ItemType Directory -Force | Out-Null

            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $otherDir -ClaudeConfigPath $script:claudeDir
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -Not -BeLike '*projects/-workspace*'
        }
    }

    Context 'when .claude.json does not exist' {
        It 'skips the .claude.json volume and produces no error' {
            $noJsonDir = Join-Path $TestDrive 'nojson'
            $claudeConfigDir = Join-Path $noJsonDir '.claude'
            New-Item -Path $claudeConfigDir -ItemType Directory -Force | Out-Null
            # Deliberately do NOT create a .claude.json in $noJsonDir

            $result = Resolve-ContainerPaths -ContainerOS 'linux' -ResolvedPath $TestDrive -ClaudeConfigPath $claudeConfigDir
            $result.Errors | Should -HaveCount 0
            $argsString = $result.DockerArgs -join ' '
            $argsString | Should -Not -BeLike '*host-claude.json*'
        }
    }
}
