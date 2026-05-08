$script:DClaudeVersions = @{
    NodeJS        = '22.14.0'
    MinGit        = '2.47.1.windows.2'
    DockerCLI     = '27.5.1'
    DockerCompose = '2.33.1'
    DockerBuildX  = '0.21.1'
}

$script:DClaudeImages = @{
    ProvisionLinux   = 'debian:bookworm-slim'
    ProvisionWindows = 'mcr.microsoft.com/windows/servercore:ltsc2022'
    CheckLinux       = 'alpine'
    CheckWindows     = 'mcr.microsoft.com/windows/nanoserver:ltsc2022'
}
