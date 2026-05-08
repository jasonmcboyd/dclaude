BeforeAll {
    . "$PSScriptRoot/../../src/Private/Write-LaunchSummary.ps1"
}

Describe 'Write-LaunchSummary' {

    BeforeEach {
        Mock Write-Host { }
    }

    Context 'image display' {
        It 'displays image name and tag when ImageName is provided' {
            Write-LaunchSummary -ImageTag 'dclaude-pwsh:latest' -ImageName 'pwsh' -DockerArgs @('run')

            Should -Invoke Write-Host -ParameterFilter { $Object -eq '[dclaude] Image: pwsh (dclaude-pwsh:latest)' }
        }

        It 'displays only image tag when ImageName is not provided' {
            Write-LaunchSummary -ImageTag 'my-image:v1' -DockerArgs @('run')

            Should -Invoke Write-Host -ParameterFilter { $Object -eq '[dclaude] Image: my-image:v1' }
        }
    }

    Context 'volume display' {
        It 'lists all volume mounts from docker args' {
            $args = @('run', '-v', '/host:/container:ro', '-v', '/other:/mount:rw', 'image:latest')

            Write-LaunchSummary -ImageTag 'image:latest' -DockerArgs $args

            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  /host:/container:ro' }
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  /other:/mount:rw' }
        }
    }

    Context 'environment variable display' {
        It 'lists all environment variables from docker args' {
            $args = @('run', '-e', 'FOO=bar', '-e', 'BAZ', 'image:latest')

            Write-LaunchSummary -ImageTag 'image:latest' -DockerArgs $args

            Should -Invoke Write-Host -ParameterFilter { $Object -eq '[dclaude] Environment variables:' }
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  FOO=bar' }
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  BAZ' }
        }

        It 'does not display environment section when no -e flags exist' {
            $args = @('run', '-v', '/host:/container:ro', 'image:latest')

            Write-LaunchSummary -ImageTag 'image:latest' -DockerArgs $args

            Should -Not -Invoke Write-Host -ParameterFilter { $Object -eq '[dclaude] Environment variables:' }
        }
    }
}
