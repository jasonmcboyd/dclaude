BeforeAll {
    . "$PSScriptRoot/../../src/Private/Get-RuntimeVolumeRevision.ps1"
}

Describe 'Get-RuntimeVolumeRevision' {

    Context 'legacy suffixless names' {
        It 'returns 0 for an exact legacy match' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-linux-v1.0.0' -ContainerOS 'linux' -Version ([version]'1.0.0') |
                Should -Be 0
        }

        It 'returns 0 for a Windows legacy match' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-windows-v0.6.4' -ContainerOS 'windows' -Version ([version]'0.6.4') |
                Should -Be 0
        }
    }

    Context 'revisioned names' {
        It 'returns the revision number for an -rN suffix' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-linux-v1.0.0-r2' -ContainerOS 'linux' -Version ([version]'1.0.0') |
                Should -Be 2
        }

        It 'returns a multi-digit revision' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-linux-v1.0.0-r42' -ContainerOS 'linux' -Version ([version]'1.0.0') |
                Should -Be 42
        }

        It 'returns 0 for an explicit -r0' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-linux-v1.0.0-r0' -ContainerOS 'linux' -Version ([version]'1.0.0') |
                Should -Be 0
        }
    }

    Context 'prefix-collision safety' {
        It 'does not match v0.6.4 against a v0.6.40 volume' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-linux-v0.6.40' -ContainerOS 'linux' -Version ([version]'0.6.4') |
                Should -Be -1
        }

        It 'does not match v0.6.40 against a v0.6.4 volume' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-linux-v0.6.4' -ContainerOS 'linux' -Version ([version]'0.6.40') |
                Should -Be -1
        }

        It 'does not match when the OS differs' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-windows-v1.0.0' -ContainerOS 'linux' -Version ([version]'1.0.0') |
                Should -Be -1
        }
    }

    Context 'malformed suffixes' {
        It 'rejects a non-digit revision suffix' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-linux-v1.0.0-rx' -ContainerOS 'linux' -Version ([version]'1.0.0') |
                Should -Be -1
        }

        It 'rejects an unrelated trailing suffix' {
            Get-RuntimeVolumeRevision -Name 'dclaude-runtime-linux-v1.0.0-foo' -ContainerOS 'linux' -Version ([version]'1.0.0') |
                Should -Be -1
        }

        It 'rejects a name with extra leading text' {
            Get-RuntimeVolumeRevision -Name 'x-dclaude-runtime-linux-v1.0.0' -ContainerOS 'linux' -Version ([version]'1.0.0') |
                Should -Be -1
        }

        It 'rejects an entirely unrelated name' {
            Get-RuntimeVolumeRevision -Name 'some-other-volume' -ContainerOS 'linux' -Version ([version]'1.0.0') |
                Should -Be -1
        }
    }
}
