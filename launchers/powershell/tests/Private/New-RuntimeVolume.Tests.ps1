BeforeAll {
    . "$PSScriptRoot/../../Private/DClaudeConstants.ps1"
    . "$PSScriptRoot/../../Private/Test-GoEntrypointEnabled.ps1"
    . "$PSScriptRoot/../../Private/New-RuntimeVolume.ps1"

    function docker { }
    # Get-LatestClaudeCodeVersion is called by New-RuntimeVolume when -ClaudeCodeVersion is
    # omitted; stub it so it can be mocked even though it isn't dot-sourced here.
    function Get-LatestClaudeCodeVersion { }
    # Get-DClaudeModuleVersion is only called on the Go-entrypoint download path; stub it.
    function Get-DClaudeModuleVersion { }

    # Returns the joined string of the 'docker run' call (skips the 'docker volume create' call).
    function Get-RunCall {
        foreach ($call in $script:dockerCalls) {
            if ($call[0] -eq 'run') { return ($call -join ' ') }
        }
        return $null
    }

    # Returns the joined string of the 'docker volume create' call, or $null if none was made.
    function Get-CreateCall {
        foreach ($call in $script:dockerCalls) {
            if ($call[0] -eq 'volume' -and $call[1] -eq 'create') { return ($call -join ' ') }
        }
        return $null
    }
}

