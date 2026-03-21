<#
.SYNOPSIS
    Runs Claude Code inside a Docker container.

.DESCRIPTION
    Launches an interactive Docker container with Claude Code, mounting the
    specified working directory and Claude configuration. The container provides
    a security boundary so Claude Code can run with --dangerously-skip-permissions
    without risk to the host system.

    The image to use is resolved in priority order: -Image parameter, -ImageKey
    parameter, project config image, project config imageKey.

.PARAMETER Image
    Docker image tag to use directly (e.g. 'dclaude-pwsh:latest').

.PARAMETER ImageKey
    Key referencing an image registered in ~/.dclaude/settings.json.

.PARAMETER Path
    Working directory to mount into the container. Defaults to the current directory.

.PARAMETER ClaudeConfigPath
    Path to the Claude configuration directory. Defaults to ~/.claude.

.PARAMETER ClaudeArgs
    Additional arguments passed through to the claude command inside the container.

.PARAMETER DockerAccess
    Mounts the Docker socket (Linux) or named pipe (Windows) into the container,
    allowing Claude to run Docker commands. Requires Docker to be accessible on the host.

.EXAMPLE
    Invoke-DClaude -Image 'dclaude-pwsh:latest'

    Runs Claude Code using the specified image with the current directory mounted.

.EXAMPLE
    Invoke-DClaude -ImageKey 'pwsh' -Path C:\repos\my-project

    Resolves the 'pwsh' image from user config and mounts the specified project directory.

.EXAMPLE
    dclaude --resume

    Uses the 'dclaude' alias with project config, passing --resume to Claude Code.

.EXAMPLE
    dclaude -DockerAccess

    Runs with the Docker socket mounted, allowing Claude to build images and run containers.
