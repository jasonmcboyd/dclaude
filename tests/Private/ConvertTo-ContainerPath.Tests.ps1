BeforeAll {
    . "$PSScriptRoot/../../src/Private/ConvertTo-ContainerPath.ps1"
}

Describe 'ConvertTo-ContainerPath' {

    Context 'Linux container with Windows host paths' {
        It 'converts a Windows path with backslashes' {
            $result = ConvertTo-ContainerPath -HostPath 'C:\Users\jason\repos\myproject' -ContainerOS 'linux'
            $result | Should -Be '/c/Users/jason/repos/myproject'
        }

        It 'converts a Windows path with forward slashes' {
            $result = ConvertTo-ContainerPath -HostPath 'C:/Users/jason' -ContainerOS 'linux'
            $result | Should -Be '/c/Users/jason'
        }

        It 'converts a Windows path with mixed separators' {
            $result = ConvertTo-ContainerPath -HostPath 'C:\Users/jason\repos' -ContainerOS 'linux'
            $result | Should -Be '/c/Users/jason/repos'
        }

        It 'converts a drive root path' {
            $result = ConvertTo-ContainerPath -HostPath 'C:\' -ContainerOS 'linux'
            $result | Should -Be '/c/'
        }

        It 'lowercases the drive letter' {
            $result = ConvertTo-ContainerPath -HostPath 'C:\Users\jason' -ContainerOS 'linux'
            $result | Should -Be '/c/Users/jason'
        }

        It 'handles an already-lowercase drive letter' {
            $result = ConvertTo-ContainerPath -HostPath 'c:\Users\jason' -ContainerOS 'linux'
            $result | Should -Be '/c/Users/jason'
        }

        It 'strips trailing slash from non-root paths' {
            $result = ConvertTo-ContainerPath -HostPath 'C:\Users\jason\' -ContainerOS 'linux'
            $result | Should -Be '/c/Users/jason'
        }

        It 'preserves trailing slash on drive root' {
            $result = ConvertTo-ContainerPath -HostPath 'C:/' -ContainerOS 'linux'
            $result | Should -Be '/c/'
        }

        It 'handles other drive letters' {
            $result = ConvertTo-ContainerPath -HostPath 'D:\data\projects' -ContainerOS 'linux'
            $result | Should -Be '/d/data/projects'
        }
    }

    Context 'Linux container with Linux host paths' {
        It 'returns a Linux path unchanged' {
            $result = ConvertTo-ContainerPath -HostPath '/home/user/repos' -ContainerOS 'linux'
            $result | Should -Be '/home/user/repos'
        }

        It 'returns a root path unchanged' {
            $result = ConvertTo-ContainerPath -HostPath '/' -ContainerOS 'linux'
            $result | Should -Be '/'
        }
    }

    Context 'Windows container passthrough' {
        It 'returns a Windows path unchanged' {
            $result = ConvertTo-ContainerPath -HostPath 'C:\Users\jason' -ContainerOS 'windows'
            $result | Should -Be 'C:\Users\jason'
        }

        It 'returns a Linux-style path unchanged' {
            $result = ConvertTo-ContainerPath -HostPath '/home/user/repos' -ContainerOS 'windows'
            $result | Should -Be '/home/user/repos'
        }

        It 'returns a forward-slash Windows path unchanged' {
            $result = ConvertTo-ContainerPath -HostPath 'C:/Users/jason/repos' -ContainerOS 'windows'
            $result | Should -Be 'C:/Users/jason/repos'
        }
    }
}
