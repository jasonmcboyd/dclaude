BeforeAll {
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeConfig.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeUserConfig.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-ImageKey.ps1"
    . "$PSScriptRoot/../../src/Private/Test-DockerAvailable.ps1"
    . "$PSScriptRoot/../../src/Public/Invoke-DClaude.ps1"

    # Define a docker function so Pester can mock it
    # (the real docker CLI may not be in PATH in test environments)
    function docker { }
}

Describe 'Invoke-DClaude' {

    BeforeEach {
        # Create a workspace directory for -Path
        $script:workDir = Join-Path $TestDrive 'workspace'
        New-Item -Path $script:workDir -ItemType Directory -Force | Out-Null

        # Create a Claude config directory
        $script:claudeDir = Join-Path $TestDrive '.claude'
        New-Item -Path $script:claudeDir -ItemType Directory -Force | Out-Null

        # Create .claude.json
        $script:claudeJson = Join-Path $TestDrive '.claude.json'
        '{}' | Set-Content $script:claudeJson

        # Mock Docker to avoid real daemon calls
        Mock Test-DockerAvailable { return 'windows' }

        # Capture docker args instead of executing
        $script:capturedDockerArgs = $null
        Mock docker {
            $script:capturedDockerArgs = $args
        }

        # Suppress project config from leaking in from the real filesystem
        Mock Get-DClaudeConfig { return $null }
    }

    AfterEach {
        # Clean up any test env vars we may have set
        foreach ($key in @('ANTHROPIC_API_KEY', 'CLAUDE_CODE_TEST', 'CLOUD_ML_REGION', 'MY_CUSTOM_VAR')) {
            [Environment]::SetEnvironmentVariable($key, $null)
        }
    }

    Context 'Docker validation' {
        It 'returns early when Docker is not available' {
            Mock Test-DockerAvailable { return $null }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir
            Should -Not -Invoke docker
        }

        It 'writes an error for unsupported Docker OS types' {
            Mock Test-DockerAvailable { return 'freebsd' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Unsupported*freebsd*'
        }
    }

    Context 'image resolution with -Image parameter' {
        It 'uses the provided image tag directly' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }

            Invoke-DClaude -Image 'my-image:v1' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            Should -Invoke docker
            $script:capturedDockerArgs | Should -Contain 'my-image:v1'
        }
    }

    Context 'image resolution with -ImageKey parameter' {
        It 'resolves the image key to a tag' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }
            Mock Resolve-ImageKey {
                return [PSCustomObject]@{ tag = 'dclaude-pwsh:latest'; volumes = @() }
            }

            Invoke-DClaude -ImageKey 'pwsh' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            Should -Invoke docker
            $script:capturedDockerArgs | Should -Contain 'dclaude-pwsh:latest'
        }
    }

    Context 'image resolution from project config' {
        It 'uses image from project config when no param specified' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }
            Mock Get-DClaudeConfig {
                return [PSCustomObject]@{ image = 'project-image:v2' }
            }

            Invoke-DClaude -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            Should -Invoke docker
            $script:capturedDockerArgs | Should -Contain 'project-image:v2'
        }

        It 'resolves imageKey from project config' {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }
            Mock Get-DClaudeConfig {
                return [PSCustomObject]@{ imageKey = 'pwsh' }
            }
            Mock Resolve-ImageKey {
                return [PSCustomObject]@{ tag = 'dclaude-pwsh:latest'; volumes = @() }
            }

            Invoke-DClaude -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            Should -Invoke docker
            $script:capturedDockerArgs | Should -Contain 'dclaude-pwsh:latest'
        }
    }

    Context 'when no image is available from any source' {
        It 'writes an error' {
            Invoke-DClaude -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*No image specified*'
            Should -Not -Invoke docker
        }
    }

    Context 'container path selection' {
        BeforeEach {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }
        }

        It 'uses Windows paths when Docker OS is windows' {
            Mock Test-DockerAvailable { return 'windows' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*C:/workspace*'
            $argsString | Should -BeLike '*C:/mnt/host-claude*'
        }

        It 'uses Linux paths when Docker OS is linux' {
            Mock Test-DockerAvailable { return 'linux' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*/workspace*'
            $argsString | Should -BeLike '*/mnt/host-claude*'
        }
    }

    Context 'volume handling' {
        BeforeEach {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }
        }

        It 'appends :ro to volumes without an explicit mode' {
            Mock Resolve-ImageKey {
                return [PSCustomObject]@{
                    tag     = 'dclaude-pwsh:latest'
                    volumes = @('C:/host:C:/container')
                }
            }

            Invoke-DClaude -ImageKey 'pwsh' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*C:/host:C:/container:ro*'
        }

        It 'preserves :rw when explicitly specified' {
            Mock Resolve-ImageKey {
                return [PSCustomObject]@{
                    tag     = 'dclaude-pwsh:latest'
                    volumes = @('C:/host:C:/container:rw')
                }
            }

            Invoke-DClaude -ImageKey 'pwsh' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*C:/host:C:/container:rw*'
            $argsString | Should -Not -BeLike '*:rw:ro*'
        }

        It 'merges image-level and project-level volumes' {
            Mock Get-DClaudeConfig {
                return [PSCustomObject]@{
                    imageKey = 'pwsh'
                    volumes  = @('C:/proj-vol:C:/proj-mount:rw')
                }
            }
            Mock Resolve-ImageKey {
                return [PSCustomObject]@{
                    tag     = 'dclaude-pwsh:latest'
                    volumes = @('C:/image-vol:C:/image-mount')
                }
            }

            Invoke-DClaude -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*C:/image-vol:C:/image-mount:ro*'
            $argsString | Should -BeLike '*C:/proj-vol:C:/proj-mount:rw*'
        }
    }

    Context 'environment variable passthrough' {
        BeforeEach {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }
        }

        It 'passes ANTHROPIC_ prefixed variables' {
            [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', 'test-key')

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $script:capturedDockerArgs | Should -Contain 'ANTHROPIC_API_KEY'
        }

        It 'passes CLAUDE_CODE_ prefixed variables' {
            [Environment]::SetEnvironmentVariable('CLAUDE_CODE_TEST', 'test-val')

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $script:capturedDockerArgs | Should -Contain 'CLAUDE_CODE_TEST'
        }

        It 'passes CLOUD_ML_ prefixed variables' {
            [Environment]::SetEnvironmentVariable('CLOUD_ML_REGION', 'us-east1')

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $script:capturedDockerArgs | Should -Contain 'CLOUD_ML_REGION'
        }

        It 'does not pass unrelated environment variables' {
            [Environment]::SetEnvironmentVariable('MY_CUSTOM_VAR', 'secret')

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $script:capturedDockerArgs | Should -Not -Contain 'MY_CUSTOM_VAR'
        }

        It 'always passes DCLAUDE_HOST_PATH' {
            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*DCLAUDE_HOST_PATH=*'
        }
    }

    Context 'DCLAUDE_VOLUMES environment variable' {
        BeforeEach {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }
        }

        It 'sets DCLAUDE_VOLUMES as pipe-separated list when volumes exist' {
            Mock Resolve-ImageKey {
                return [PSCustomObject]@{
                    tag     = 'dclaude-pwsh:latest'
                    volumes = @('C:/a:C:/b', 'C:/c:C:/d:rw')
                }
            }

            Invoke-DClaude -ImageKey 'pwsh' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*DCLAUDE_VOLUMES=*'
            $argsString | Should -BeLike '*C:/a:C:/b:ro|C:/c:C:/d:rw*'
        }

        It 'does not set DCLAUDE_VOLUMES when there are no additional volumes' {
            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -Not -BeLike '*DCLAUDE_VOLUMES*'
        }
    }

    Context 'docker run arguments structure' {
        BeforeEach {
            Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }
        }

        It 'includes run -it --rm flags' {
            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $script:capturedDockerArgs[0] | Should -Be 'run'
            $script:capturedDockerArgs | Should -Contain '-it'
            $script:capturedDockerArgs | Should -Contain '--rm'
        }

        It 'passes extra ClaudeArgs at the end' {
            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ClaudeArgs '--resume', '--verbose'

            $imageIdx = [array]::IndexOf($script:capturedDockerArgs, 'test:latest')
            $resumeIdx = [array]::IndexOf($script:capturedDockerArgs, '--resume')
            $resumeIdx | Should -BeGreaterThan $imageIdx
        }
    }

    Context 'path validation' {
        It 'writes an error when path does not exist' {
            $nonexistent = Join-Path $TestDrive 'nonexistent-path'
            Invoke-DClaude -Image 'test:latest' -Path $nonexistent -ClaudeConfigPath $script:claudeDir -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*does not exist*'
            Should -Not -Invoke docker
        }
    }

    Context 'Windows .claude.json symlink check' {
        It 'errors when .claude.json is not a symlink on Windows' {
            Mock Test-DockerAvailable { return 'windows' }
            Mock Get-Item { [PSCustomObject]@{ Target = $null } } -ParameterFilter { $Path -like '*.claude.json' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*not symlinked*'
        }
    }

    Context 'Linux .claude.json mount' {
        It 'mounts .claude.json as read-only on Linux' {
            Mock Test-DockerAvailable { return 'linux' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*/mnt/host-claude.json:ro*'
        }
    }
}
