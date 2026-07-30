BeforeAll {
    . "$PSScriptRoot/../../Private/Get-VolumeContainerPath.ps1"
}

Describe 'Get-VolumeContainerPath' {

    It 'extracts container path from Linux volume spec with mode' {
        Get-VolumeContainerPath '/host/data:/container/data:ro' | Should -Be '/container/data'
    }

    It 'extracts container path from Linux volume spec without mode' {
        Get-VolumeContainerPath '/host/data:/container/data' | Should -Be '/container/data'
    }

    It 'extracts container path from Windows volume spec with mode' {
        Get-VolumeContainerPath 'C:\host:C:\container:rw' | Should -Be 'C:\container'
    }

    It 'extracts container path from Windows volume spec without mode' {
        Get-VolumeContainerPath 'C:\host:C:\container' | Should -Be 'C:\container'
    }

    It 'returns null for unparseable spec' {
        Get-VolumeContainerPath 'garbage' | Should -BeNullOrEmpty
    }
}
