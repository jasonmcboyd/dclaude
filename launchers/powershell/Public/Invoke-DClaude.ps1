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

.PARAMETER Update
    Before launching, check whether the runtime volume's Claude Code is older than the latest
    published version and provision an updated runtime volume if so. Running containers are
    unaffected.

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

        [switch]$Force,

        [switch]$Update
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
            if ($config -and $config.PSObject.Properties['defaultImageKey']) {
                $imageKeyToResolve = $config.defaultImageKey
            }
            elseif ($config -and $config.PSObject.Properties['imageKey']) {
                Write-Warning "Project config uses deprecated 'imageKey'. Rename to 'defaultImageKey'."
                $imageKeyToResolve = $config.imageKey
            }
            elseif ($config -and $config.PSObject.Properties['image']) {
                Write-Warning "Project config uses deprecated 'image'. Use 'defaultImageKey' instead, or pass -Image to Invoke-DClaude."
                $imageTag = $config.image
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
        Write-Error "No image specified. Pass -Image, -ImageKey, set 'defaultImageKey' in project .dclaude/settings.json, or set 'defaultImageKey' in ~/.dclaude/settings.json."
        return
    }

    # Ensure the permanent dclaude rules file exists on the host.
    # This provides container context to Claude via env vars rather than
    # generating a file at runtime that needs cleanup.
    $dclaudeRulesFile = Join-Path $ClaudeConfigPath 'rules' 'dclaude-rules.md'
    if (-not (Test-Path $dclaudeRulesFile)) {
        New-Item -ItemType Directory -Path (Split-Path $dclaudeRulesFile) -Force | Out-Null
        @'
# dclaude Container Context

When the environment variable DCLAUDE_HOST_PATH is set, you are running
inside a dclaude Docker container. The following applies:

- The workspace is mounted from the host path in DCLAUDE_HOST_PATH.
- The container image is in DCLAUDE_IMAGE.
- Additional volume mounts are in DCLAUDE_VOLUMES (pipe-separated specs: host:container:mode).
- Passthrough environment variable names are in DCLAUDE_ENV (pipe-separated).
- Paths referenced in CLAUDE.md or other instructions may refer to host-only locations
  not mounted in this container.

When a referenced path does not exist:
1. Do NOT search for it or attempt workarounds.
2. Inform the user it was not mounted into the container.
3. Suggest they add a volume mount in their dclaude project or image configuration.
'@ | Set-Content $dclaudeRulesFile -Encoding UTF8
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
    $moduleVersion = Get-DClaudeModuleVersion

    # Optionally provision a fresh runtime volume if the selected one's Claude Code is outdated.
    # Runs before selection/cleanup so the newly provisioned higher revision is picked up below.
    if ($Update) {
        Update-RuntimeIfOutdated -ContainerOS $containerOS -ModuleVersion $moduleVersion
    }

    # Clean up stale runtime volumes from previous module versions
    Remove-StaleRuntimeVolumes -CurrentVersion $moduleVersion

    # Provision runtime volume (Node.js + Claude Code)
    $runtime = Initialize-RuntimeVolume -ContainerOS $containerOS -Version $moduleVersion
    if (-not $runtime) { return }

    # Resolve the entrypoint script path. The entrypoints directory is a sibling of Public/
    # in both the repo layout (launchers/powershell/) and the installed module.
    $entrypointsDir = Join-Path (Split-Path $PSScriptRoot) 'entrypoints'

    # Windows containers: always stage entrypoint.ps1 to a local LOCALAPPDATA cache
    # before mounting. This guarantees the file has no OneDrive reparse point attributes
    # that would prevent Hyper-V from bind-mounting it into the container.
    if ($containerOS -eq 'windows') {
        $entrypointCache = Join-Path $env:LOCALAPPDATA "dclaude\.entrypoints\v$moduleVersion"
        New-Item -ItemType Directory -Path $entrypointCache -Force | Out-Null
        Copy-Item (Join-Path $entrypointsDir 'entrypoint.ps1') $entrypointCache -Force
        $entrypointsDir = $entrypointCache
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

    # Go entrypoint (roadmap phase 4, gated; Linux only until Windows parity lands in phase 5).
    # When enabled, invoke the binary baked into the runtime volume directly instead of mounting
    # and running the shell entrypoint.
    $goBinary = (Test-GoEntrypointEnabled) -and ($containerOS -eq 'linux')

    # Mount entrypoint script from host and override container's entrypoint
    if ($goBinary) {
        $dockerArgs += '--entrypoint'
        $dockerArgs += "$($runtime.MountPath)/bin/dclaude-entrypoint"
    }
    elseif ($containerOS -eq 'linux') {
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
    $userVolumeProp = if ($userConfig -and $userConfig.PSObject.Properties['volumes']) {
        $userConfig.volumes
    } elseif ($userConfig -and $userConfig.PSObject.Properties['commonVolumes']) {
        Write-Warning "User config uses deprecated 'commonVolumes'. Rename to 'volumes'."
        $userConfig.commonVolumes
    } else { $null }
    if ($userVolumeProp) {
        if ($userVolumeProp -is [array]) {
            $userVolumes = @($userVolumeProp)
        } elseif ($userVolumeProp -is [PSCustomObject] -and $userVolumeProp.PSObject.Properties[$containerOS]) {
            $userVolumes = @($userVolumeProp.$containerOS)
        }
    }
    $projectVolumeProp = if ($config -and $config.PSObject.Properties['volumes']) { $config.volumes } else { $null }
    $projectVolumes = @()
    if ($projectVolumeProp) {
        if ($projectVolumeProp -is [PSCustomObject] -and $projectVolumeProp.PSObject.Properties[$containerOS]) {
            $projectVolumes = @($projectVolumeProp.$containerOS)
        } elseif ($projectVolumeProp -is [array]) {
            Write-Warning "Project config uses flat array for 'volumes'. Use platform-keyed object format: { `"windows`": [...], `"linux`": [...] }"
            $projectVolumes = @($projectVolumeProp)
        }
    }
    $volumeArgs = Get-VolumeArgs -UserVolumes $userVolumes -ImageVolumes $imageVolumes -ProjectVolumes $projectVolumes -ContainerOS $containerOS
    $dockerArgs += $volumeArgs

    # Append environment variable passthrough (global + image-level + project-level patterns)
    $globalEnvPassthrough = if ($userConfig -and $userConfig.PSObject.Properties['envPassthrough']) {
        @($userConfig.envPassthrough)
    } else { @() }
    $projectEnvPassthrough = if ($config -and $config.PSObject.Properties['envPassthrough']) {
        @($config.envPassthrough)
    } else { @() }
    $envPatterns = $globalEnvPassthrough + $imageEnvPassthrough + $projectEnvPassthrough
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

    # Go entrypoint contract: host-OS seam, the container ~/.claude path, and the contract version.
    if ($goBinary) {
        $dockerArgs += '-e'
        $dockerArgs += "DCLAUDE_HOST_OS=$(Get-DClaudeHostOS)"
        $dockerArgs += '-e'
        $dockerArgs += "DCLAUDE_CLAUDE_HOME=$($paths.ClaudeHome)"
        $dockerArgs += '-e'
        $dockerArgs += 'DCLAUDE_CONTRACT=1'
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

    # Entrypoint script path goes after the image tag (as CMD arguments to the ENTRYPOINT).
    # The Go binary entrypoint takes claude args directly, so it needs no script path.
    # Linux: /bin/sh runs the mounted script (Windows bind mounts lose the executable bit)
    # Windows: powershell runs the mounted script with -NoProfile -File
    if ($goBinary) {
        # no CMD prefix — claude args (below) are passed straight to the binary
    }
    elseif ($containerOS -eq 'linux') {
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
