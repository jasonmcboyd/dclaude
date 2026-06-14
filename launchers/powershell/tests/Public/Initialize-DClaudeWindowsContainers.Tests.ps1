BeforeAll {
    . "$PSScriptRoot/../../Public/Initialize-DClaudeWindowsContainers.ps1"
}

Describe 'Initialize-DClaudeWindowsContainers' {

    BeforeEach {
        # Clean slate: remove any leftover .claude dir and .claude.json from previous tests
        $script:claudeDir = Join-Path $TestDrive '.claude'
        $script:claudeJsonPath = Join-Path $TestDrive '.claude.json'
        if (Test-Path $script:claudeDir) { Remove-Item -Recurse -Force $script:claudeDir }
        if (Test-Path $script:claudeJsonPath) { Remove-Item -Force $script:claudeJsonPath }
    }

    Context 'when .claude.json does not exist' {
        It 'returns without error' {
            Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir

            Test-Path (Join-Path $script:claudeDir '.claude.json') | Should -BeFalse
        }
    }

    Context 'when .claude.json is already a symlink' {
        It 'returns without error' {
            New-Item -ItemType Directory -Path $script:claudeDir -Force | Out-Null
            $target = Join-Path $script:claudeDir '.claude.json'
            '{}' | Set-Content $target
            New-Item -ItemType SymbolicLink -Path $script:claudeJsonPath -Target $target -Force | Out-Null

            Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir

            # Should still be a symlink pointing at the original target
            (Get-Item -Force $script:claudeJsonPath).Target | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when .claude.json is a regular file' {
        BeforeEach {
            '{ "key": "value" }' | Set-Content $script:claudeJsonPath
        }

        It 'copies into .claude directory and creates symlink' {
            Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir

            $claudeJsonInDir = Join-Path $script:claudeDir '.claude.json'
            Test-Path $claudeJsonInDir | Should -BeTrue
            (Get-Content $claudeJsonInDir -Raw).Trim() | Should -Be '{ "key": "value" }'
            (Get-Item -Force $script:claudeJsonPath).Target | Should -Not -BeNullOrEmpty
        }

        It 'is idempotent (second run sees the symlink and returns early)' {
            Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir
            Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir

            $claudeJsonInDir = Join-Path $script:claudeDir '.claude.json'
            Test-Path $claudeJsonInDir | Should -BeTrue
            (Get-Item -Force $script:claudeJsonPath).Target | Should -Not -BeNullOrEmpty
        }

        It 'does not modify files when -WhatIf is used' {
            Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir -WhatIf

            $claudeJsonInDir = Join-Path $script:claudeDir '.claude.json'
            Test-Path $claudeJsonInDir | Should -BeFalse
            (Get-Item -Force $script:claudeJsonPath).LinkType | Should -BeNullOrEmpty
        }
    }

    Context 'rollback on symlink failure' {
        It 'removes the copy when symlink creation fails' {
            '{ "key": "value" }' | Set-Content $script:claudeJsonPath

            # Pre-create the .claude directory so the directory New-Item call is not needed
            New-Item -ItemType Directory -Path $script:claudeDir -Force | Out-Null

            Mock New-Item {
                throw 'Simulated symlink failure'
            } -ParameterFilter { $ItemType -eq 'SymbolicLink' }

            Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir -ErrorVariable err -ErrorAction SilentlyContinue

            $err | Should -Not -BeNullOrEmpty
            # The copy should have been cleaned up
            Test-Path (Join-Path $script:claudeDir '.claude.json') | Should -BeFalse
        }
    }
}
