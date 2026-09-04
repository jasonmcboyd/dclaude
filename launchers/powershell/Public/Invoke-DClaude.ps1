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

.PARAMETER SqlConnection
    One or more SecureString connection strings for SQL Server. Launches an SQL MCP sidecar
    container that holds the credentials and enforces read-only access. The main Claude
    container connects to the sidecar over a Docker network and never sees the connection
    strings. Database names are parsed from the connection strings automatically. Linux
    containers only.

    Example: -SqlConnection (Read-Host 'Connection string' -AsSecureString)

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

.EXAMPLE
    dclaude -SqlConnection (Read-Host -AsSecureString)

    Launches with read-only SQL access. Connection strings are held in a sidecar container.
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

        [System.Security.SecureString[]]$SqlConnection,

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

    # Validate SqlConnection parameter
    if ($SqlConnection) {
        if ($containerOS -ne 'linux') {
            Write-Error '-SqlConnection requires Linux containers. Windows containers are not supported for the SQL MCP sidecar.'
            return
        }
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

    # Resolve effective config (walks all ancestor .dclaude dirs + user config)
    $config = Resolve-DClaudeConfig -Path $resolvedPath -Quiet

    # Determine image tag, image-level volumes, env passthrough patterns, and env constants
    $imageTag = $null
    $imageVolumes = @()
    $imageEnvPassthrough = @()
    $imageEnv = $null
    $imageKeyToResolve = $null
    $imageName = $null
    switch ($PSCmdlet.ParameterSetName) {
        'ByImage' {
            Write-Debug "[image] -Image parameter: $Image"
            $imageTag = $Image
        }
        'ByImageKey' {
            Write-Debug "[image] -ImageKey parameter: $ImageKey"
            $imageKeyToResolve = $ImageKey
        }
        'Default' {
            Write-Debug '[image] No -Image or -ImageKey parameter; checking config'
            if ($config -and $config.defaultImageKey) {
                Write-Debug "[image] Resolved config defaultImageKey = '$($config.defaultImageKey)'"
                $imageKeyToResolve = $config.defaultImageKey
            }
            elseif ($config -and $config.PSObject.Properties['image']) {
                Write-Warning "Config uses deprecated 'image'. Use 'defaultImageKey' instead, or pass -Image to Invoke-DClaude."
                $imageTag = $config.image
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
        Write-Debug "[image] Resolved imageKey '$imageKeyToResolve' -> tag '$imageTag' ($containerOS)"
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

    # On Windows, derive the container's profile dir from the image rather than assuming
    # ContainerAdministrator. Linux needs no probe (fixed claude home).
    $containerProfile = if ($containerOS -eq 'windows') {
        Get-ContainerUserProfile -Image $imageTag
    } else { $null }

    # Resolve container paths and platform-specific mounts
    $paths = Resolve-ContainerPaths -ContainerOS $containerOS -ResolvedPath $resolvedPath -ClaudeConfigPath $ClaudeConfigPath -ContainerUserProfile $containerProfile
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

    # Resolve the Go entrypoint binary (dev override or the module-bundled binary). The runtime
    # volume carries only Node.js + Claude Code; the binary is mounted in from the host below.
    $entrypointBin = Get-DClaudeEntrypointBinary -ContainerOS $containerOS
    if (-not $entrypointBin) { return }

    # Build docker run arguments
    $leafName = (Split-Path $resolvedPath -Leaf) -replace '[^a-zA-Z0-9_.-]', '-'
    $randomSuffix = Get-Random -Maximum 9999
    $containerName = "dclaude-${leafName}-${randomSuffix}"

    # Start SQL MCP sidecar if requested
    $sidecar = $null
    if ($SqlConnection) {
        $networkName = "dclaude-net-${leafName}-${randomSuffix}"
        $sidecar = Start-SqlMcpSidecar -SqlConnections $SqlConnection -NetworkName $networkName -ModuleVersion $moduleVersion
        if (-not $sidecar) { return }
    }
    $dockerArgs = @(
        'run', '-it', '--rm'
        '--name', $containerName
    )

    # Join the sidecar's Docker network
    if ($sidecar) {
        $dockerArgs += '--network'
        $dockerArgs += $sidecar.NetworkName
    }

    $dockerArgs += '-v'
    $dockerArgs += "${resolvedPath}:$($paths.Workspace):rw"
    $dockerArgs += '-w'
    $dockerArgs += $paths.Workspace

    # Mount runtime volume (Node.js + Claude Code) read-only
    $dockerArgs += '-v'
    $dockerArgs += "$($runtime.VolumeName):$($runtime.MountPath):ro"

    # Mount the entrypoint binary from the host and run it directly. The runtime volume carries
    # only Node.js + Claude Code; the binary is supplied by the module (or the dev override).
    if ($containerOS -eq 'linux') {
        $dockerArgs += '-v'
        $dockerArgs += "${entrypointBin}:/mnt/dclaude-bin/dclaude-entrypoint:ro"
        $dockerArgs += '--entrypoint'
        $dockerArgs += '/mnt/dclaude-bin/dclaude-entrypoint'
    }
    else {
        # Windows can't bind-mount a single file, and OneDrive reparse points on the module dir
        # can block Hyper-V mounts. Stage the binary to a content-hashed local cache (non-OneDrive)
        # and mount that directory: the same binary reuses its dir (no re-copy, no lock against a
        # running instance), while a rebuilt dev binary hashes differently and gets a fresh dir.
        $binHash = (Get-FileHash -Path $entrypointBin -Algorithm SHA256).Hash.Substring(0, 16)
        $stageDir = Join-Path $env:LOCALAPPDATA "dclaude\.bin\$binHash"
        $stagedBin = Join-Path $stageDir 'dclaude-entrypoint.exe'
        if (-not (Test-Path $stagedBin)) {
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
            # Copy to a temp name then rename into place (atomic on NTFS), so an interrupted copy
            # can't leave a truncated binary that the hash-keyed Test-Path would trust forever.
            $tmpBin = "$stagedBin.$PID.tmp"
            Copy-Item $entrypointBin $tmpBin -Force
            Move-Item $tmpBin $stagedBin -Force
        }
        $dockerArgs += '-v'
        $dockerArgs += "${stageDir}:C:\mnt\dclaude-bin:ro"
        $dockerArgs += '--entrypoint'
        $dockerArgs += 'C:\mnt\dclaude-bin\dclaude-entrypoint.exe'
    }

    # Linux: entrypoint drops privileges via setpriv with --no-new-privs.
    # Windows: --security-opt=no-new-privileges is not supported.
    # No --security-opt flag is needed on either platform.

    # Append platform-specific mount args (claude config, .claude.json, project dir)
    $dockerArgs += $paths.DockerArgs

    # Append volume mounts from composed config (user + project) and image config
    $composedVolumes = @()
    if ($config -and $config.PSObject.Properties['volumes'] -and $config.volumes.PSObject.Properties[$containerOS]) {
        $composedVolumes = @($config.volumes.$containerOS)
    }
    $volumeArgs = Get-VolumeArgs -ProjectVolumes $composedVolumes -ImageVolumes $imageVolumes -ContainerOS $containerOS
    $dockerArgs += $volumeArgs

    # Append environment variable passthrough (composed config + image-level patterns)
    $composedEnvPassthrough = if ($config -and $config.PSObject.Properties['envPassthrough']) {
        @($config.envPassthrough)
    } else { @() }
    $envPatterns = $imageEnvPassthrough + $composedEnvPassthrough
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
    if ($DebugPreference -eq 'Continue') {
        $dockerArgs += '-e'
        $dockerArgs += 'DCLAUDE_DEBUG=1'
    }

    # Go entrypoint contract: host-OS seam, the container ~/.claude path, and the contract version.
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_HOST_OS=$(Get-DClaudeHostOS)"
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_CLAUDE_HOME=$($paths.ClaudeHome)"
    $dockerArgs += '-e'
    $dockerArgs += 'DCLAUDE_CONTRACT=1'

    # Inject MCP sidecar config for the Go entrypoint to merge into .claude.json
    if ($sidecar) {
        $mcpInject = @{ 'sql-mcp' = @{ url = $sidecar.McpUrl } } | ConvertTo-Json -Compress
        $dockerArgs += '-e'
        $dockerArgs += "DCLAUDE_MCP_INJECT=$mcpInject"
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

    # The Go entrypoint binary takes claude args directly, so no CMD prefix is needed here;
    # the claude args (below) are passed straight to the binary as the container command.

    # Add any extra arguments for claude
    if ($ClaudeArgs -and $ClaudeArgs.Count -gt 0) {
        $dockerArgs += $ClaudeArgs
    }

    Write-LaunchSummary -ImageTag $imageTag -ImageName $imageName -DockerArgs $dockerArgs

    # Launch the container
    if ($sidecar) {
        try {
            & docker @dockerArgs
        }
        finally {
            Stop-SqlMcpSidecar -SidecarName $sidecar.SidecarName -NetworkName $sidecar.NetworkName
        }
    }
    else {
        & docker @dockerArgs
    }
}
