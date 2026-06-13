BeforeAll {
    . "$PSScriptRoot/../../src/Private/DClaudeConstants.ps1"
    . "$PSScriptRoot/../../src/Private/Get-RuntimeVolumeRevision.ps1"
    . "$PSScriptRoot/../../src/Private/Test-RuntimeVolumePopulated.ps1"
    . "$PSScriptRoot/../../src/Private/Get-CurrentRuntimeVolume.ps1"

    function docker { }
}

Describe 'Get-CurrentRuntimeVolume' {

    BeforeEach {
        Mock docker { return $null }
        Mock Test-RuntimeVolumePopulated { return $false }
    }

    Context 'when a single populated volume exists' {
        It 'returns its name and revision (Linux)' {
            Mock docker { return @('dclaude-runtime-linux-v1.0.0-r1') } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Get-CurrentRuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.Name | Should -Be 'dclaude-runtime-linux-v1.0.0-r1'
            $result.Revision | Should -Be 1
        }
    }

    Context 'when multiple populated revisions exist' {
        It 'returns the highest revision' {
            Mock docker {
                return @(
                    'dclaude-runtime-linux-v1.0.0',       # revision 0 (legacy)
                    'dclaude-runtime-linux-v1.0.0-r1',
                    'dclaude-runtime-linux-v1.0.0-r3',
                    'dclaude-runtime-linux-v1.0.0-r2'
                )
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Get-CurrentRuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.Name | Should -Be 'dclaude-runtime-linux-v1.0.0-r3'
            $result.Revision | Should -Be 3
        }
    }

    Context 'when the highest revision is not populated' {
        It 'returns the highest POPULATED revision' {
            Mock docker {
                return @(
                    'dclaude-runtime-linux-v1.0.0-r1',
                    'dclaude-runtime-linux-v1.0.0-r2'
                )
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated {
                return $VolumeName -eq 'dclaude-runtime-linux-v1.0.0-r1'
            }

            $result = Get-CurrentRuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.Name | Should -Be 'dclaude-runtime-linux-v1.0.0-r1'
            $result.Revision | Should -Be 1
        }
    }

    Context 'when a legacy suffixless volume is the only populated one' {
        It 'treats it as revision 0 and returns it' {
            Mock docker { return @('dclaude-runtime-linux-v1.0.0') } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Get-CurrentRuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.Name | Should -Be 'dclaude-runtime-linux-v1.0.0'
            $result.Revision | Should -Be 0
        }
    }

    Context 'when no volume is populated' {
        It 'returns null even though volumes exist' {
            Mock docker {
                return @(
                    'dclaude-runtime-linux-v1.0.0-r1',
                    'dclaude-runtime-linux-v1.0.0-r2'
                )
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $false }

            $result = Get-CurrentRuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result | Should -BeNullOrEmpty
        }

        It 'returns null when no volumes exist at all' {
            Mock docker { return $null } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }

            $result = Get-CurrentRuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when prefix-colliding volumes for another version are present' {
        It 'excludes v1.0.0 names when selecting for v1.0 (anchored revision match)' {
            # docker volume ls --filter name= is a prefix match, so a query for v1.0 surfaces
            # v1.0.0 names. Get-RuntimeVolumeRevision returns -1 for those, so they must be
            # ignored — leaving no match for v1.0.
            Mock docker {
                return @('dclaude-runtime-linux-v1.0.0-r5')
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Get-CurrentRuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0')

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Windows' {
        It 'returns the highest populated revision for Windows volumes' {
            Mock docker {
                return @(
                    'dclaude-runtime-windows-v1.0.0-r1',
                    'dclaude-runtime-windows-v1.0.0-r2'
                )
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Get-CurrentRuntimeVolume -ContainerOS 'windows' -Version ([version]'1.0.0')

            $result.Name | Should -Be 'dclaude-runtime-windows-v1.0.0-r2'
            $result.Revision | Should -Be 2
        }
    }
}