Describe 'New-RuntimeVolume' {

    BeforeEach {
        # Keep the default path deterministic: Go entrypoint disabled unless a test opts in.
        $env:DCLAUDE_USE_GO_ENTRYPOINT = $null
        $env:DCLAUDE_ENTRYPOINT_SRC = $null
        $script:dockerCalls = @()
        Mock docker {
            $script:dockerCalls += , @($args)
            # The pre-existing-volume guard probes `docker volume inspect`; report not-found
            # (exit 1) so provisioning proceeds. Everything else succeeds (exit 0).
            if ($args[0] -eq 'volume' -and $args[1] -eq 'inspect') { $global:LASTEXITCODE = 1 }
            else { $global:LASTEXITCODE = 0 }
        }
        Mock Write-Host { }
        Mock Out-Host { }
        # Default: latest resolves to a concrete version so a labeled volume is created.
        Mock Get-LatestClaudeCodeVersion { return '7.7.7' }
    }

    Context 'volume name' {
        It 'passes the exact volume name to docker run -v (Linux)' {
            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'dclaude-runtime-linux-v1.0.0-r3' | Out-Null

            $run = Get-RunCall
            $run | Should -BeLike '*run*'
            $run | Should -BeLike '*dclaude-runtime-linux-v1.0.0-r3:/out*'
        }

        It 'passes the exact volume name to docker run -v (Windows)' {
            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'dclaude-runtime-windows-v1.0.0-r3' | Out-Null

            $run = Get-RunCall
            $run | Should -BeLike '*dclaude-runtime-windows-v1.0.0-r3:C:\out*'
        }
    }

    Context 'version label and install pinning' {
        It 'pre-creates the volume with the dclaude.cc-version label matching the resolved version (Linux)' {
            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null

            $create = Get-CreateCall
            $create | Should -BeLike '*volume create*'
            $create | Should -BeLike '*--label dclaude.cc-version=1.2.3*'
            $create | Should -BeLike '*v*'
        }

        It 'pins the install to the SAME version recorded in the label (Linux)' {
            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null

            (Get-CreateCall) | Should -BeLike '*--label dclaude.cc-version=1.2.3*'
            (Get-RunCall) | Should -BeLike '*@anthropic-ai/claude-code@1.2.3*'
        }

        It 'pins the install to the SAME version recorded in the label (Windows)' {
            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null

            (Get-CreateCall) | Should -BeLike '*--label dclaude.cc-version=1.2.3*'
            (Get-RunCall) | Should -BeLike '*@anthropic-ai/claude-code@1.2.3*'
        }

        It 'resolves latest via Get-LatestClaudeCodeVersion when -ClaudeCodeVersion is omitted (Linux)' {
            Mock Get-LatestClaudeCodeVersion { return '7.7.7' }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' | Out-Null

            Should -Invoke Get-LatestClaudeCodeVersion -Times 1
            (Get-CreateCall) | Should -BeLike '*--label dclaude.cc-version=7.7.7*'
            (Get-RunCall) | Should -BeLike '*@anthropic-ai/claude-code@7.7.7*'
        }

        It 'does not call Get-LatestClaudeCodeVersion when -ClaudeCodeVersion is supplied' {
            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null

            Should -Not -Invoke Get-LatestClaudeCodeVersion
        }
    }

    Context 'when latest cannot be resolved and no version is supplied' {
        It 'installs plain latest with NO label and creates no labeled volume (Linux)' {
            Mock Get-LatestClaudeCodeVersion { return $null }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' | Out-Null

            # No version label volume should be created.
            Get-CreateCall | Should -BeNullOrEmpty
            # Plain latest install (no @version pin).
            $run = Get-RunCall
            $run | Should -BeLike '*@anthropic-ai/claude-code *'
            $run | Should -Not -BeLike '*@anthropic-ai/claude-code@*'
        }

        It 'installs plain latest with NO label (Windows)' {
            Mock Get-LatestClaudeCodeVersion { return $null }

            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'v' | Out-Null

            Get-CreateCall | Should -BeNullOrEmpty
            (Get-RunCall) | Should -Not -BeLike '*@anthropic-ai/claude-code@*'
        }
    }

    Context 'when the target volume already exists' {
        It 'refuses to provision over it and returns false' {
            # Guard probe finds the volume (exit 0) — provisioning must not proceed.
            Mock docker {
                $script:dockerCalls += , @($args)
                $global:LASTEXITCODE = 0
            }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' -ErrorAction SilentlyContinue |
                Should -BeFalse
            Get-CreateCall | Should -BeNullOrEmpty
            Get-RunCall | Should -BeNullOrEmpty
        }
    }

    Context 'when the labeled volume cannot be created' {
        It 'returns false and does not run the provisioning container' {
            Mock docker {
                $script:dockerCalls += , @($args)
                # Guard probe: report not-found. Fail only the 'volume create' step.
                if ($args[0] -eq 'volume' -and $args[1] -eq 'inspect') {
                    $global:LASTEXITCODE = 1
                } elseif ($args[0] -eq 'volume' -and $args[1] -eq 'create') {
                    $global:LASTEXITCODE = 1
                } else {
                    $global:LASTEXITCODE = 0
                }
            }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' -ErrorAction SilentlyContinue |
                Should -BeFalse
            Get-RunCall | Should -BeNullOrEmpty
        }
    }

    Context 'return value' {
        It 'returns true when provisioning exits 0 (Linux)' {
            # Guard probe reports not-found (exit 1); all real steps succeed (exit 0).
            Mock docker {
                if ($args[0] -eq 'volume' -and $args[1] -eq 'inspect') { $global:LASTEXITCODE = 1 }
                else { $global:LASTEXITCODE = 0 }
            }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Should -BeTrue
        }

        It 'returns false when provisioning exits non-zero (Linux)' {
            # Guard probe not-found; volume create succeeds (exit 0); provisioning run fails (exit 1).
            Mock docker {
                if ($args[0] -eq 'volume' -and $args[1] -eq 'inspect') {
                    $global:LASTEXITCODE = 1
                } elseif ($args[0] -eq 'volume' -and $args[1] -eq 'create') {
                    $global:LASTEXITCODE = 0
                } else {
                    $global:LASTEXITCODE = 1
                }
            }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Should -BeFalse
        }
    }

    Context 'Windows VHD-cleanup verification path' {
        It 'returns true when provisioning exits non-zero but the volume verifies populated' {
            # volume create succeeds; the provision run returns non-zero; the verification call
            # (mounting :C:\check) returns 0 because the node binary is present.
            Mock docker {
                $joined = $args -join ' '
                if ($args[0] -eq 'volume' -and $args[1] -eq 'inspect') {
                    $global:LASTEXITCODE = 1
                }
                elseif ($args[0] -eq 'volume' -and $args[1] -eq 'create') {
                    $global:LASTEXITCODE = 0
                }
                elseif ($joined -match ':C:\\check') {
                    $global:LASTEXITCODE = 0
                }
                else {
                    $global:LASTEXITCODE = 1
                }
            }

            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Should -BeTrue
        }

        It 'returns false when provisioning fails and the volume does not verify populated' {
            Mock docker {
                if ($args[0] -eq 'volume' -and $args[1] -eq 'inspect') {
                    $global:LASTEXITCODE = 1
                } elseif ($args[0] -eq 'volume' -and $args[1] -eq 'create') {
                    $global:LASTEXITCODE = 0
                } else {
                    $global:LASTEXITCODE = 1
                }
            }

            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Should -BeFalse
        }

        It 'does not run the verification check on Linux failures' {
            $script:checkSeen = $false
            Mock docker {
                if (($args -join ' ') -match ':/check') { $script:checkSeen = $true }
                if ($args[0] -eq 'volume' -and $args[1] -eq 'inspect') {
                    $global:LASTEXITCODE = 1
                } elseif ($args[0] -eq 'volume' -and $args[1] -eq 'create') {
                    $global:LASTEXITCODE = 0
                } else {
                    $global:LASTEXITCODE = 1
                }
            }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Should -BeFalse
            $script:checkSeen | Should -BeFalse
        }
    }

    Context 'Go entrypoint provisioning (DCLAUDE_USE_GO_ENTRYPOINT)' {
        It 'does not touch the entrypoint binary when disabled (default)' {
            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null
            (Get-RunCall) | Should -Not -BeLike '*dclaude-entrypoint*'
        }

        It 'downloads the release binary for the module version when enabled (Linux)' {
            Mock Test-GoEntrypointEnabled { $true }
            Mock Get-DClaudeModuleVersion { [version]'0.17.0' }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null

            $run = Get-RunCall
            $run | Should -BeLike '*releases/download/v0.17.0/dclaude-entrypoint-linux-*'
            $run | Should -BeLike '*-o /out/bin/dclaude-entrypoint*'
            $run | Should -BeLike '*chmod +x /out/bin/dclaude-entrypoint*'
        }

        It 'downloads the windows release binary before applying icacls (Windows)' {
            Mock Test-GoEntrypointEnabled { $true }
            Mock Get-DClaudeModuleVersion { [version]'0.17.0' }

            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null

            $run = Get-RunCall
            $run | Should -BeLike '*releases/download/v0.17.0/dclaude-entrypoint-windows-amd64.exe*'
            # The download must precede the icacls grant so the bin dir inherits it.
            $dl = $run.IndexOf('dclaude-entrypoint.exe')
            $icacls = $run.IndexOf('icacls')
            $dl | Should -BeLessThan $icacls
        }

        It 'injects a locally built binary via docker cp instead of downloading (Linux)' {
            Mock Test-GoEntrypointEnabled { $true }
            $env:DCLAUDE_ENTRYPOINT_SRC = 'C:\build\dclaude-entrypoint'

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null

            $run = Get-RunCall
            $run | Should -BeLike '*C:\build\dclaude-entrypoint:/in/dclaude-entrypoint:ro*'
            $run | Should -BeLike '*cp /in/dclaude-entrypoint /out/bin/dclaude-entrypoint*'
            $run | Should -Not -BeLike '*releases/download*'
        }

        It 'does not resolve the module version on the local-source path' {
            Mock Test-GoEntrypointEnabled { $true }
            Mock Get-DClaudeModuleVersion { throw 'should not be called' }
            $env:DCLAUDE_ENTRYPOINT_SRC = 'C:\build\dclaude-entrypoint'

            { New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' } | Should -Not -Throw
            Should -Not -Invoke Get-DClaudeModuleVersion
        }
    }
}
