BeforeAll {
    . "$PSScriptRoot/../../src/Private/Get-DockerContainerOS.ps1"
    function docker { }
}

Describe 'Get-DockerContainerOS' {

    AfterEach { $global:LASTEXITCODE = 0 }

    Context 'when Docker command is not found' {
        It 'writes an error' {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'docker' }

            Get-DockerContainerOS -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Docker is not installed*'
        }
    }

    Context 'when Docker daemon is not running' {
        It 'writes an error' {
            Mock Get-Command { return @{ Name = 'docker' } } -ParameterFilter { $Name -eq 'docker' }
            Mock docker { $global:LASTEXITCODE = 1; 'error during connect' }

            Get-DockerContainerOS -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Docker is not running*'
        }
    }

    Context 'when Docker returns Windows OS type' {
        It 'returns windows' {
            Mock Get-Command { return @{ Name = 'docker' } } -ParameterFilter { $Name -eq 'docker' }
            Mock docker { $global:LASTEXITCODE = 0; 'windows' }

            $result = Get-DockerContainerOS

            $result | Should -Be 'windows'
        }
    }

    Context 'when Docker returns Linux OS type' {
        It 'returns linux' {
            Mock Get-Command { return @{ Name = 'docker' } } -ParameterFilter { $Name -eq 'docker' }
            Mock docker { $global:LASTEXITCODE = 0; 'linux' }

            $result = Get-DockerContainerOS

            $result | Should -Be 'linux'
        }
    }

    Context 'when OS type cannot be determined' {
        It 'writes an error' {
            Mock Get-Command { return @{ Name = 'docker' } } -ParameterFilter { $Name -eq 'docker' }
            Mock docker { $global:LASTEXITCODE = 0; '' }

            Get-DockerContainerOS -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Unable to determine*'
        }
    }
}
