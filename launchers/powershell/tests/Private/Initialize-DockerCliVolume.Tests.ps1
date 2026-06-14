BeforeAll {
    . "$PSScriptRoot/../../Private/DClaudeConstants.ps1"
    . "$PSScriptRoot/../../Private/Initialize-DockerCliVolume.ps1"

    function docker { }
}

Describe 'Initialize-DockerCliVolume' {

    Context 'when volume is already populated (Linux)' {
        It 'returns volume info without provisioning' {
            Mock docker {
                if ($args -join ' ' -match ':/check') {
                    $global:LASTEXITCODE = 0
                }
            }

            $result = Initialize-DockerCliVolume -ContainerOS 'linux'
            $result.VolumeName | Should -Be 'dclaude-docker-cli-linux'
            $result.MountPath | Should -Be '/opt/docker-cli'
            Should -Invoke docker -Times 1 -Exactly
        }
    }

    Context 'when volume is already populated (Windows)' {
        It 'returns volume info without provisioning' {
            Mock docker {
                if ($args -join ' ' -match ':/check' -or $args -join ' ' -match 'C:\\check') {
                    $global:LASTEXITCODE = 0
                }
            }

            $result = Initialize-DockerCliVolume -ContainerOS 'windows'
            $result.VolumeName | Should -Be 'dclaude-docker-cli-windows'
            $result.MountPath | Should -Be 'C:/docker-cli'
            Should -Invoke docker -Times 1 -Exactly
        }
    }

    Context 'when volume needs provisioning (Linux)' {
        It 'provisions and returns volume info' {
            $script:callCount = 0
            Mock docker {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    $global:LASTEXITCODE = 1
                }
                else {
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Write-Host { }

            $result = Initialize-DockerCliVolume -ContainerOS 'linux'
            $result.VolumeName | Should -Be 'dclaude-docker-cli-linux'
            Should -Invoke docker -Times 2 -Exactly
        }

        It 'writes a provisioning message' {
            Mock docker { $global:LASTEXITCODE = 1 }
            Mock Write-Host { }

            Initialize-DockerCliVolume -ContainerOS 'linux' -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke Write-Host -ParameterFilter { $Object -like '*Provisioning Docker CLI*' }
        }
    }

    Context 'when volume needs provisioning (Windows)' {
        It 'provisions using servercore and returns volume info' {
            $script:callCount = 0
            Mock docker {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    $global:LASTEXITCODE = 1
                }
                else {
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Write-Host { }

            $result = Initialize-DockerCliVolume -ContainerOS 'windows'
            $result.VolumeName | Should -Be 'dclaude-docker-cli-windows'
            Should -Invoke docker -Times 2 -Exactly
        }
    }

    Context 'when provisioning fails' {
        It 'writes an error and returns null' {
            Mock docker { $global:LASTEXITCODE = 1 }
            Mock Write-Host { }

            $result = Initialize-DockerCliVolume -ContainerOS 'linux' -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Failed to provision Docker CLI*'
        }
    }
}
