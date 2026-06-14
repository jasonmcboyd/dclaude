BeforeAll {
    . "$PSScriptRoot/../../Private/Set-VolumeDefaultMode.ps1"
}

Describe 'Set-VolumeDefaultMode' {

    Context 'when no mode is specified (Linux paths)' {
        It 'appends :ro to a Linux volume spec' {
            $result = Set-VolumeDefaultMode -VolumeSpec '/host/path:/container/path'

            $result | Should -Be '/host/path:/container/path:ro'
        }
    }

    Context 'when no mode is specified (Windows paths)' {
        It 'appends :ro to a Windows volume spec' {
            $result = Set-VolumeDefaultMode -VolumeSpec 'C:/host:C:/container'

            $result | Should -Be 'C:/host:C:/container:ro'
        }
    }

    Context 'when :ro is already specified' {
        It 'preserves the existing :ro mode' {
            $result = Set-VolumeDefaultMode -VolumeSpec '/host/path:/container/path:ro'

            $result | Should -Be '/host/path:/container/path:ro'
        }
    }

    Context 'when :rw is already specified' {
        It 'preserves the existing :rw mode' {
            $result = Set-VolumeDefaultMode -VolumeSpec '/host/path:/container/path:rw'

            $result | Should -Be '/host/path:/container/path:rw'
        }
    }

    Context 'Windows drive letter handling' {
        It 'does not confuse the drive colon with a mode suffix' {
            # A Windows path like C:/host:C:/container contains colons after drive
            # letters. The function should only look at a trailing :ro or :rw, not
            # misinterpret the drive-letter colon.
            $result = Set-VolumeDefaultMode -VolumeSpec 'D:/projects:C:/workspace'

            $result | Should -Be 'D:/projects:C:/workspace:ro'
        }
    }
}
