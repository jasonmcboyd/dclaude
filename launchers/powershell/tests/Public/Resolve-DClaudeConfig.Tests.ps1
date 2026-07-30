BeforeAll {
    . "$PSScriptRoot/../../Private/Read-SettingsFile.ps1"
    . "$PSScriptRoot/../../Private/Test-DClaudeSettingsSchema.ps1"
    . "$PSScriptRoot/../../Private/Merge-SettingsFiles.ps1"
    . "$PSScriptRoot/../../Private/Get-VolumeContainerPath.ps1"
    . "$PSScriptRoot/../../Private/Get-DClaudeUserConfig.ps1"
    . "$PSScriptRoot/../../Public/Resolve-DClaudeConfig.ps1"
}

Describe 'Resolve-DClaudeConfig' {

    BeforeEach {
        Mock Get-DClaudeUserConfig { $null }
        Mock Write-Host {}
    }

    Context 'when no config exists' {
        It 'returns null' {
            $emptyDir = Join-Path $TestDrive 'empty'
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*.dclaude' }

            $result = Resolve-DClaudeConfig -Path $emptyDir -Quiet
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'single project config' {
        It 'returns values from that directory' {
            $projectDir = Join-Path $TestDrive 'single'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{
                defaultImageKey = 'python'
                envPassthrough  = @('MY_VAR')
                volumes         = @{ linux = @('/host:/mnt:ro') }
            } | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $configDir 'settings.json')

            $result = Resolve-DClaudeConfig -Path $projectDir -Quiet
            $result.defaultImageKey | Should -Be 'python'
            $result.envPassthrough | Should -Contain 'MY_VAR'
            $result.volumes.linux | Should -Contain '/host:/mnt:ro'
        }
    }

    Context 'multi-level project configs' {
        It 'uses closest scalar value (closest wins)' {
            $rootDir = Join-Path $TestDrive 'scalar-win'
            $childDir = Join-Path $rootDir 'packages/app'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'root-image' } | ConvertTo-Json |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'child-image' } | ConvertTo-Json |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.defaultImageKey | Should -Be 'child-image'
        }

        It 'inherits scalars from parent when child does not define them' {
            $rootDir = Join-Path $TestDrive 'scalar-inherit'
            $childDir = Join-Path $rootDir 'packages/app'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'parent-image' } | ConvertTo-Json |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ envPassthrough = @('CHILD_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.defaultImageKey | Should -Be 'parent-image'
        }

        It 'merges envPassthrough additively across levels' {
            $rootDir = Join-Path $TestDrive 'env-merge'
            $childDir = Join-Path $rootDir 'packages/app'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ envPassthrough = @('ROOT_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ envPassthrough = @('CHILD_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.envPassthrough | Should -Contain 'CHILD_VAR'
            $result.envPassthrough | Should -Contain 'ROOT_VAR'
            $result.envPassthrough.Count | Should -Be 2
        }

        It 'merges volumes additively per platform' {
            $rootDir = Join-Path $TestDrive 'vol-merge'
            $childDir = Join-Path $rootDir 'packages/app'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ volumes = @{ linux = @('/host/root:/container/root:ro') } } | ConvertTo-Json -Depth 3 |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ volumes = @{ linux = @('/host/child:/container/child:ro') } } | ConvertTo-Json -Depth 3 |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.volumes.linux | Should -Contain '/host/child:/container/child:ro'
            $result.volumes.linux | Should -Contain '/host/root:/container/root:ro'
            $result.volumes.linux.Count | Should -Be 2
        }

        It 'composes three levels correctly' {
            $grandparentDir = Join-Path $TestDrive 'three-level'
            $parentDir = Join-Path $grandparentDir 'parent'
            $childDir = Join-Path $parentDir 'child'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $gpConfig = Join-Path $grandparentDir '.dclaude'
            New-Item -Path $gpConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'gp-image'; envPassthrough = @('GP_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $gpConfig 'settings.json')

            $pConfig = Join-Path $parentDir '.dclaude'
            New-Item -Path $pConfig -ItemType Directory -Force | Out-Null
            @{ envPassthrough = @('PARENT_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $pConfig 'settings.json')

            $cConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $cConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'child-image'; envPassthrough = @('CHILD_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $cConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.defaultImageKey | Should -Be 'child-image'
            $result.envPassthrough | Should -Contain 'CHILD_VAR'
            $result.envPassthrough | Should -Contain 'PARENT_VAR'
            $result.envPassthrough | Should -Contain 'GP_VAR'
            $result.envPassthrough.Count | Should -Be 3
        }

        It 'deduplicates exact duplicate volume specs' {
            $rootDir = Join-Path $TestDrive 'vol-dedup'
            $childDir = Join-Path $rootDir 'child'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ volumes = @{ linux = @('/host/a:/mnt/a:ro') } } | ConvertTo-Json -Depth 3 |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ volumes = @{ linux = @('/host/a:/mnt/a:ro') } } | ConvertTo-Json -Depth 3 |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.volumes.linux | Should -Contain '/host/a:/mnt/a:ro'
            $result.volumes.linux.Count | Should -Be 1
        }

        It 'keeps closest volume when container paths conflict' {
            $rootDir = Join-Path $TestDrive 'vol-conflict'
            $childDir = Join-Path $rootDir 'child'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ volumes = @{ linux = @('/host/parent:/mnt/data:ro') } } | ConvertTo-Json -Depth 3 |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ volumes = @{ linux = @('/host/child:/mnt/data:ro') } } | ConvertTo-Json -Depth 3 |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.volumes.linux | Should -Contain '/host/child:/mnt/data:ro'
            $result.volumes.linux | Should -Not -Contain '/host/parent:/mnt/data:ro'
            $result.volumes.linux.Count | Should -Be 1
        }

        It 'keeps both volumes when same source maps to different container paths' {
            $rootDir = Join-Path $TestDrive 'vol-diff-dest'
            $childDir = Join-Path $rootDir 'child'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ volumes = @{ linux = @('/host/a:/mnt/b:ro') } } | ConvertTo-Json -Depth 3 |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ volumes = @{ linux = @('/host/a:/mnt/a:ro') } } | ConvertTo-Json -Depth 3 |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.volumes.linux | Should -Contain '/host/a:/mnt/a:ro'
            $result.volumes.linux | Should -Contain '/host/a:/mnt/b:ro'
            $result.volumes.linux.Count | Should -Be 2
        }
    }

    Context 'user config integration' {
        It 'falls back to user config for defaultImageKey when no project sets it' {
            $projectDir = Join-Path $TestDrive 'user-fallback'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ envPassthrough = @('PROJECT_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')

            Mock Get-DClaudeUserConfig {
                [PSCustomObject]@{ defaultImageKey = 'user-image'; envPassthrough = @('USER_VAR') }
            }

            $result = Resolve-DClaudeConfig -Path $projectDir -Quiet
            $result.defaultImageKey | Should -Be 'user-image'
        }

        It 'merges user envPassthrough with project envPassthrough' {
            $projectDir = Join-Path $TestDrive 'user-env'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ envPassthrough = @('PROJECT_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')

            Mock Get-DClaudeUserConfig {
                [PSCustomObject]@{ envPassthrough = @('USER_VAR') }
            }

            $result = Resolve-DClaudeConfig -Path $projectDir -Quiet
            $result.envPassthrough | Should -Contain 'PROJECT_VAR'
            $result.envPassthrough | Should -Contain 'USER_VAR'
            $result.envPassthrough.Count | Should -Be 2
        }

        It 'project defaultImageKey wins over user defaultImageKey' {
            $projectDir = Join-Path $TestDrive 'user-override'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'project-image' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')

            Mock Get-DClaudeUserConfig {
                [PSCustomObject]@{ defaultImageKey = 'user-image' }
            }

            $result = Resolve-DClaudeConfig -Path $projectDir -Quiet
            $result.defaultImageKey | Should -Be 'project-image'
        }

        It 'merges user volumes with project volumes' {
            $projectDir = Join-Path $TestDrive 'user-vol'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ volumes = @{ linux = @('/project:/proj:ro') } } | ConvertTo-Json -Depth 3 |
                Set-Content (Join-Path $configDir 'settings.json')

            Mock Get-DClaudeUserConfig {
                [PSCustomObject]@{ volumes = [PSCustomObject]@{ linux = @('/user:/usr:ro') } }
            }

            $result = Resolve-DClaudeConfig -Path $projectDir -Quiet
            $result.volumes.linux | Should -Contain '/project:/proj:ro'
            $result.volumes.linux | Should -Contain '/user:/usr:ro'
            $result.volumes.linux.Count | Should -Be 2
        }
    }

    Context 'provenance tracking' {
        It 'populates Sources with config directories in order' {
            $rootDir = Join-Path $TestDrive 'prov-sources'
            $childDir = Join-Path $rootDir 'child'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'root' } | ConvertTo-Json |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'child' } | ConvertTo-Json |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.Sources.Count | Should -BeGreaterOrEqual 2
            $result.Sources[0] | Should -BeLike "*child*"
        }

        It 'tracks DefaultImageKeyProvenance with effective flag' {
            $rootDir = Join-Path $TestDrive 'prov-imgkey'
            $childDir = Join-Path $rootDir 'child'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'root-img' } | ConvertTo-Json |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ defaultImageKey = 'child-img' } | ConvertTo-Json |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.DefaultImageKeyProvenance.Count | Should -Be 2
            $result.DefaultImageKeyProvenance[0].Value | Should -Be 'child-img'
            $result.DefaultImageKeyProvenance[0].Effective | Should -BeTrue
            $result.DefaultImageKeyProvenance[1].Value | Should -Be 'root-img'
            $result.DefaultImageKeyProvenance[1].Effective | Should -BeFalse
        }

        It 'tracks EnvPassthroughProvenance with source directories' {
            $rootDir = Join-Path $TestDrive 'prov-env'
            $childDir = Join-Path $rootDir 'child'
            New-Item -Path $childDir -ItemType Directory -Force | Out-Null

            $rootConfig = Join-Path $rootDir '.dclaude'
            New-Item -Path $rootConfig -ItemType Directory -Force | Out-Null
            @{ envPassthrough = @('ROOT_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $rootConfig 'settings.json')

            $childConfig = Join-Path $childDir '.dclaude'
            New-Item -Path $childConfig -ItemType Directory -Force | Out-Null
            @{ envPassthrough = @('CHILD_VAR') } | ConvertTo-Json |
                Set-Content (Join-Path $childConfig 'settings.json')

            $result = Resolve-DClaudeConfig -Path $childDir -Quiet
            $result.EnvPassthroughProvenance.Count | Should -Be 2
            $result.EnvPassthroughProvenance[0].Pattern | Should -Be 'CHILD_VAR'
            $result.EnvPassthroughProvenance[0].Source | Should -BeLike '*child*'
            $result.EnvPassthroughProvenance[1].Pattern | Should -Be 'ROOT_VAR'
        }
    }

    Context 'deprecated property handling' {
        It 'treats imageKey as defaultImageKey with a warning' {
            $projectDir = Join-Path $TestDrive 'deprecated-ik'
            $configDir = Join-Path $projectDir '.dclaude'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            @{ imageKey = 'old-key' } | ConvertTo-Json |
                Set-Content (Join-Path $configDir 'settings.json')

            $result = Resolve-DClaudeConfig -Path $projectDir -Quiet 3>$null
            $result.defaultImageKey | Should -Be 'old-key'
        }
    }
}
