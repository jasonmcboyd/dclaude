BeforeAll {
    . "$PSScriptRoot/../../Private/Get-ContainerUserProfile.ps1"
    function docker { }
}

Describe 'Get-ContainerUserProfile' {

    Context 'when the image is already present' {
        It 'returns the probed profile in forward-slash form' {
            Mock docker {
                if ($args[0] -eq 'run') { 'C:\Users\SomeUser' }
                $global:LASTEXITCODE = 0
            }

            Get-ContainerUserProfile -Image 'img:latest' | Should -Be 'C:/Users/SomeUser'
        }

        It 'does not pull when the image is already local' {
            $script:calls = @()
            Mock docker {
                $script:calls += , @($args)
                if ($args[0] -eq 'run') { 'C:\Users\SomeUser' }
                $global:LASTEXITCODE = 0
            }

            Get-ContainerUserProfile -Image 'img:latest' | Out-Null

            ($script:calls | Where-Object { $_[0] -eq 'pull' }).Count | Should -Be 0
        }

        It 'probes via cmd echo %USERPROFILE% against the image' {
            $script:joined = $null
            Mock docker {
                if ($args[0] -eq 'run') { $script:joined = $args -join ' '; 'C:\Users\X' }
                $global:LASTEXITCODE = 0
            }

            Get-ContainerUserProfile -Image 'img:latest' | Out-Null

            $script:joined | Should -BeLike '*--entrypoint cmd img:latest /c echo %USERPROFILE%*'
        }
    }

    Context 'when the image is not present locally' {
        It 'pulls it (visibly) before probing' {
            $script:calls = @()
            Mock docker {
                $script:calls += , @($args)
                if ($args[0] -eq 'image' -and $args[1] -eq 'inspect') { $global:LASTEXITCODE = 1; return }
                if ($args[0] -eq 'run') { 'C:\Users\X'; $global:LASTEXITCODE = 0; return }
                $global:LASTEXITCODE = 0  # pull
            }

            Get-ContainerUserProfile -Image 'img:latest' | Should -Be 'C:/Users/X'
            ($script:calls | Where-Object { $_[0] -eq 'pull' }).Count | Should -BeGreaterThan 0
        }

        It 'falls back to ContainerAdministrator when the pull fails' {
            Mock docker {
                if ($args[0] -eq 'image' -and $args[1] -eq 'inspect') { $global:LASTEXITCODE = 1; return }
                $global:LASTEXITCODE = 1  # pull fails
            }

            Get-ContainerUserProfile -Image 'img:latest' -WarningAction SilentlyContinue |
                Should -Be 'C:/Users/ContainerAdministrator'
        }
    }

    Context 'fallbacks' {
        It 'falls back when the probe returns empty output' {
            Mock docker {
                if ($args[0] -eq 'run') { '' }
                $global:LASTEXITCODE = 0
            }

            Get-ContainerUserProfile -Image 'img:latest' -WarningAction SilentlyContinue |
                Should -Be 'C:/Users/ContainerAdministrator'
        }
    }
}
