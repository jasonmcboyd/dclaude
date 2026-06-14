BeforeAll {
    . "$PSScriptRoot/../../Private/Remove-StaleRuntimeVolumes.ps1"

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

    Context 'when multiple revisions of the current version exist' {
        It 'keeps the highest revision and removes lower unreferenced revisions' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'volume ls') {
                    return @(
                        'dclaude-runtime-linux-v1.0.0-r1',
                        'dclaude-runtime-linux-v1.0.0-r2',
                        'dclaude-runtime-linux-v1.0.0-r3'
                    )
                }
                if ($joined -match 'ps -a') { return $null }
                if ($joined -match 'volume rm') { return $null }
            }
            Mock Write-Host { }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            # r3 is the highest -> kept
            Should -Not -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm.*dclaude-runtime-linux-v1.0.0-r3'
            }
            # r1 and r2 are superseded and unreferenced -> removed
            Should -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm.*dclaude-runtime-linux-v1.0.0-r1'
            }
            Should -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm.*dclaude-runtime-linux-v1.0.0-r2'
            }
        }

        It 'treats a legacy suffixless volume as revision 0 (a removable lower revision)' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'volume ls') {
                    return @(
                        'dclaude-runtime-linux-v1.0.0',       # revision 0 (legacy)
                        'dclaude-runtime-linux-v1.0.0-r1'
                    )
                }
                if ($joined -match 'ps -a') { return $null }
                if ($joined -match 'volume rm') { return $null }
            }
            Mock Write-Host { }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            # r1 is highest -> kept; legacy (revision 0) is lower -> removed
            Should -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm.*dclaude-runtime-linux-v1.0.0$'
            }
            Should -Not -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm.*dclaude-runtime-linux-v1.0.0-r1'
            }
        }

        It 'does not remove a lower revision that a container references' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'volume ls') {
                    return @(
                        'dclaude-runtime-linux-v1.0.0-r1',
                        'dclaude-runtime-linux-v1.0.0-r2'
                    )
                }
                # r1 is in use, r2 has no container
                if ($joined -match 'ps -a') {
                    if ($joined -match 'dclaude-runtime-linux-v1.0.0-r1') { return 'abc123' }
                    return $null
                }
                if ($joined -match 'volume rm') { return $null }
            }
            Mock Write-Host { }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            Should -Not -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm.*dclaude-runtime-linux-v1.0.0-r1'
            }
        }

        It 'never removes the highest current revision even when unreferenced' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'volume ls') {
                    return @('dclaude-runtime-linux-v1.0.0-r2')
                }
                if ($joined -match 'ps -a') { return $null }
                if ($joined -match 'volume rm') { return $null }
            }
            Mock Write-Host { }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            Should -Not -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm'
            }
        }
    }

    Context 'when a newer module version volume exists (rollback scenario)' {
        It 'leaves newer-version volumes alone' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'volume ls') {
                    return @(
                        'dclaude-runtime-linux-v1.0.0-r1',
                        'dclaude-runtime-linux-v2.0.0-r1'
                    )
                }
                if ($joined -match 'ps -a') { return $null }
                if ($joined -match 'volume rm') { return $null }
            }
            Mock Write-Host { }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            Should -Not -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm.*dclaude-runtime-linux-v2.0.0-r1'
            }
        }
    }

    Context 'when removing a stale Windows runtime volume' {
        It 'runs the ACL-cleanup container before docker volume rm' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'volume ls') {
                    return @('dclaude-runtime-windows-v0.9.0')
                }
                if ($joined -match 'ps -a') { return $null }
                if ($joined -match 'volume rm') { return $null }
            }
            Mock Write-Host { }

            Remove-StaleRuntimeVolumes -CurrentVersion ([version]'1.0.0')

            # The takeown/icacls cleanup container is invoked for windows volumes
            Should -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'takeown'
            }
            Should -Invoke docker -ParameterFilter {
                ($args -join ' ') -match 'volume rm.*dclaude-runtime-windows-v0.9.0'
            }
        }
    }
}
