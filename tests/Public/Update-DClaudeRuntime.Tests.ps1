BeforeAll {
    . "$PSScriptRoot/../../src/Private/Get-DockerContainerOS.ps1"
    . "$PSScriptRoot/../../src/Private/Get-DClaudeModuleVersion.ps1"
    . "$PSScriptRoot/../../src/Private/Get-RuntimeVolumeRevision.ps1"
    . "$PSScriptRoot/../../src/Private/New-RuntimeVolume.ps1"
    . "$PSScriptRoot/../../src/Private/Remove-StaleRuntimeVolumes.ps1"
    . "$PSScriptRoot/../../src/Public/Update-DClaudeRuntime.ps1"

    function docker { }
}

Describe 'Update-DClaudeRuntime' {

    BeforeEach {
        Mock Get-DockerContainerOS { return 'linux' }
        Mock Get-DClaudeModuleVersion { return [version]'1.0.0' }
        # Default: no existing volumes.
        Mock docker { return $null }
        Mock New-RuntimeVolume { return $true }
        Mock Remove-StaleRuntimeVolumes { }
        Mock Write-Host { }
    }

    Context 'ContainerOS resolution' {
        It 'defaults ContainerOS from Get-DockerContainerOS when omitted' {
            Update-DClaudeRuntime

            Should -Invoke Get-DockerContainerOS -Times 1
            Should -Invoke New-RuntimeVolume -ParameterFilter { $ContainerOS -eq 'linux' }
        }

        It 'normalizes a capitalized OS type to lowercase' {
            Mock Get-DockerContainerOS { return 'Windows' }

            Update-DClaudeRuntime

            Should -Invoke New-RuntimeVolume -ParameterFilter {
                $ContainerOS -eq 'windows' -and $VolumeName -like 'dclaude-runtime-windows-*'
            }
        }

        It 'honors an explicit -ContainerOS without calling Get-DockerContainerOS' {
            Update-DClaudeRuntime -ContainerOS 'windows'

            Should -Not -Invoke Get-DockerContainerOS
            Should -Invoke New-RuntimeVolume -ParameterFilter { $ContainerOS -eq 'windows' }
        }
    }

    Context 'next revision computation' {
        It 'provisions revision 1 when no volumes exist' {
            Mock docker { return $null } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }

            Update-DClaudeRuntime -ContainerOS 'linux'

            Should -Invoke New-RuntimeVolume -ParameterFilter {
                $VolumeName -eq 'dclaude-runtime-linux-v1.0.0-r1'
            }
        }

        It 'provisions max existing revision + 1' {
            Mock docker {
                return @(
                    'dclaude-runtime-linux-v1.0.0',       # revision 0
                    'dclaude-runtime-linux-v1.0.0-r1',
                    'dclaude-runtime-linux-v1.0.0-r4',
                    'dclaude-runtime-linux-v1.0.0-r2'
                )
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }

            Update-DClaudeRuntime -ContainerOS 'linux'

            Should -Invoke New-RuntimeVolume -ParameterFilter {
                $VolumeName -eq 'dclaude-runtime-linux-v1.0.0-r5'
            }
        }

        It 'ignores prefix-colliding names for other versions' {
            # docker volume ls is a prefix match; a v1.0.0 entry must not influence a v1.0 update.
            Mock Get-DClaudeModuleVersion { return [version]'1.0' }
            Mock docker {
                return @('dclaude-runtime-linux-v1.0.0-r9')
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }

            Update-DClaudeRuntime -ContainerOS 'linux'

            Should -Invoke New-RuntimeVolume -ParameterFilter {
                $VolumeName -eq 'dclaude-runtime-linux-v1.0-r1'
            }
        }
    }

    Context 'version passthrough' {
        It 'passes -Version through as -ClaudeCodeVersion' {
            Update-DClaudeRuntime -ContainerOS 'linux' -Version '2.3.4'

            Should -Invoke New-RuntimeVolume -ParameterFilter {
                $ClaudeCodeVersion -eq '2.3.4'
            }
        }
    }

    Context 'cleanup' {
        It 'reclaims superseded volumes after a successful provision' {
            Update-DClaudeRuntime -ContainerOS 'linux'

            Should -Invoke Remove-StaleRuntimeVolumes -ParameterFilter {
                $CurrentVersion -eq [version]'1.0.0'
            }
        }
    }

    Context 'WhatIf support' {
        It 'does not provision or clean up when -WhatIf is used' {
            Update-DClaudeRuntime -ContainerOS 'linux' -WhatIf

            Should -Not -Invoke New-RuntimeVolume
            Should -Not -Invoke Remove-StaleRuntimeVolumes
        }
    }

    Context 'error handling' {
        # When Get-DockerContainerOS fails it returns $null; Update-DClaudeRuntime resolves
        # the OS into a plain local (NOT back into the [ValidateSet] parameter, which would
        # re-validate and throw), so it returns cleanly without provisioning.
        It 'returns without provisioning when Get-DockerContainerOS fails' {
            Mock Get-DockerContainerOS { return $null }

            { Update-DClaudeRuntime } | Should -Not -Throw
            Should -Not -Invoke New-RuntimeVolume
        }

        It 'writes an error when provisioning fails' {
            Mock New-RuntimeVolume { return $false }

            Update-DClaudeRuntime -ContainerOS 'linux' -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Failed to provision*'
            Should -Not -Invoke Remove-StaleRuntimeVolumes
        }
    }
}
