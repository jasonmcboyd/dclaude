BeforeAll {
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../src/Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeConfig.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeUserConfig.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-ImageKey.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DockerContainerOS.ps1"
    . "$PSScriptRoot/../../src/Private/Set-VolumeDefaultMode.ps1"
    . "$PSScriptRoot/../../src/Private/Resolve-ContainerPaths.ps1"
    . "$PSScriptRoot/../../src/Private/Get-VolumeArgs.ps1"
    . "$PSScriptRoot/../../src/Private/Get-EnvironmentPassthroughArgs.ps1"
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
        Mock Get-DockerContainerOS { return 'windows' }

        # Capture docker args instead of executing
        $script:capturedDockerArgs = $null
        Mock docker {
            $script:capturedDockerArgs = $args
        }

        # Suppress project config from leaking in from the real filesystem
        Mock Get-DClaudeConfig { return $null }

        # Default .claude.json symlink check — returns a valid symlink target.
        # The 'Windows .claude.json symlink check' context overrides this with Target = $null.
        Mock Get-Item { [PSCustomObject]@{ Target = 'something' } } -ParameterFilter { $Path -like '*.claude.json' }
    }

    AfterEach {
        # Clean up any test env vars we may have set
        foreach ($key in @('ANTHROPIC_API_KEY', 'CLAUDE_CODE_TEST', 'CLOUD_ML_REGION', 'MY_CUSTOM_VAR')) {
            [Environment]::SetEnvironmentVariable($key, $null)
        }
    }

    Context 'Docker validation' {
        It 'returns early when Docker is not available' {
            Mock Get-DockerContainerOS { return $null }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir
            Should -Not -Invoke docker
        }

        It 'writes an error for unsupported Docker OS types' {
            Mock Get-DockerContainerOS { return 'freebsd' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Unsupported*freebsd*'
        }
    }

    Context 'image resolution with -Image parameter' {
        It 'uses the provided image tag directly' {
            Invoke-DClaude -Image 'my-image:v1' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            Should -Invoke docker
            $script:capturedDockerArgs | Should -Contain 'my-image:v1'
        }
    }

    Context 'image resolution with -ImageKey parameter' {
        It 'resolves the image key to a tag' {
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
            Mock Get-DClaudeConfig {
                return [PSCustomObject]@{ image = 'project-image:v2' }
            }

            Invoke-DClaude -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            Should -Invoke docker
            $script:capturedDockerArgs | Should -Contain 'project-image:v2'
        }

        It 'resolves imageKey from project config' {
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

    Context 'image takes precedence over imageKey in project config' {
        It 'uses image and does not call Resolve-ImageKey' {
            Mock Get-DClaudeConfig {
                return [PSCustomObject]@{
                    image    = 'direct-image:v1'
                    imageKey = 'pwsh'
                }
            }
            Mock Resolve-ImageKey {
                return [PSCustomObject]@{ tag = 'dclaude-pwsh:latest'; volumes = @() }
            }

            Invoke-DClaude -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            Should -Invoke docker
            $script:capturedDockerArgs -join ' ' | Should -BeLike '*direct-image:v1*'
            Should -Not -Invoke Resolve-ImageKey
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
        It 'uses Windows paths when Docker OS is windows' {
            Mock Get-DockerContainerOS { return 'windows' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*C:/workspace*'
            $argsString | Should -BeLike '*C:/mnt/host-claude*'
        }

        It 'uses Linux paths when Docker OS is linux' {
            Mock Get-DockerContainerOS { return 'linux' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*/workspace*'
            $argsString | Should -BeLike '*/mnt/host-claude*'
        }

        It 'normalizes capitalized OS type to lowercase' {
            Mock Get-DockerContainerOS { return 'Linux' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*/workspace*'
        }
    }

    Context 'workspace mount mode' {
        It 'mounts workspace with explicit :rw mode' {
            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -Match ":\S+workspace:rw"
        }
    }

    Context 'volume handling' {
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
            Mock Get-DockerContainerOS { return 'windows' }
            Mock Get-Item { [PSCustomObject]@{ Target = $null } } -ParameterFilter { $Path -like '*.claude.json' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*not symlinked*'
        }
    }

    Context 'Linux .claude.json mount' {
        It 'mounts .claude.json as read-only on Linux' {
            Mock Get-DockerContainerOS { return 'linux' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*/mnt/host-claude.json:ro*'
        }
    }

    Context 'mount display on startup' {
        It 'writes volume mounts to host before launching' {
            Mock Write-Host { }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'dclaude: mounting volumes:' }
        }

        It 'displays user-configured volumes' {
            Mock Write-Host { }
            Mock Resolve-ImageKey {
                return [PSCustomObject]@{
                    tag     = 'dclaude-pwsh:latest'
                    volumes = @('C:/host-data:C:/container-data')
                }
            }

            Invoke-DClaude -ImageKey 'pwsh' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            Should -Invoke Write-Host -ParameterFilter { $Object -like '*C:/host-data:C:/container-data*' }
        }
    }

    Context 'when Resolve-ImageKey fails' {
        It 'emits only one error when -ImageKey resolve fails' {
            Mock Resolve-ImageKey {
                Write-Error "Image key 'bad' not found"
                return $null
            }

            Invoke-DClaude -ImageKey 'bad' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -HaveCount 1
            $err[0].ToString() | Should -BeLike "*not found*"
            Should -Not -Invoke docker
        }

        It 'emits only one error when imageKey from project config resolve fails' {
            Mock Get-DClaudeConfig {
                return [PSCustomObject]@{ imageKey = 'missing' }
            }
            Mock Resolve-ImageKey {
                Write-Error "Image key 'missing' not found"
                return $null
            }

            Invoke-DClaude -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -HaveCount 1
            $err[0].ToString() | Should -BeLike "*not found*"
            Should -Not -Invoke docker
        }
    }

    Context 'Linux ambient capabilities' {
        It 'omits --security-opt=no-new-privileges for Linux (entrypoint sets it via setpriv)' {
            Mock Get-DockerContainerOS { return 'linux' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $script:capturedDockerArgs | Should -Not -Contain '--security-opt=no-new-privileges'
        }

        It 'includes --security-opt=no-new-privileges for Windows containers' {
            Mock Get-DockerContainerOS { return 'windows' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $script:capturedDockerArgs | Should -Contain '--security-opt=no-new-privileges'
        }
    }

    Context 'Docker access' {
        It 'mounts Docker socket on Linux when -DockerAccess is specified' {
            Mock Get-DockerContainerOS { return 'linux' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -DockerAccess

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*/var/run/docker.sock:/var/run/docker.sock:rw*'
        }

        It 'mounts Docker named pipe on Windows when -DockerAccess is specified' {
            Mock Get-DockerContainerOS { return 'windows' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -DockerAccess

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -BeLike '*//./pipe/docker_engine://./pipe/docker_engine*'
        }

        It 'does not mount Docker socket when -DockerAccess is not specified' {
            Mock Get-DockerContainerOS { return 'linux' }

            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir

            $argsString = $script:capturedDockerArgs -join ' '
            $argsString | Should -Not -BeLike '*docker.sock*'
        }
    }

    Context 'help flag interception' {
        BeforeEach {
            Mock Get-Help { }
        }

        It 'shows dclaude help and does not call docker when ClaudeArgs is --help' {
            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ClaudeArgs '--help'

            Should -Invoke Get-Help -ParameterFilter { $Name -eq 'Invoke-DClaude' }
            Should -Not -Invoke docker
        }

        It 'shows dclaude help and does not call docker when ClaudeArgs is -h' {
            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ClaudeArgs '-h'

            Should -Invoke Get-Help -ParameterFilter { $Name -eq 'Invoke-DClaude' }
            Should -Not -Invoke docker
        }

        It 'passes args through to claude normally when --help appears with other arguments' {
            Invoke-DClaude -Image 'test:latest' -Path $script:workDir -ClaudeConfigPath $script:claudeDir -ClaudeArgs '--help', '--resume'

            Should -Not -Invoke Get-Help
            Should -Invoke docker
        }
    }
}
