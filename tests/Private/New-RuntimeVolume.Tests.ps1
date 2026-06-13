BeforeAll {
    . "$PSScriptRoot/../../src/Private/DClaudeConstants.ps1"
    . "$PSScriptRoot/../../src/Private/New-RuntimeVolume.ps1"

    function docker { }
}

Describe 'New-RuntimeVolume' {

    BeforeEach {
        $script:dockerCalls = @()
        Mock docker {
            $script:dockerCalls += , @($args)
            $global:LASTEXITCODE = 0
        }
        Mock Write-Host { }
        Mock Out-Host { }
    }

    Context 'volume name' {
        It 'passes the exact volume name to docker run -v (Linux)' {
            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'dclaude-runtime-linux-v1.0.0-r3' | Out-Null

            $joined = $script:dockerCalls[0] -join ' '
            $joined | Should -BeLike '*run*'
            $joined | Should -BeLike '*dclaude-runtime-linux-v1.0.0-r3:/out*'
        }

        It 'passes the exact volume name to docker run -v (Windows)' {
            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'dclaude-runtime-windows-v1.0.0-r3' | Out-Null

            $joined = $script:dockerCalls[0] -join ' '
            $joined | Should -BeLike '*dclaude-runtime-windows-v1.0.0-r3:C:\out*'
        }
    }

    Context 'Claude Code version selection' {
        It 'installs the pinned version when -ClaudeCodeVersion is supplied (Linux)' {
            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null

            $joined = $script:dockerCalls[0] -join ' '
            $joined | Should -BeLike '*@anthropic-ai/claude-code@1.2.3*'
        }

        It 'installs latest (no @version) when -ClaudeCodeVersion is omitted (Linux)' {
            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' | Out-Null

            $joined = $script:dockerCalls[0] -join ' '
            $joined | Should -BeLike '*@anthropic-ai/claude-code *'
            $joined | Should -Not -BeLike '*@anthropic-ai/claude-code@*'
        }

        It 'installs the pinned version when -ClaudeCodeVersion is supplied (Windows)' {
            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'v' -ClaudeCodeVersion '1.2.3' | Out-Null

            $joined = $script:dockerCalls[0] -join ' '
            $joined | Should -BeLike '*@anthropic-ai/claude-code@1.2.3*'
        }

        It 'installs latest when -ClaudeCodeVersion is omitted (Windows)' {
            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'v' | Out-Null

            $joined = $script:dockerCalls[0] -join ' '
            $joined | Should -Not -BeLike '*@anthropic-ai/claude-code@*'
        }
    }

    Context 'return value' {
        It 'returns true when provisioning exits 0 (Linux)' {
            Mock docker { $global:LASTEXITCODE = 0 }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' | Should -BeTrue
        }

        It 'returns false when provisioning exits non-zero (Linux)' {
            Mock docker { $global:LASTEXITCODE = 1 }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' | Should -BeFalse
        }
    }

    Context 'Windows VHD-cleanup verification path' {
        It 'returns true when provisioning exits non-zero but the volume verifies populated' {
            # First docker call (provision) returns non-zero; the verification call
            # (mounting :C:\check) returns 0 because the node binary is present.
            Mock docker {
                $joined = $args -join ' '
                if ($joined -match ':C:\\check') {
                    $global:LASTEXITCODE = 0
                }
                else {
                    $global:LASTEXITCODE = 1
                }
            }

            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'v' | Should -BeTrue
        }

        It 'returns false when provisioning fails and the volume does not verify populated' {
            Mock docker { $global:LASTEXITCODE = 1 }

            New-RuntimeVolume -ContainerOS 'windows' -VolumeName 'v' | Should -BeFalse
        }

        It 'does not run the verification check on Linux failures' {
            $script:checkSeen = $false
            Mock docker {
                if (($args -join ' ') -match ':/check') { $script:checkSeen = $true }
                $global:LASTEXITCODE = 1
            }

            New-RuntimeVolume -ContainerOS 'linux' -VolumeName 'v' | Should -BeFalse
            $script:checkSeen | Should -BeFalse
        }
    }
}
