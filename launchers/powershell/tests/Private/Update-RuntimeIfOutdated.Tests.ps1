BeforeAll {
    . "$PSScriptRoot/../../Private/Update-RuntimeIfOutdated.ps1"

    # Stub the collaborators so they can be mocked even though they aren't dot-sourced here.
    # Update-DClaudeRuntime declares -ContainerOS so Should -Invoke -ParameterFilter can bind it.
    function Get-CurrentRuntimeVolume { param($ContainerOS, $Version) }
    function Get-LatestClaudeCodeVersion { }
    function Get-RuntimeVolumeClaudeVersion { param($VolumeName) }
    function Update-DClaudeRuntime { param($ContainerOS, $Version) }
}

Describe 'Update-RuntimeIfOutdated' {

    BeforeEach {
        Mock Write-Host { }
        # Sensible defaults; individual contexts override the relevant collaborator.
        Mock Get-CurrentRuntimeVolume {
            return [PSCustomObject]@{ Name = 'dclaude-runtime-linux-v1.0.0-r1'; Revision = 1 }
        }
        Mock Get-LatestClaudeCodeVersion { return '2.0.0' }
        Mock Get-RuntimeVolumeClaudeVersion { return '2.0.0' }
        Mock Update-DClaudeRuntime { }
    }

    Context 'when no populated runtime volume exists' {
        It 'returns without consulting the registry or updating' {
            Mock Get-CurrentRuntimeVolume { return $null }

            Update-RuntimeIfOutdated -ContainerOS 'linux' -ModuleVersion ([version]'1.0.0')

            Should -Not -Invoke Get-LatestClaudeCodeVersion
            Should -Not -Invoke Get-RuntimeVolumeClaudeVersion
            Should -Not -Invoke Update-DClaudeRuntime
        }
    }

    Context 'when the latest version cannot be determined' {
        It 'warns and does not update' {
            Mock Get-LatestClaudeCodeVersion { return $null }

            Update-RuntimeIfOutdated -ContainerOS 'linux' -ModuleVersion ([version]'1.0.0')

            Should -Not -Invoke Get-RuntimeVolumeClaudeVersion
            Should -Not -Invoke Update-DClaudeRuntime
        }
    }

    Context 'when the installed version matches latest' {
        It 'reports up to date and does not update' {
            Mock Get-LatestClaudeCodeVersion { return '2.0.0' }
            Mock Get-RuntimeVolumeClaudeVersion { return '2.0.0' }

            Update-RuntimeIfOutdated -ContainerOS 'linux' -ModuleVersion ([version]'1.0.0')

            Should -Not -Invoke Update-DClaudeRuntime
        }
    }

    Context 'when the installed version is outdated' {
        It 'provisions a fresh runtime via Update-DClaudeRuntime' {
            Mock Get-LatestClaudeCodeVersion { return '2.0.0' }
            Mock Get-RuntimeVolumeClaudeVersion { return '1.5.0' }

            Update-RuntimeIfOutdated -ContainerOS 'linux' -ModuleVersion ([version]'1.0.0')

            Should -Invoke Update-DClaudeRuntime -Times 1 -ParameterFilter {
                $ContainerOS -eq 'linux'
            }
        }
    }

    Context 'when the selected volume is unlabeled (null installed version)' {
        It 'treats it as outdated and provisions a fresh runtime' {
            Mock Get-LatestClaudeCodeVersion { return '2.0.0' }
            Mock Get-RuntimeVolumeClaudeVersion { return $null }

            Update-RuntimeIfOutdated -ContainerOS 'linux' -ModuleVersion ([version]'1.0.0')

            Should -Invoke Update-DClaudeRuntime -Times 1 -ParameterFilter {
                $ContainerOS -eq 'linux'
            }
        }
    }

    Context 'Windows' {
        It 'passes the windows container OS through to Update-DClaudeRuntime' {
            Mock Get-CurrentRuntimeVolume {
                return [PSCustomObject]@{ Name = 'dclaude-runtime-windows-v1.0.0-r1'; Revision = 1 }
            }
            Mock Get-LatestClaudeCodeVersion { return '2.0.0' }
            Mock Get-RuntimeVolumeClaudeVersion { return '1.0.0' }

            Update-RuntimeIfOutdated -ContainerOS 'windows' -ModuleVersion ([version]'1.0.0')

            Should -Invoke Update-DClaudeRuntime -Times 1 -ParameterFilter {
                $ContainerOS -eq 'windows'
            }
        }
    }
}
