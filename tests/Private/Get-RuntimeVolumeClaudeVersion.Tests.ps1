BeforeAll {
    . "$PSScriptRoot/../../src/Private/DClaudeConstants.ps1"
    . "$PSScriptRoot/../../src/Private/Get-RuntimeVolumeClaudeVersion.ps1"

    function docker { }
}

Describe 'Get-RuntimeVolumeClaudeVersion' {

    BeforeEach {
        Mock docker { $global:LASTEXITCODE = 0 }
    }

    Context 'when the volume carries the version label' {
        It 'returns the label value' {
            Mock docker {
                $global:LASTEXITCODE = 0
                return '1.2.3'
            }

            Get-RuntimeVolumeClaudeVersion -VolumeName 'dclaude-runtime-linux-v1.0.0-r1' | Should -Be '1.2.3'
        }

        It 'trims surrounding whitespace from the label value' {
            Mock docker {
                $global:LASTEXITCODE = 0
                return "  1.2.3`n"
            }

            Get-RuntimeVolumeClaudeVersion -VolumeName 'v' | Should -Be '1.2.3'
        }

        It 'queries via docker volume inspect with the label key in the format template' {
            Mock docker {
                $global:LASTEXITCODE = 0
                return '1.2.3'
            }

            Get-RuntimeVolumeClaudeVersion -VolumeName 'v' | Out-Null

            Should -Invoke docker -ParameterFilter {
                ($args -join ' ') -like '*volume inspect*dclaude.cc-version*'
            }
        }
    }

    Context 'when the label is missing' {
        It 'returns null when docker renders the literal no-value placeholder' {
            Mock docker {
                $global:LASTEXITCODE = 0
                return '<no value>'
            }

            Get-RuntimeVolumeClaudeVersion -VolumeName 'v' | Should -BeNullOrEmpty
        }

        It 'returns null when the output is empty' {
            Mock docker {
                $global:LASTEXITCODE = 0
                return ''
            }

            Get-RuntimeVolumeClaudeVersion -VolumeName 'v' | Should -BeNullOrEmpty
        }
    }

    Context 'when inspect fails' {
        It 'returns null on a non-zero exit code' {
            Mock docker {
                $global:LASTEXITCODE = 1
                return $null
            }

            Get-RuntimeVolumeClaudeVersion -VolumeName 'does-not-exist' | Should -BeNullOrEmpty
        }
    }
}
