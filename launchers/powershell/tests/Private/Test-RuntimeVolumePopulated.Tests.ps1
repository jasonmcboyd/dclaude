BeforeAll {
    . "$PSScriptRoot/../../Private/DClaudeConstants.ps1"
    . "$PSScriptRoot/../../Private/Test-RuntimeVolumePopulated.ps1"

    function docker { }
}

Describe 'Test-RuntimeVolumePopulated' {

    Context 'Linux' {
        It 'returns true when the node check exits 0' {
            Mock docker { $global:LASTEXITCODE = 0 }

            Test-RuntimeVolumePopulated -ContainerOS 'linux' -VolumeName 'v' | Should -BeTrue
        }

        It 'returns false when the node check exits non-zero' {
            Mock docker { $global:LASTEXITCODE = 1 }

            Test-RuntimeVolumePopulated -ContainerOS 'linux' -VolumeName 'v' | Should -BeFalse
        }

        It 'mounts the volume read-side and checks for the node binary' {
            $script:joined = $null
            Mock docker {
                $script:joined = $args -join ' '
                $global:LASTEXITCODE = 0
            }

            Test-RuntimeVolumePopulated -ContainerOS 'linux' -VolumeName 'myvol' | Out-Null

            $script:joined | Should -BeLike '*myvol:/check*'
            $script:joined | Should -BeLike '*test -f /check/node/bin/node*'
        }
    }

    Context 'Windows' {
        It 'returns true when the node check exits 0' {
            Mock docker { $global:LASTEXITCODE = 0 }

            Test-RuntimeVolumePopulated -ContainerOS 'windows' -VolumeName 'v' | Should -BeTrue
        }

        It 'returns false when the node check exits non-zero' {
            Mock docker { $global:LASTEXITCODE = 1 }

            Test-RuntimeVolumePopulated -ContainerOS 'windows' -VolumeName 'v' | Should -BeFalse
        }

        It 'mounts the volume and checks for node.exe' {
            $script:joined = $null
            Mock docker {
                $script:joined = $args -join ' '
                $global:LASTEXITCODE = 0
            }

            Test-RuntimeVolumePopulated -ContainerOS 'windows' -VolumeName 'myvol' | Out-Null

            $script:joined | Should -BeLike '*myvol:C:\check*'
            $script:joined | Should -BeLike '*if exist C:\check\node\node.exe*'
        }
    }
}
