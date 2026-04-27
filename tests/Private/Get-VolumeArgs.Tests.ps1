BeforeAll {
    . "$PSScriptRoot/../../src/Private/ConvertTo-ContainerPath.ps1"
    . "$PSScriptRoot/../../src/Private/Set-VolumeDefaultMode.ps1"
    . "$PSScriptRoot/../../src/Private/Get-VolumeArgs.ps1"
}

Describe 'Get-VolumeArgs' {

    Context 'when no volumes are provided' {
        It 'returns an empty array' {
            $result = Get-VolumeArgs -ContainerOS windows
            $result | Should -HaveCount 0
        }

        It 'returns an empty array when both parameters are empty' {
            $result = Get-VolumeArgs -ImageVolumes @() -ProjectVolumes @() -ContainerOS windows
            $result | Should -HaveCount 0
        }
    }

    Context 'default mode' {
        It 'appends :ro to volumes without a mode' {
            $result = Get-VolumeArgs -ImageVolumes @('/host:/container') -ContainerOS windows
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*-v /host:/container:ro*'
        }

        It 'appends :ro to Windows volumes without a mode' {
            $result = Get-VolumeArgs -ImageVolumes @('C:/host:C:/container') -ContainerOS windows
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*-v C:/host:C:/container:ro*'
        }
    }

    Context 'explicit mode preserved' {
        It 'preserves :rw when specified' {
            $result = Get-VolumeArgs -ImageVolumes @('/host:/container:rw') -ContainerOS windows
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*-v /host:/container:rw*'
            $argsString | Should -Not -BeLike '*:rw:ro*'
        }

        It 'preserves :ro when specified' {
            $result = Get-VolumeArgs -ImageVolumes @('/host:/container:ro') -ContainerOS windows
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*-v /host:/container:ro*'
        }
    }

    Context 'merging image and project volumes' {
        It 'includes both image-level and project-level volumes' {
            $result = Get-VolumeArgs -ImageVolumes @('/img:/img-mount') -ProjectVolumes @('/proj:/proj-mount:rw') -ContainerOS windows
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*-v /img:/img-mount:ro*'
            $argsString | Should -BeLike '*-v /proj:/proj-mount:rw*'
        }
    }

    Context 'environment variable expansion' {
        AfterEach {
            [Environment]::SetEnvironmentVariable('TEST_DCLAUDE_VOL_PATH', $null)
        }

        It 'expands %VAR% syntax in volume paths' {
            [Environment]::SetEnvironmentVariable('TEST_DCLAUDE_VOL_PATH', '/test/expanded')

            $result = Get-VolumeArgs -ImageVolumes @('%TEST_DCLAUDE_VOL_PATH%:/container') -ContainerOS windows
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*-v /test/expanded:/container:ro*'
        }

        It 'includes expanded path in DCLAUDE_VOLUMES' {
            [Environment]::SetEnvironmentVariable('TEST_DCLAUDE_VOL_PATH', '/test/expanded')

            $result = Get-VolumeArgs -ImageVolumes @('%TEST_DCLAUDE_VOL_PATH%:/container') -ContainerOS windows
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*DCLAUDE_VOLUMES=/test/expanded:/container:ro*'
        }
    }

    Context 'DCLAUDE_VOLUMES environment variable' {
        It 'sets DCLAUDE_VOLUMES as pipe-separated list' {
            $result = Get-VolumeArgs -ImageVolumes @('/a:/b', '/c:/d:rw') -ContainerOS windows
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*DCLAUDE_VOLUMES=/a:/b:ro|/c:/d:rw*'
        }

        It 'includes -e flag before DCLAUDE_VOLUMES' {
            $result = Get-VolumeArgs -ImageVolumes @('/a:/b') -ContainerOS windows
            $volIdx = $result | ForEach-Object { $_ } | Where-Object { $_ -like 'DCLAUDE_VOLUMES=*' }
            $volIdx | Should -Not -BeNullOrEmpty
            $idx = [array]::IndexOf($result, ($volIdx | Select-Object -First 1))
            $result[$idx - 1] | Should -Be '-e'
        }

        It 'does not include DCLAUDE_VOLUMES when no volumes provided' {
            $result = Get-VolumeArgs -ContainerOS windows
            $result -join ' ' | Should -Not -BeLike '*DCLAUDE_VOLUMES*'
        }
    }

    Context 'Linux container path translation' {
        It 'converts Windows container path to Linux format' {
            $result = Get-VolumeArgs -ImageVolumes @('C:\Users\jboyd\data:C:\data:rw') -ContainerOS linux
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*-v C:\Users\jboyd\data:/c/data:rw*'
        }

        It 'converts container path without mode' {
            $result = Get-VolumeArgs -ImageVolumes @('C:\host:C:\container') -ContainerOS linux
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*-v C:\host:/c/container:ro*'
        }

        It 'leaves Linux paths unchanged for Linux containers' {
            $result = Get-VolumeArgs -ImageVolumes @('/host:/container:rw') -ContainerOS linux
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*-v /host:/container:rw*'
        }

        It 'converts UNC-style host with drive-letter container path' {
            $result = Get-VolumeArgs -ImageVolumes @('\\Users\jboyd\repos:c:\blueprint:rw') -ContainerOS linux
            $argsString = $result -join ' '
            $argsString | Should -BeLike '*:/c/blueprint:rw*'
        }
    }
}
