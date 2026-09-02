BeforeAll {
    . "$PSScriptRoot/../../Private/Stop-SqlMcpSidecar.ps1"

    function docker { }
}

Describe 'Stop-SqlMcpSidecar' {

    BeforeEach {
        Mock docker { }
        Mock Write-Host { }
    }

    It 'stops the sidecar and removes the network' {
        Stop-SqlMcpSidecar -SidecarName 'sql-mcp-test-1234' -NetworkName 'dclaude-net-test-1234'

        Should -Invoke docker -ParameterFilter {
            $args[0] -eq 'stop' -and $args[1] -eq 'sql-mcp-test-1234'
        }
        Should -Invoke docker -ParameterFilter {
            $args[0] -eq 'network' -and $args[1] -eq 'rm' -and $args[2] -eq 'dclaude-net-test-1234'
        }
    }

    It 'is idempotent when sidecar already stopped' {
        # docker stop fails (already stopped) — should not throw
        Mock docker { $global:LASTEXITCODE = 1 } -ParameterFilter {
            $args[0] -eq 'stop'
        }

        { Stop-SqlMcpSidecar -SidecarName 'gone' -NetworkName 'dclaude-net-gone' } | Should -Not -Throw
    }

    It 'is idempotent when network already removed' {
        Mock docker { $global:LASTEXITCODE = 1 } -ParameterFilter {
            $args[0] -eq 'network' -and $args[1] -eq 'rm'
        }

        { Stop-SqlMcpSidecar -SidecarName 'x' -NetworkName 'dclaude-net-x' } | Should -Not -Throw
    }
}
