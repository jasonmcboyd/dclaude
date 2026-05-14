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
    allowing Claude to run Docker commands. Prompts for confirmation due to the
    security implications (root-equivalent host access). Use -Force to skip the prompt.

.PARAMETER Force
    Suppresses the Docker access confirmation prompt. Has no effect without -DockerAccess.

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

        [switch]$DockerAccess,

        [switch]$Force
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

    # Confirm Docker access before doing any provisioning work
    if ($DockerAccess -and -not $Force) {
        $warning = @(
            'Docker socket access grants the container full control of the host Docker daemon.'
            'This is effectively root-equivalent access: the container can start privileged'
            'containers, mount arbitrary host paths, and access host resources.'
        ) -join ' '
        if (-not $PSCmdlet.ShouldContinue($warning, 'Docker Access')) {
            return
        }
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

    if (-not $imageTag -and -not $imageKeyToResolve) {
        $uc = Get-DClaudeUserConfig
        if ($uc -and $uc.PSObject.Properties['defaultImageKey']) {
            $imageKeyToResolve = $uc.defaultImageKey
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
        Write-Error "No image specified. Pass -Image, -ImageKey, set 'image'/'imageKey' in project .dclaude/settings.json, or set 'defaultImageKey' in ~/.dclaude/settings.json."
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

    # Resolve the entrypoint script path from the module's Entrypoints directory.
    # Try sibling of Public/ first (installed module layout), then repo root layout.
    $entrypointsDir = Join-Path (Split-Path $PSScriptRoot) 'Entrypoints'
    if (-not (Test-Path $entrypointsDir)) {
        $entrypointsDir = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'Entrypoints'
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

    # Mount runtime volume (Node.js + Claude Code) read-only
    $dockerArgs += '-v'
    $dockerArgs += "$($runtime.VolumeName):$($runtime.MountPath):ro"

    # Mount entrypoint script from host and override container's entrypoint
    if ($containerOS -eq 'linux') {
        $entrypointHost = Join-Path $entrypointsDir 'entrypoint.sh'
        $dockerArgs += '-v'
        $dockerArgs += "${entrypointHost}:/mnt/dclaude/entrypoint.sh:ro"
        $dockerArgs += '--entrypoint'
        $dockerArgs += '/bin/sh'
    }
    else {
        # Windows containers cannot bind-mount individual files — mount the whole directory.
        $dockerArgs += '-v'
        $dockerArgs += "${entrypointsDir}:C:\mnt\dclaude:ro"
        $dockerArgs += '--entrypoint'
        $dockerArgs += 'powershell'
    }

    # Linux: entrypoint drops privileges via setpriv with --no-new-privs.
    # Windows: --security-opt=no-new-privileges is not supported.
    # No --security-opt flag is needed on either platform.

    # Append platform-specific mount args (claude config, .claude.json, project dir)
    $dockerArgs += $paths.DockerArgs

    # Append volume mounts from user config, image config, and project config
    $userConfig = Get-DClaudeUserConfig
    $userVolumes = @()
    if ($userConfig -and $userConfig.PSObject.Properties['commonVolumes']) {
        $cv = $userConfig.commonVolumes
        if ($cv -is [array]) {
            $userVolumes = @($cv)
        } elseif ($cv -is [PSCustomObject] -and $cv.PSObject.Properties[$containerOS]) {
            $userVolumes = @($cv.$containerOS)
        }
    }
    $projectVolumes = if ($config -and $config.volumes) { @($config.volumes) } else { @() }
    $volumeArgs = Get-VolumeArgs -UserVolumes $userVolumes -ImageVolumes $imageVolumes -ProjectVolumes $projectVolumes -ContainerOS $containerOS
    $dockerArgs += $volumeArgs

    # Append environment variable passthrough (global + image-level patterns)
    $globalEnvPassthrough = if ($userConfig -and $userConfig.PSObject.Properties['envPassthrough']) {
        @($userConfig.envPassthrough)
    } else { @() }
    $envPatterns = $globalEnvPassthrough + $imageEnvPassthrough
    $envPassthroughResult = Get-EnvironmentPassthroughArgs -HostPath $resolvedPath -Patterns $envPatterns
    $dockerArgs += $envPassthroughResult

    # Collect passthrough env var names for container context
    $passthroughNames = @()
    for ($i = 0; $i -lt $envPassthroughResult.Count; $i++) {
        if ($envPassthroughResult[$i] -eq '-e' -and ($i + 1) -lt $envPassthroughResult.Count) {
            $val = $envPassthroughResult[$i + 1]
            $name = if ($val -match '=') { ($val -split '=', 2)[0] } else { $val }
            if ($name -notmatch '^DCLAUDE_') {
                $passthroughNames += $name
            }
        }
    }

    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_WORKSPACE=$($paths.Workspace)"
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_RUNTIME=$($runtime.MountPath)"
    $dockerArgs += '-e'
    $dockerArgs += 'DCLAUDE_CONTAINER=1'
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_IMAGE=$imageTag"
    if ($VerbosePreference -eq 'Continue') {
        $dockerArgs += '-e'
        $dockerArgs += 'DCLAUDE_VERBOSE=1'
    }

    # Inject env constants from image config
    if ($imageEnv) {
        foreach ($prop in $imageEnv.PSObject.Properties) {
            $dockerArgs += '-e'
            $dockerArgs += "$($prop.Name)=$($prop.Value)"
            $passthroughNames += $prop.Name
        }
    }

    # Pass env var name list so entrypoint can document them in context
    if ($passthroughNames.Count -gt 0) {
        $dockerArgs += '-e'
        $dockerArgs += "DCLAUDE_ENV=$(($passthroughNames | Sort-Object -Unique) -join '|')"
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

        $cli = Initialize-DockerCliVolume -ContainerOS $containerOS
        if (-not $cli) { return }
        $dockerArgs += '-v'
        $dockerArgs += "$($cli.VolumeName):$($cli.MountPath):ro"
    }

    # Add image tag
    $dockerArgs += $imageTag

    # Entrypoint script path goes after the image tag (as CMD arguments to the ENTRYPOINT)
    # Linux: /bin/sh runs the mounted script (Windows bind mounts lose the executable bit)
    # Windows: powershell runs the mounted script with -NoProfile -File
    if ($containerOS -eq 'linux') {
        $dockerArgs += '/mnt/dclaude/entrypoint.sh'
    }
    else {
        $dockerArgs += '-NoProfile'
        $dockerArgs += '-File'
        $dockerArgs += 'C:\mnt\dclaude\entrypoint.ps1'
    }

    # Add any extra arguments for claude
    if ($ClaudeArgs -and $ClaudeArgs.Count -gt 0) {
        $dockerArgs += $ClaudeArgs
    }

    Write-LaunchSummary -ImageTag $imageTag -ImageName $imageName -DockerArgs $dockerArgs

    # Launch the container
    & docker @dockerArgs
}
