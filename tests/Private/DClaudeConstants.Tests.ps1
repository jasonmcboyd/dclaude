BeforeAll {
    . "$PSScriptRoot/../../src/Private/DClaudeConstants.ps1"
}

Describe 'DClaudeConstants' {

    Context 'DClaudeVersions' {
        It 'defines all required version keys' {
            $script:DClaudeVersions | Should -Not -BeNullOrEmpty
            $script:DClaudeVersions.NodeJS | Should -Not -BeNullOrEmpty
            $script:DClaudeVersions.MinGit | Should -Not -BeNullOrEmpty
            $script:DClaudeVersions.DockerCLI | Should -Not -BeNullOrEmpty
            $script:DClaudeVersions.DockerCompose | Should -Not -BeNullOrEmpty
            $script:DClaudeVersions.DockerBuildX | Should -Not -BeNullOrEmpty
        }

        It 'contains only string values' {
            foreach ($key in $script:DClaudeVersions.Keys) {
                $script:DClaudeVersions[$key] | Should -BeOfType [string]
            }
        }
    }

    Context 'DClaudeImages' {
        It 'defines all required image keys' {
            $script:DClaudeImages | Should -Not -BeNullOrEmpty
            $script:DClaudeImages.ProvisionLinux | Should -Not -BeNullOrEmpty
            $script:DClaudeImages.ProvisionWindows | Should -Not -BeNullOrEmpty
            $script:DClaudeImages.CheckLinux | Should -Not -BeNullOrEmpty
            $script:DClaudeImages.CheckWindows | Should -Not -BeNullOrEmpty
        }

        It 'contains only string values' {
            foreach ($key in $script:DClaudeImages.Keys) {
                $script:DClaudeImages[$key] | Should -BeOfType [string]
            }
        }
    }
}
