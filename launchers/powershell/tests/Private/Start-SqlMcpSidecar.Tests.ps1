BeforeAll {
    . "$PSScriptRoot/../../Private/Start-SqlMcpSidecar.ps1"

    function docker { }

    function NewSecureString([string]$plain) {
        return ($plain | ConvertTo-SecureString -AsPlainText -Force)
    }
}

Describe 'Start-SqlMcpSidecar' {

    BeforeEach {
        Mock docker { return $null }
        Mock Write-Host { }
        Mock Start-Sleep { }
        Mock Test-Path { return $true }
    }

    Context 'when image exists and sidecar starts healthy' {
        It 'skips build, creates network, starts sidecar, and returns info' {
            # Image exists
            Mock docker { return '{}' } -ParameterFilter {
                $args[0] -eq 'image' -and $args[1] -eq 'inspect'
            }
            # Network create succeeds
            Mock docker { $global:LASTEXITCODE = 0 } -ParameterFilter {
                $args[0] -eq 'network' -and $args[1] -eq 'create'
            }
            # Container start succeeds
            Mock docker { $global:LASTEXITCODE = 0 } -ParameterFilter {
                $args[0] -eq 'run'
            }
            # Health check returns healthy
            Mock docker { return 'healthy' } -ParameterFilter {
                $args[0] -eq 'inspect'
            }

            $conns = @((NewSecureString 'Server=localhost;Database=AppData'))
            $result = Start-SqlMcpSidecar -SqlConnections $conns -NetworkName 'dclaude-net-test-1234' -ModuleVersion ([version]'1.0.0')

            $result | Should -Not -BeNullOrEmpty
            $result.NetworkName | Should -Be 'dclaude-net-test-1234'
            $result.SidecarName | Should -Be 'sql-mcp-test-1234'
            $result.McpUrl | Should -Be 'http://sql-mcp:3100/mcp'

            # Should not have called docker build
            Should -Not -Invoke docker -ParameterFilter {
                $args[0] -eq 'build'
            }
        }
    }

    Context 'when image does not exist' {
        It 'builds the image before starting sidecar' {
            # Image does not exist
            Mock docker { $global:LASTEXITCODE = 1; return $null } -ParameterFilter {
                $args[0] -eq 'image' -and $args[1] -eq 'inspect'
            }
            # Build succeeds
            Mock docker { $global:LASTEXITCODE = 0 } -ParameterFilter {
                $args[0] -eq 'build'
            }
            # Network create succeeds
            Mock docker { $global:LASTEXITCODE = 0 } -ParameterFilter {
                $args[0] -eq 'network' -and $args[1] -eq 'create'
            }
            # Container start succeeds
            Mock docker { $global:LASTEXITCODE = 0 } -ParameterFilter {
                $args[0] -eq 'run'
            }
            # Health check returns healthy
            Mock docker { return 'healthy' } -ParameterFilter {
                $args[0] -eq 'inspect'
            }

            $conns = @((NewSecureString 'Server=test'))
            $result = Start-SqlMcpSidecar -SqlConnections $conns -NetworkName 'dclaude-net-proj-42' -ModuleVersion ([version]'2.0.0')

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke docker -ParameterFilter {
                $args[0] -eq 'build'
            }
        }
    }

    Context 'when health check times out' {
        It 'stops sidecar, removes network, and returns null' {
            Mock docker { return '{}' } -ParameterFilter {
                $args[0] -eq 'image' -and $args[1] -eq 'inspect'
            }
            Mock docker { $global:LASTEXITCODE = 0 } -ParameterFilter {
                $args[0] -eq 'network' -and $args[1] -eq 'create'
            }
            Mock docker { $global:LASTEXITCODE = 0 } -ParameterFilter {
                $args[0] -eq 'run'
            }
            # Health never becomes healthy
            Mock docker { return 'starting' } -ParameterFilter {
                $args[0] -eq 'inspect'
            }

            $conns = @((NewSecureString 'Server=x'))
            $result = Start-SqlMcpSidecar -SqlConnections $conns -NetworkName 'dclaude-net-t-1' -ModuleVersion ([version]'1.0.0') -ErrorVariable err -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*healthy*'

            # Cleanup should be called
            Should -Invoke docker -ParameterFilter {
                $args[0] -eq 'stop'
            }
            Should -Invoke docker -ParameterFilter {
                $args[0] -eq 'network' -and $args[1] -eq 'rm'
            }
        }
    }

    Context 'when multiple connections are provided' {
        It 'passes all connection strings as numbered env vars' {
            Mock docker { return '{}' } -ParameterFilter {
                $args[0] -eq 'image' -and $args[1] -eq 'inspect'
            }
            Mock docker { $global:LASTEXITCODE = 0 } -ParameterFilter {
                $args[0] -eq 'network' -and $args[1] -eq 'create'
            }
            $script:capturedRunArgs = $null
            Mock docker {
                $script:capturedRunArgs = $args
                $global:LASTEXITCODE = 0
            } -ParameterFilter {
                $args[0] -eq 'run'
            }
            Mock docker { return 'healthy' } -ParameterFilter {
                $args[0] -eq 'inspect'
            }

            $conns = @(
                (NewSecureString 'Server=srv1;Database=AppData')
                (NewSecureString 'Server=srv2;Database=InvestorData')
            )
            $result = Start-SqlMcpSidecar -SqlConnections $conns -NetworkName 'dclaude-net-m-1' -ModuleVersion ([version]'1.0.0')

            $result | Should -Not -BeNullOrEmpty
            $runArgs = $script:capturedRunArgs -join ' '
            $runArgs | Should -Match 'SQL_CONN_1='
            $runArgs | Should -Match 'SQL_CONN_2='
        }
    }

    Context 'when network creation fails' {
        It 'returns null with error' {
            Mock docker { return '{}' } -ParameterFilter {
                $args[0] -eq 'image' -and $args[1] -eq 'inspect'
            }
            Mock docker { $global:LASTEXITCODE = 1 } -ParameterFilter {
                $args[0] -eq 'network' -and $args[1] -eq 'create'
            }

            $conns = @((NewSecureString 'Server=x'))
            $result = Start-SqlMcpSidecar -SqlConnections $conns -NetworkName 'dclaude-net-f-1' -ModuleVersion ([version]'1.0.0') -ErrorVariable err -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*network*'
        }
    }
}
