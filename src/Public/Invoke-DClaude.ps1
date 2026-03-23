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
    Docker image tag to use directly (e.g. 'python:3.12-slim').

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
    Invoke-DClaude -Image 'python:3.12-slim'

    Runs Claude Code using a stock Python image with the current directory mounted.

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

    # Determine image tag, image-level volumes, env passthrough patterns, and env constants
    $imageTag = $null
    $imageVolumes = @()
    $imageEnvPassthrough = @()
    $imageEnv = $null
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
        $imageEnv = $resolved.env
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

    # Read module version for runtime volume naming
    $moduleVersion = $MyInvocation.MyCommand.Module.Version
    if (-not $moduleVersion) {
        # Fallback: read from .psd1 when running outside a loaded module (e.g. dot-sourced)
        $psdPath = Join-Path (Split-Path $PSScriptRoot) 'dclaude.psd1'
        if (Test-Path $psdPath) {
            $psdContent = Import-PowerShellDataFile $psdPath
            $moduleVersion = [version]$psdContent.ModuleVersion
        }
        else {
            $moduleVersion = [version]'0.0.0'
        }
    }

    # Clean up stale runtime volumes from previous module versions
    Remove-StaleRuntimeVolumes -CurrentVersion $moduleVersion

    # Provision runtime volume (Node.js + Claude Code)
    $runtime = Initialize-RuntimeVolume -ContainerOS $containerOS -Version $moduleVersion
    if (-not $runtime) { return }

    # Resolve the entrypoint script path from the module's Images directory
    $imagesDir = Join-Path (Split-Path $PSScriptRoot) 'Images'

    # Build docker run arguments
    $leafName = (Split-Path $resolvedPath -Leaf) -replace '[^a-zA-Z0-9_.-]', '-'
    $containerName = "dclaude-${leafName}-$(Get-Random -Maximum 9999)"
    $dockerArgs = @(
        'run', '-it', '--rm'
        '--name', $containerName
        '-v', "${resolvedPath}:$($paths.Workspace):rw"
        '-w', $paths.Workspace
    )

    # Mount runtime volume (Node.js + Claude Code) read-only
    $dockerArgs += '-v'
    $dockerArgs += "$($runtime.VolumeName):$($runtime.MountPath):ro"

    # Mount entrypoint script from host and override container's entrypoint
    if ($containerOS -eq 'linux') {
        $entrypointHost = Join-Path $imagesDir 'entrypoint.sh'
        $dockerArgs += '-v'
        $dockerArgs += "${entrypointHost}:/mnt/dclaude/entrypoint.sh:ro"
        $dockerArgs += '--entrypoint'
        $dockerArgs += '/mnt/dclaude/entrypoint.sh'
    }
    else {
        $entrypointHost = Join-Path $imagesDir 'entrypoint.ps1'
        $dockerArgs += '-v'
        $dockerArgs += "${entrypointHost}:C:\mnt\dclaude\entrypoint.ps1:ro"
        $dockerArgs += '--entrypoint'
        $dockerArgs += 'powershell'
    }

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
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_WORKSPACE=$($paths.Workspace)"
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_RUNTIME=$($runtime.MountPath)"
    $dockerArgs += '-e'
    $dockerArgs += 'DCLAUDE_CONTAINER=1'

    # Inject env constants from image config
    if ($imageEnv) {
        foreach ($prop in $imageEnv.PSObject.Properties) {
            $dockerArgs += '-e'
            $dockerArgs += "$($prop.Name)=$($prop.Value)"
        }
    }

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

    # Append Docker socket/pipe mount and CLI volume if requested.
    # No pre-existence check on the socket: Docker Desktop resolves paths internally,
    # so Test-Path may fail on the host (e.g. WSL) even when the mount works fine.
    if ($DockerAccess) {
        # Mount the Docker socket (Linux) or named pipe (Windows)
        if ($containerOS -eq 'linux') {
            $dockerArgs += '-v'
            $dockerArgs += '/var/run/docker.sock:/var/run/docker.sock:rw'
        }
        else {
            $dockerArgs += '-v'
            $dockerArgs += '//./pipe/docker_engine://./pipe/docker_engine'
        }

        # Ensure the Docker CLI volume exists and is populated, then mount it.
        # The volume persists across container runs so this only downloads once.
        # Check for the actual binary, not just the volume — Docker auto-creates
        # empty volumes on first mount, so volume existence doesn't mean populated.
        $cliVolume = "dclaude-docker-cli-$containerOS"
        $cliMountPath = if ($containerOS -eq 'linux') { '/opt/docker-cli' } else { 'C:/docker-cli' }
        if ($containerOS -eq 'linux') {
            $volumePopulated = docker run --rm -v "${cliVolume}:/check" alpine test -f /check/docker 2>$null
            $volumePopulated = ($LASTEXITCODE -eq 0)
        }
        else {
            $volumePopulated = docker run --rm -v "${cliVolume}:C:\check" mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd /c "if exist C:\check\docker.exe (exit 0) else (exit 1)" 2>$null
            $volumePopulated = ($LASTEXITCODE -eq 0)
        }
        if (-not $volumePopulated) {
            Write-Host "dclaude: provisioning Docker CLI volume ($cliVolume)..." -ForegroundColor DarkGray
            if ($containerOS -eq 'linux') {
                $script = @'
apk add --no-cache curl >/dev/null 2>&1 && ARCH=$(uname -m) && case "$ARCH" in x86_64) GOARCH=amd64;; aarch64) GOARCH=arm64;; *) GOARCH=$ARCH;; esac && curl -fsSL "https://download.docker.com/linux/static/stable/${ARCH}/docker-27.5.1.tgz" | tar -xz --strip-components=1 -C /out docker/docker && mkdir -p /out/cli-plugins && curl -fsSL -o /out/cli-plugins/docker-compose "https://github.com/docker/compose/releases/download/v2.33.1/docker-compose-linux-${ARCH}" && chmod +x /out/cli-plugins/docker-compose && curl -fsSL -o /out/cli-plugins/docker-buildx "https://github.com/docker/buildx/releases/download/v0.21.1/buildx-v0.21.1.linux-${GOARCH}" && chmod +x /out/cli-plugins/docker-buildx
'@
                docker run --rm -v "${cliVolume}:/out" alpine:latest sh -c $script
            }
            else {
                $script = 'curl -sLo docker.zip https://download.docker.com/win/static/stable/x86_64/docker-27.5.1.zip && tar -xf docker.zip --strip-components=1 -C C:\out docker/docker.exe && del docker.zip && mkdir C:\out\cli-plugins && curl -sLo C:\out\cli-plugins\docker-compose.exe https://github.com/docker/compose/releases/download/v2.33.1/docker-compose-windows-x86_64.exe && curl -sLo C:\out\cli-plugins\docker-buildx.exe https://github.com/docker/buildx/releases/download/v0.21.1/buildx-v0.21.1.windows-amd64.exe'
                docker run --rm -v "${cliVolume}:C:\out" mcr.microsoft.com/windows/servercore:ltsc2022 cmd /c $script
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to provision Docker CLI volume. Check network connectivity."
                return
            }
        }
        $dockerArgs += '-v'
        $dockerArgs += "${cliVolume}:${cliMountPath}:ro"
    }

    # Add image tag
    $dockerArgs += $imageTag

    # On Windows, the entrypoint is 'powershell' — the script path goes after the image tag
    if ($containerOS -eq 'windows') {
        $dockerArgs += '-NoProfile'
        $dockerArgs += '-File'
        $dockerArgs += 'C:\mnt\dclaude\entrypoint.ps1'
    }

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
