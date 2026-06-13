BeforeAll {
    . "$PSScriptRoot/../../src/Private/DClaudeConstants.ps1"
    . "$PSScriptRoot/../../src/Private/Get-RuntimeVolumeRevision.ps1"
    . "$PSScriptRoot/../../src/Private/Test-RuntimeVolumePopulated.ps1"
    . "$PSScriptRoot/../../src/Private/New-RuntimeVolume.ps1"
    . "$PSScriptRoot/../../src/Private/Initialize-RuntimeVolume.ps1"

    function docker { }
}

Describe 'Initialize-RuntimeVolume' {

    BeforeEach {
        # By default no volumes exist; individual tests override the 'volume ls' result.
        Mock docker { return $null }
        Mock Test-RuntimeVolumePopulated { return $false }
        Mock New-RuntimeVolume { return $true }
        Mock Write-Host { }
    }

    Context 'when a populated volume already exists (Linux)' {
        It 'returns the volume without provisioning' {
            Mock docker { return @('dclaude-runtime-linux-v1.0.0-r1') } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v1.0.0-r1'
            $result.MountPath | Should -Be '/opt/dclaude-runtime'
            Should -Not -Invoke New-RuntimeVolume
        }
    }

    Context 'when a populated legacy (suffixless) volume exists' {
        It 'treats it as revision 0 and returns it' {
            Mock docker { return @('dclaude-runtime-linux-v1.0.0') } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v1.0.0'
            Should -Not -Invoke New-RuntimeVolume
        }
    }

    Context 'when a populated volume already exists (Windows)' {
        It 'returns the volume with the Windows mount path' {
            Mock docker { return @('dclaude-runtime-windows-v1.0.0-r1') } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Initialize-RuntimeVolume -ContainerOS 'windows' -Version ([version]'1.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-windows-v1.0.0-r1'
            $result.MountPath | Should -Be 'C:\dclaude-runtime'
            Should -Not -Invoke New-RuntimeVolume
        }
    }

    Context 'when multiple revisions are present and all populated' {
        It 'returns the highest revision' {
            Mock docker {
                return @(
                    'dclaude-runtime-linux-v1.0.0',       # revision 0
                    'dclaude-runtime-linux-v1.0.0-r1',
                    'dclaude-runtime-linux-v1.0.0-r3',
                    'dclaude-runtime-linux-v1.0.0-r2'
                )
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v1.0.0-r3'
            Should -Not -Invoke New-RuntimeVolume
        }
    }

    Context 'when the highest revision is NOT populated but a lower one is' {
        It 'returns the highest POPULATED revision (does not provision)' {
            Mock docker {
                return @(
                    'dclaude-runtime-linux-v1.0.0-r1',
                    'dclaude-runtime-linux-v1.0.0-r2'
                )
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            # r2 (highest) is unpopulated, r1 is populated
            Mock Test-RuntimeVolumePopulated {
                return $VolumeName -eq 'dclaude-runtime-linux-v1.0.0-r1'
            }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v1.0.0-r1'
            Should -Not -Invoke New-RuntimeVolume
        }
    }

    Context 'when prefix-colliding volumes for another version are present' {
        It 'ignores v1.0.0 entries when resolving v1.0 and provisions fresh' {
            # docker volume ls --filter name= is a prefix match, so a query for v1.0 would
            # surface v1.0.0 names. Get-RuntimeVolumeRevision returns -1 for those, so they
            # must be ignored and a fresh revision provisioned.
            Mock docker {
                return @('dclaude-runtime-linux-v1.0.0-r5')
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $true }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0')

            # No matching populated volume -> provisions r1 for v1.0
            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v1.0-r1'
            Should -Invoke New-RuntimeVolume -ParameterFilter {
                $VolumeName -eq 'dclaude-runtime-linux-v1.0-r1'
            }
        }
    }

    Context 'when no volumes exist at all' {
        It 'provisions revision 1 and returns it (Linux)' {
            Mock docker { return $null } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'2.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v2.0.0-r1'
            $result.MountPath | Should -Be '/opt/dclaude-runtime'
            Should -Invoke New-RuntimeVolume -ParameterFilter {
                $ContainerOS -eq 'linux' -and $VolumeName -eq 'dclaude-runtime-linux-v2.0.0-r1'
            }
        }

        It 'provisions revision 1 and returns it (Windows)' {
            Mock docker { return $null } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }

            $result = Initialize-RuntimeVolume -ContainerOS 'windows' -Version ([version]'2.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-windows-v2.0.0-r1'
            $result.MountPath | Should -Be 'C:\dclaude-runtime'
        }
    }

    Context 'when volumes exist but none are populated' {
        It 'provisions the next revision (maxRevision + 1)' {
            Mock docker {
                return @(
                    'dclaude-runtime-linux-v1.0.0-r1',
                    'dclaude-runtime-linux-v1.0.0-r2'
                )
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $false }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v1.0.0-r3'
            Should -Invoke New-RuntimeVolume -ParameterFilter {
                $VolumeName -eq 'dclaude-runtime-linux-v1.0.0-r3'
            }
        }

        It 'treats a legacy suffixless volume as revision 0 when computing next revision' {
            Mock docker {
                return @('dclaude-runtime-linux-v1.0.0')
            } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock Test-RuntimeVolumePopulated { return $false }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            # max revision is 0 (legacy) -> next is 1
            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v1.0.0-r1'
        }
    }

    Context 'when provisioning fails' {
        It 'writes an error and returns null' {
            Mock docker { return $null } `
                -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }
            Mock New-RuntimeVolume { return $false }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0') -ErrorVariable err -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Failed to provision*'
        }
    }
}