#>
function Invoke-DClaude {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param(
        [Parameter(ParameterSetName = 'ByImage', Mandatory)]
        [string]$Image,

        [Parameter(ParameterSetName = 'ByImageKey', Mandatory)]
        [string]$ImageKey,

        [Parameter()]
        [string]$Path = $PWD,

        [Parameter()]
        [string]$ClaudeConfigPath = (Join-Path $HOME '.claude'),

        [Parameter(ValueFromRemainingArguments)]
        [string[]]$ClaudeArgs,

        [switch]$DockerAccess
    )

    # Intercept --help / -h when it's the only remaining argument
    if ($ClaudeArgs -and $ClaudeArgs.Count -eq 1 -and $ClaudeArgs[0] -in @('--help', '-h')) {
        Get-Help $MyInvocation.MyCommand -Full
        return
    }

    # Validate Docker environment and detect container OS
    $containerOS = Get-DockerContainerOS
    if (-not $containerOS) { return }
    $containerOS = $containerOS.ToLower()
    if ($containerOS -notin @('windows', 'linux')) {
        Write-Error "Unsupported Docker OS type '$containerOS'. Only 'windows' and 'linux' are supported."
        return
    }

    # Resolve working directory to absolute path
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "Path '$Path' does not exist or is not a directory."
        return
    }
    $resolvedPath = (Resolve-Path -Path $Path).Path

    # Load project config
    $config = Get-DClaudeConfig -Path $resolvedPath

    # Determine image tag, image-level volumes, and env passthrough patterns
    $imageTag = $null
    $imageVolumes = @()
    $imageEnvPassthrough = @()
    $imageKeyToResolve = $null
    $imageName = $null
    switch ($PSCmdlet.ParameterSetName) {
        'ByImage' {
            $imageTag = $Image
        }
        'ByImageKey' {
            $imageKeyToResolve = $ImageKey
        }
        'Default' {
            if ($config -and $config.image) {
                $imageTag = $config.image
            }
            elseif ($config -and $config.imageKey) {
                $imageKeyToResolve = $config.imageKey
            }
        }
    }

    if ($imageKeyToResolve) {
        $imageName = $imageKeyToResolve
        $resolved = Resolve-ImageKey $imageKeyToResolve $containerOS
        if (-not $resolved) { return }
        $imageTag = $resolved.tag
        $imageVolumes = $resolved.volumes
        $imageEnvPassthrough = $resolved.envPassthrough
    }

    if (-not $imageTag) {
        Write-Error "No image specified. Pass -Image, -ImageKey, or set 'image' or 'imageKey' in your project .dclaude/settings.json."
        return
    }

    # Resolve container paths and platform-specific mounts
    $paths = Resolve-ContainerPaths -ContainerOS $containerOS -ResolvedPath $resolvedPath -ClaudeConfigPath $ClaudeConfigPath
    if ($paths.Errors.Count -gt 0) {
        foreach ($err in $paths.Errors) {
            Write-Error $err
        }
        return
    }

    # Build docker run arguments
    $leafName = (Split-Path $resolvedPath -Leaf) -replace '[^a-zA-Z0-9_.-]', '-'
    $containerName = "dclaude-${leafName}-$(Get-Random -Maximum 9999)"
    $dockerArgs = @(
        'run', '-it', '--rm'
        '--name', $containerName
        '-v', "${resolvedPath}:$($paths.Workspace):rw"
        '-w', $paths.Workspace
    )

    # Linux: entrypoint drops privileges via setpriv with --no-new-privs.
    # Windows: --security-opt=no-new-privileges is not supported.
    # No --security-opt flag is needed on either platform.

    # Append platform-specific mount args (claude config, .claude.json, project dir)
    $dockerArgs += $paths.DockerArgs

    # Append volume mounts from image config and project config
    $projectVolumes = if ($config -and $config.volumes) { @($config.volumes) } else { @() }
    $volumeArgs = Get-VolumeArgs -ImageVolumes $imageVolumes -ProjectVolumes $projectVolumes
    $dockerArgs += $volumeArgs

    # Append environment variable passthrough (global + image-level patterns)
    $userConfig = Get-DClaudeUserConfig
    $globalEnvPassthrough = if ($userConfig -and $userConfig.PSObject.Properties['envPassthrough']) {
        @($userConfig.envPassthrough)
    } else { @() }
    $envPatterns = $globalEnvPassthrough + $imageEnvPassthrough
    $dockerArgs += Get-EnvironmentPassthroughArgs -HostPath $resolvedPath -Patterns $envPatterns

    # Mount init.d directories for user/project init scripts
    $dclaudeUserDir = Join-Path $HOME '.dclaude'
    $dclaudeProjectDir = Join-Path $resolvedPath '.dclaude'
    $initBase = if ($containerOS -eq 'linux') { '/mnt/init.d' } else { 'C:/mnt/init.d' }

    $initDirs = @(
        @{ Host = Join-Path $dclaudeUserDir 'common.init.d'; Container = "$initBase/user-common" }
    )
    if ($imageName) {
        $initDirs += @{ Host = Join-Path $dclaudeUserDir "$imageName.init.d"; Container = "$initBase/user-image" }
    }
    $initDirs += @{ Host = Join-Path $dclaudeProjectDir 'common.init.d'; Container = "$initBase/project-common" }
    if ($imageName) {
        $initDirs += @{ Host = Join-Path $dclaudeProjectDir "$imageName.init.d"; Container = "$initBase/project-image" }
    }

    foreach ($dir in $initDirs) {
        if (Test-Path $dir.Host) {
            $dockerArgs += '-v'
            $dockerArgs += "$($dir.Host):$($dir.Container):ro"
        }
    }

    # Append Docker socket/pipe mount if requested
    if ($DockerAccess) {
        if ($containerOS -eq 'linux') {
            $socketPath = '/var/run/docker.sock'
            if (-not (Test-Path -Path $socketPath)) {
                Write-Error "Docker socket not found at '$socketPath'. Is Docker running?"
                return
            }
            $dockerArgs += '-v'
            $dockerArgs += '/var/run/docker.sock:/var/run/docker.sock:rw'
        }
        else {
            $pipePath = '//./pipe/docker_engine'
            if (-not (Test-Path -Path $pipePath)) {
                Write-Error "Docker named pipe not found at '$pipePath'. Is Docker running?"
                return
            }
            $dockerArgs += '-v'
            $dockerArgs += '//./pipe/docker_engine://./pipe/docker_engine'
        }
    }

    # Add image tag
    $dockerArgs += $imageTag

    # Add any extra arguments for claude
    if ($ClaudeArgs -and $ClaudeArgs.Count -gt 0) {
        $dockerArgs += $ClaudeArgs
    }

    # Display effective mounts before launching
    Write-Host "dclaude: mounting volumes:" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $dockerArgs.Count; $i++) {
        if ($dockerArgs[$i] -eq '-v' -and ($i + 1) -lt $dockerArgs.Count) {
            Write-Host "  $($dockerArgs[$i + 1])" -ForegroundColor DarkGray
        }
    }

    # Display environment variables being passed through
    $envVars = @()
    for ($i = 0; $i -lt $dockerArgs.Count; $i++) {
        if ($dockerArgs[$i] -eq '-e' -and ($i + 1) -lt $dockerArgs.Count) {
            $envVars += $dockerArgs[$i + 1]
        }
    }
    if ($envVars.Count -gt 0) {
        Write-Host "dclaude: environment variables:" -ForegroundColor DarkGray
        foreach ($envVar in $envVars) {
            Write-Host "  $envVar" -ForegroundColor DarkGray
        }
    }
    Write-Host ""

    # Launch the container
    & docker @dockerArgs
}
