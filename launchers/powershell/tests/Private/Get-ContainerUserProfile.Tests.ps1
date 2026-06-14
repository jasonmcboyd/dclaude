BeforeAll {
    . "$PSScriptRoot/../../Private/Get-ContainerUserProfile.ps1"
    function docker { }
}

Describe 'Get-ContainerUserProfile' {
    It 'returns the probed profile in forward-slash form' {
        Mock docker { 'C:\Users\SomeUser'; $global:LASTEXITCODE = 0 }

        Get-ContainerUserProfile -Image 'img:latest' | Should -Be 'C:/Users/SomeUser'
    }

    It 'probes via cmd echo %USERPROFILE% against the image' {
        $script:joined = $null
        Mock docker { $script:joined = $args -join ' '; 'C:\Users\X'; $global:LASTEXITCODE = 0 }

        Get-ContainerUserProfile -Image 'img:latest' | Out-Null

        $script:joined | Should -BeLike '*--entrypoint cmd img:latest /c echo %USERPROFILE%*'
    }

    It 'falls back to ContainerAdministrator when the probe exits non-zero' {
        Mock docker { $global:LASTEXITCODE = 1 }

        Get-ContainerUserProfile -Image 'img:latest' -WarningAction SilentlyContinue |
            Should -Be 'C:/Users/ContainerAdministrator'
    }

    It 'falls back when the probe returns empty output' {
        Mock docker { ''; $global:LASTEXITCODE = 0 }

        Get-ContainerUserProfile -Image 'img:latest' -WarningAction SilentlyContinue |
            Should -Be 'C:/Users/ContainerAdministrator'
    }
}
