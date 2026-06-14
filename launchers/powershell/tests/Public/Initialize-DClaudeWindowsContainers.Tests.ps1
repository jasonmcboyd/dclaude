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
            # Creating a real symlink requires Administrator/Developer Mode, so we
            # simulate an existing symlink by mocking Get-Item to report a .Target.
            # This exercises the function's early-return path without a real link.
            '{}' | Set-Content $script:claudeJsonPath
            Mock Get-Item { [PSCustomObject]@{ Target = $script:claudeJsonPath } } `
                -ParameterFilter { $Path -like '*.claude.json' }

            # No SymbolicLink should be created and nothing should be copied.
            Mock New-Item { throw 'New-Item should not be called on the early-return path' } `
                -ParameterFilter { $ItemType -eq 'SymbolicLink' }
            Mock Copy-Item { throw 'Copy-Item should not be called on the early-return path' }

            { Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir } |
                Should -Not -Throw

            Should -Not -Invoke New-Item -ParameterFilter { $ItemType -eq 'SymbolicLink' }
            Should -Not -Invoke Copy-Item
        }
    }

    Context 'when .claude.json is a regular file' {
        BeforeEach {
            '{ "key": "value" }' | Set-Content $script:claudeJsonPath
        }

        It 'copies into .claude directory and creates symlink' {
            # Mock the SymbolicLink creation (needs admin) to succeed without making
            # a real link. The Copy-Item into the .claude dir is real and needs no admin.
            Mock New-Item { } -ParameterFilter { $ItemType -eq 'SymbolicLink' }

            Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir

            $claudeJsonInDir = Join-Path $script:claudeDir '.claude.json'
            # The real copy into the .claude directory happened.
            Test-Path $claudeJsonInDir | Should -BeTrue
            (Get-Content $claudeJsonInDir -Raw).Trim() | Should -Be '{ "key": "value" }'

            # The symlink was created at the original path, pointing into the .claude dir.
            Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
                $ItemType -eq 'SymbolicLink' -and
                $Path -eq $script:claudeJsonPath -and
                $Target -eq $claudeJsonInDir
            }
        }

        It 'is idempotent (second run sees the symlink and returns early)' {
            $claudeJsonInDir = Join-Path $script:claudeDir '.claude.json'

            # First run: simulate successful symlink creation without a real link.
            Mock New-Item { } -ParameterFilter { $ItemType -eq 'SymbolicLink' }
            Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir
            Test-Path $claudeJsonInDir | Should -BeTrue

            # Second run: simulate the path now being a symlink so the early-return
            # path is exercised — no further copy/symlink work should occur.
            Mock Get-Item { [PSCustomObject]@{ Target = $claudeJsonInDir } } `
                -ParameterFilter { $Path -like '*.claude.json' }
            Mock Copy-Item { throw 'Copy-Item should not run on the idempotent second pass' }

            { Initialize-DClaudeWindowsContainers -ClaudeConfigPath $script:claudeDir } |
                Should -Not -Throw

            Should -Not -Invoke Copy-Item
            Test-Path $claudeJsonInDir | Should -BeTrue
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
