BeforeAll {
    . "$PSScriptRoot/../../Private/Remove-StaleNetworks.ps1"

    function docker { }
}

Describe 'Remove-StaleNetworks' {

    Context 'when no dclaude networks exist' {
        It 'does nothing' {
            Mock docker { return $null } -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'ls' }

            Remove-StaleNetworks

            Should -Not -Invoke docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'rm' }
        }
    }

    Context 'when all networks have containers attached' {
        It 'skips networks with containers' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'network ls') {
                    return @('dclaude-net-myproject-1234')
                }
                if ($joined -match 'network inspect') {
                    return 'dclaude-myproject-1234 sql-mcp-myproject-1234 '
                }
            }

            Remove-StaleNetworks

            Should -Not -Invoke docker -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'rm' }
        }
    }

    Context 'when orphaned networks exist' {
        It 'removes networks with no containers' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'network ls') {
                    return @('dclaude-net-proj-111', 'dclaude-net-proj-222')
                }
                if ($joined -match 'network inspect') {
                    return ''
                }
                if ($joined -match 'network rm') {
                    return $null
                }
            }
            Mock Write-Host { }

            Remove-StaleNetworks

            Should -Invoke docker -Times 2 -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'rm' }
        }
    }

    Context 'when mix of orphaned and active networks exist' {
        It 'removes only orphaned networks' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'network ls') {
                    return @('dclaude-net-active-100', 'dclaude-net-orphan-200')
                }
                if ($joined -match 'network inspect.*active') {
                    return 'some-container '
                }
                if ($joined -match 'network inspect.*orphan') {
                    return ''
                }
                if ($joined -match 'network rm') {
                    return $null
                }
            }
            Mock Write-Host { }

            Remove-StaleNetworks

            Should -Invoke docker -Times 1 -ParameterFilter { $args[0] -eq 'network' -and $args[1] -eq 'rm' }
            Should -Invoke docker -Times 1 -ParameterFilter {
                $args[0] -eq 'network' -and $args[1] -eq 'rm' -and $args[2] -eq 'dclaude-net-orphan-200'
            }
        }
    }

    Context 'when network removal fails' {
        It 'does not throw' {
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match 'network ls') {
                    return @('dclaude-net-stuck-999')
                }
                if ($joined -match 'network inspect') {
                    return ''
                }
            }
            Mock Write-Host { }

            { Remove-StaleNetworks } | Should -Not -Throw

            Should -Invoke docker -ParameterFilter {
                $args[0] -eq 'network' -and $args[1] -eq 'rm' -and $args[2] -eq 'dclaude-net-stuck-999'
            }
        }
    }
}
