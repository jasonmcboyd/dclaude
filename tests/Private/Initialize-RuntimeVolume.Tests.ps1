BeforeAll {
    . "$PSScriptRoot/../../src/Private/Initialize-RuntimeVolume.ps1"

    function docker { }
}

Describe 'Initialize-RuntimeVolume' {

    Context 'when volume is already populated (Linux)' {
        It 'returns volume info without provisioning' {
            Mock docker {
                if ($args -join ' ' -match ':/check') {
                    $global:LASTEXITCODE = 0
                }
            }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v1.0.0'
            $result.MountPath | Should -Be '/opt/dclaude-runtime'
        }
    }

    Context 'when volume is already populated (Windows)' {
        It 'returns volume info without provisioning' {
            Mock docker {
                if ($args -join ' ' -match ':C:\\check') {
                    $global:LASTEXITCODE = 0
                }
            }

            $result = Initialize-RuntimeVolume -ContainerOS 'windows' -Version ([version]'1.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-windows-v1.0.0'
            $result.MountPath | Should -Be 'C:\dclaude-runtime'
        }
    }

    Context 'when volume needs provisioning (Linux)' {
        BeforeEach {
            $script:dockerCalls = @()
            Mock docker {
                $script:dockerCalls += ($args -join ' ')
                $joined = $args -join ' '
                if ($joined -match ':/check') {
                    $global:LASTEXITCODE = 1
                }
                else {
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Write-Host { }
        }

        It 'provisions the volume and returns volume info' {
            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'2.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v2.0.0'
            $result.MountPath | Should -Be '/opt/dclaude-runtime'
            # Should have called docker twice: check + provision
            $script:dockerCalls.Count | Should -Be 2
            $script:dockerCalls[1] | Should -BeLike '*debian:bookworm-slim*'
        }

        It 'writes a provisioning message' {
            Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'2.0.0')

            Should -Invoke Write-Host -ParameterFilter { $Object -like '*provisioning runtime volume*' }
        }
    }

    Context 'when volume needs provisioning (Windows)' {
        BeforeEach {
            $script:dockerCalls = @()
            Mock docker {
                $script:dockerCalls += ($args -join ' ')
                $joined = $args -join ' '
                if ($joined -match ':C:\\check') {
                    $global:LASTEXITCODE = 1
                }
                else {
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Write-Host { }
        }

        It 'provisions the volume using servercore and returns volume info' {
            $result = Initialize-RuntimeVolume -ContainerOS 'windows' -Version ([version]'2.0.0')

            $result.VolumeName | Should -Be 'dclaude-runtime-windows-v2.0.0'
            $result.MountPath | Should -Be 'C:\dclaude-runtime'
            $script:dockerCalls.Count | Should -Be 2
            $script:dockerCalls[1] | Should -BeLike '*servercore*'
        }
    }

    Context 'when provisioning fails' {
        It 'writes an error and returns null' {
            Mock docker {
                $global:LASTEXITCODE = 1
            }
            Mock Write-Host { }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'1.0.0') -ErrorVariable err -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Failed to provision*'
        }
    }

    Context 'volume name includes version' {
        It 'uses the provided version in the volume name' {
            Mock docker {
                $global:LASTEXITCODE = 0
            }

            $result = Initialize-RuntimeVolume -ContainerOS 'linux' -Version ([version]'3.2.1')

            $result.VolumeName | Should -Be 'dclaude-runtime-linux-v3.2.1'
        }
    }
}
