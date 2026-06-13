BeforeAll {
    . "$PSScriptRoot/../../src/Private/Get-LatestClaudeCodeVersion.ps1"

    # Helper to seed a cache file with a given version and age. Defined in BeforeAll so it is
    # in scope inside It blocks; reads the script-scoped paths set per-test in BeforeEach.
    function Set-Cache {
        param([string]$Version, [datetime]$CheckedAtUtc)
        New-Item -ItemType Directory -Path $script:configDir -Force | Out-Null
        [PSCustomObject]@{
            version      = $Version
            checkedAtUtc = $CheckedAtUtc.ToString('o')
        } | ConvertTo-Json | Set-Content -Path $script:cacheFile -Encoding UTF8
    }
}

Describe 'Get-LatestClaudeCodeVersion' {

    BeforeEach {
        # Isolate the cache location: the function resolves it as $HOME/.dclaude/.cc-latest-cache.json,
        # so point $HOME at a throwaway TestDrive subdir to avoid touching the real user config.
        $script:realHome = $HOME
        $script:fakeHome = Join-Path $TestDrive "home-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:fakeHome -Force | Out-Null
        Set-Variable -Name HOME -Value $script:fakeHome -Scope Global -Force

        $script:configDir = Join-Path $script:fakeHome '.dclaude'
        $script:cacheFile = Join-Path $script:configDir '.cc-latest-cache.json'

        # Default: registry returns a version.
        Mock Invoke-RestMethod { return [PSCustomObject]@{ version = '9.9.9' } }
    }

    AfterEach {
        Set-Variable -Name HOME -Value $script:realHome -Scope Global -Force
    }

    Context 'cache hit within TTL' {
        It 'returns the cached version without querying the registry' {
            Set-Cache -Version '1.0.0' -CheckedAtUtc ([datetime]::UtcNow.AddHours(-1))

            $result = Get-LatestClaudeCodeVersion

            $result | Should -Be '1.0.0'
            Should -Not -Invoke Invoke-RestMethod
        }

        It 'honors a custom -MaxAgeHours window' {
            # 3h old cache with a 2h window is expired -> must query the registry.
            Set-Cache -Version '1.0.0' -CheckedAtUtc ([datetime]::UtcNow.AddHours(-3))

            $result = Get-LatestClaudeCodeVersion -MaxAgeHours 2

            $result | Should -Be '9.9.9'
            Should -Invoke Invoke-RestMethod -Times 1
        }
    }

    Context 'expired cache' {
        It 'queries the registry and rewrites the cache' {
            Set-Cache -Version '1.0.0' -CheckedAtUtc ([datetime]::UtcNow.AddHours(-5))

            $result = Get-LatestClaudeCodeVersion

            $result | Should -Be '9.9.9'
            Should -Invoke Invoke-RestMethod -Times 1

            # Cache should now hold the freshly-queried version.
            $written = Get-Content -Path $script:cacheFile -Raw | ConvertFrom-Json
            $written.version | Should -Be '9.9.9'
            $written.checkedAtUtc | Should -Not -BeNullOrEmpty
        }
    }

    Context 'missing cache' {
        It 'queries the registry and writes a new cache file' {
            Test-Path $script:cacheFile | Should -BeFalse

            $result = Get-LatestClaudeCodeVersion

            $result | Should -Be '9.9.9'
            Should -Invoke Invoke-RestMethod -Times 1
            Test-Path $script:cacheFile | Should -BeTrue
        }
    }

    Context 'corrupt cache file' {
        It 'treats unparsable JSON as a cache miss and does not throw' {
            New-Item -ItemType Directory -Path $script:configDir -Force | Out-Null
            'this is not json {{{' | Set-Content -Path $script:cacheFile -Encoding UTF8

            $result = Get-LatestClaudeCodeVersion

            $result | Should -Be '9.9.9'
            Should -Invoke Invoke-RestMethod -Times 1
        }

        It 'treats a cache missing required fields as a miss' {
            New-Item -ItemType Directory -Path $script:configDir -Force | Out-Null
            '{ "somethingElse": true }' | Set-Content -Path $script:cacheFile -Encoding UTF8

            $result = Get-LatestClaudeCodeVersion

            $result | Should -Be '9.9.9'
            Should -Invoke Invoke-RestMethod -Times 1
        }
    }

    Context 'network failure' {
        It 'returns null quietly when Invoke-RestMethod throws (no cache present)' {
            Mock Invoke-RestMethod { throw 'network down' }

            $result = Get-LatestClaudeCodeVersion

            $result | Should -BeNullOrEmpty
        }

        It 'returns null when the registry response has no version field' {
            Mock Invoke-RestMethod { return [PSCustomObject]@{ name = 'claude-code' } }

            $result = Get-LatestClaudeCodeVersion

            $result | Should -BeNullOrEmpty
        }

        It 'does not write a cache file on network failure' {
            Mock Invoke-RestMethod { throw 'network down' }

            Get-LatestClaudeCodeVersion | Out-Null

            Test-Path $script:cacheFile | Should -BeFalse
        }
    }

    Context '-Force switch' {
        It 'bypasses a fresh cache and queries the registry' {
            Set-Cache -Version '1.0.0' -CheckedAtUtc ([datetime]::UtcNow.AddMinutes(-5))

            $result = Get-LatestClaudeCodeVersion -Force

            $result | Should -Be '9.9.9'
            Should -Invoke Invoke-RestMethod -Times 1
        }
    }

    Context 'cache-write failure' {
        It 'still returns the queried version when the cache cannot be written' {
            # Make the config dir a FILE so the directory-create / Set-Content both fail.
            # The path resolution puts the cache under $HOME/.dclaude; create .dclaude as a file.
            Remove-Item -Path $script:configDir -Recurse -Force -ErrorAction SilentlyContinue
            Set-Content -Path $script:configDir -Value 'blocking file' -Encoding UTF8

            # The cache write fails internally; the call must still return the queried version.
            # 2>$null suppresses the non-terminating Set-Content error the function emits — it
            # does not abort the call (see report note on the cache-write try/catch).
            $result = Get-LatestClaudeCodeVersion 2>$null

            $result | Should -Be '9.9.9'
        }
    }
}
