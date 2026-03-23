BeforeAll {
    . "$PSScriptRoot/../../src/Private/Remove-StaleRuntimeVolumes.ps1"

    function docker { }
}

Describe 'Remove-StaleRuntimeVolumes' {

    Context 'when no volumes exist' {
        It 'does nothing' {
            Mock docker { return $null } -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'ls' }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            Should -Not -Invoke docker -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'rm' }
        }
    }

    Context 'when only current version volumes exist' {
        It 'skips current version volumes' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'volume ls') {
                    return @('dclaude-runtime-linux-v1.0.0', 'dclaude-runtime-windows-v1.0.0')
                }
            }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            Should -Not -Invoke docker -ParameterFilter { $args[0] -eq 'volume' -and $args[1] -eq 'rm' }
        }
    }

    Context 'when stale volumes exist with no containers' {
        It 'removes unreferenced stale volumes' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'volume ls') {
                    return @('dclaude-runtime-linux-v0.9.0', 'dclaude-runtime-linux-v1.0.0')
                }
                if ($joined -match 'ps -a') {
                    return $null
                }
                if ($joined -match 'volume rm') {
                    return $null
                }
            }
            Mock Write-Host { }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            Should -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm.*dclaude-runtime-linux-v0.9.0'
            }
        }
    }

    Context 'when stale volume is referenced by a container' {
        It 'does not remove the volume' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'volume ls') {
                    return @('dclaude-runtime-linux-v0.9.0')
                }
                if ($joined -match 'ps -a') {
                    return 'abc123'
                }
            }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            Should -Not -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm'
            }
        }
    }
}
