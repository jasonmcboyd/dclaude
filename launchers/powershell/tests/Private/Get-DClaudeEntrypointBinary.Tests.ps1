BeforeAll {
    . "$PSScriptRoot/../../Private/Get-DClaudeEntrypointBinary.ps1"

    # The function resolves the bundled binary relative to its own source location:
    #   $binDir = Join-Path (Split-Path $PSScriptRoot) 'bin'   (a sibling of Private/)
    # which lands at launchers/powershell/bin. That directory does not exist in the repo
    # (binaries are built/bundled in CI), so the bundled-fallback tests below create the
    # expected file there and clean it up afterward.
    $script:moduleRoot = Split-Path (Split-Path $PSScriptRoot)   # launchers/powershell
    $script:bundledBinDir = Join-Path $script:moduleRoot 'bin'

    $script:hostArch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        'Arm64' { 'arm64' }
        default { 'amd64' }
    }
}

Describe 'Get-DClaudeEntrypointBinary' {

    BeforeEach {
        $script:savedSrc = $env:DCLAUDE_ENTRYPOINT_SRC
        $env:DCLAUDE_ENTRYPOINT_SRC = $null
    }

    AfterEach {
        $env:DCLAUDE_ENTRYPOINT_SRC = $script:savedSrc
    }

    Context 'DCLAUDE_ENTRYPOINT_SRC override' {
        It 'returns the override path when it points at an existing file' {
            $override = Join-Path $TestDrive 'my-built-entrypoint'
            Set-Content -Path $override -Value 'x'
            $env:DCLAUDE_ENTRYPOINT_SRC = $override

            $result = Get-DClaudeEntrypointBinary -ContainerOS 'linux'

            $result | Should -Be $override
        }

        It 'wins over the bundled binary even when both exist' {
            $override = Join-Path $TestDrive 'override-entrypoint'
            Set-Content -Path $override -Value 'x'
            $env:DCLAUDE_ENTRYPOINT_SRC = $override

            # Stage a bundled binary too; the override should still take precedence.
            $bundledName = "dclaude-entrypoint-linux-$script:hostArch"
            $bundledPath = Join-Path $script:bundledBinDir $bundledName
            $createdBinDir = -not (Test-Path $script:bundledBinDir)
            New-Item -ItemType Directory -Path $script:bundledBinDir -Force | Out-Null
            Set-Content -Path $bundledPath -Value 'bundled'
            try {
                $result = Get-DClaudeEntrypointBinary -ContainerOS 'linux'
                $result | Should -Be $override
            }
            finally {
                Remove-Item $bundledPath -Force -ErrorAction SilentlyContinue
                if ($createdBinDir) { Remove-Item $script:bundledBinDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        It 'falls back to the bundled binary (with a warning) when the override is missing' {
            $env:DCLAUDE_ENTRYPOINT_SRC = Join-Path $TestDrive 'does-not-exist'

            $bundledName = "dclaude-entrypoint-linux-$script:hostArch"
            $bundledPath = Join-Path $script:bundledBinDir $bundledName
            $createdBinDir = -not (Test-Path $script:bundledBinDir)
            New-Item -ItemType Directory -Path $script:bundledBinDir -Force | Out-Null
            Set-Content -Path $bundledPath -Value 'bundled'
            try {
                $result = Get-DClaudeEntrypointBinary -ContainerOS 'linux' -WarningAction SilentlyContinue
                $result | Should -Be $bundledPath
            }
            finally {
                Remove-Item $bundledPath -Force -ErrorAction SilentlyContinue
                if ($createdBinDir) { Remove-Item $script:bundledBinDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    Context 'bundled binary resolution' {
        It 'resolves the Linux binary name (no .exe extension)' {
            $bundledName = "dclaude-entrypoint-linux-$script:hostArch"
            $bundledPath = Join-Path $script:bundledBinDir $bundledName
            $createdBinDir = -not (Test-Path $script:bundledBinDir)
            New-Item -ItemType Directory -Path $script:bundledBinDir -Force | Out-Null
            Set-Content -Path $bundledPath -Value 'bundled'
            try {
                $result = Get-DClaudeEntrypointBinary -ContainerOS 'linux'
                $result | Should -Be $bundledPath
            }
            finally {
                Remove-Item $bundledPath -Force -ErrorAction SilentlyContinue
                if ($createdBinDir) { Remove-Item $script:bundledBinDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        It 'resolves the Windows binary name (with .bin.gz extension)' {
            $bundledName = "dclaude-entrypoint-windows-$script:hostArch.bin.gz"
            $bundledPath = Join-Path $script:bundledBinDir $bundledName
            $createdBinDir = -not (Test-Path $script:bundledBinDir)
            New-Item -ItemType Directory -Path $script:bundledBinDir -Force | Out-Null
            Set-Content -Path $bundledPath -Value 'bundled'
            try {
                $result = Get-DClaudeEntrypointBinary -ContainerOS 'windows'
                $result | Should -Be $bundledPath
            }
            finally {
                Remove-Item $bundledPath -Force -ErrorAction SilentlyContinue
                if ($createdBinDir) { Remove-Item $script:bundledBinDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    Context 'when no binary can be found' {
        It 'writes an error and returns null when neither override nor bundled binary exists' {
            # Guard: only meaningful if there is no real bundled binary on disk for this OS/arch.
            $bundledName = "dclaude-entrypoint-linux-$script:hostArch"
            $bundledPath = Join-Path $script:bundledBinDir $bundledName
            if (Test-Path $bundledPath) {
                Set-ItResult -Skipped -Because 'a real bundled binary is present on disk'
                return
            }

            $result = Get-DClaudeEntrypointBinary -ContainerOS 'linux' -ErrorVariable err -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
            $err[0].ToString() | Should -BeLike '*Bundled entrypoint binary not found*'
        }
    }
}
