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
        [string[]]$ClaudeArgs
    )

    # Validate Docker environment and detect container OS
    $containerOS = Test-DockerAvailable
    if ($containerOS -notin @('windows', 'linux')) {
        throw "Unsupported Docker OS type '$containerOS'. Only 'windows' and 'linux' are supported."
    }

    # Resolve working directory to absolute path
    if (-not (Test-Path -Path $Path -PathType Container)) {
        throw "Path '$Path' does not exist or is not a directory."
    }
    $resolvedPath = (Resolve-Path -Path $Path).Path

    # Load project config
    $config = Get-DClaudeConfig -Path $resolvedPath

    # Determine image tag and image-level volumes
    $imageTag = $null
    $imageVolumes = @()
    switch ($PSCmdlet.ParameterSetName) {
        'ByImage' {
            $imageTag = $Image
        }
        'ByImageKey' {
            $resolved = Resolve-ImageKey $ImageKey $containerOS
            $imageTag = $resolved.tag
            $imageVolumes = $resolved.volumes
        }
        'Default' {
            if ($config -and $config.image) {
                $imageTag = $config.image
            }
            elseif ($config -and $config.imageKey) {
                $resolved = Resolve-ImageKey $config.imageKey $containerOS
                $imageTag = $resolved.tag
                $imageVolumes = $resolved.volumes
            }
        }
    }

    if (-not $imageTag) {
        throw "No image specified. Pass -Image, -ImageKey, or set 'image' or 'imageKey' in your project .dclaude/settings.json."
    }

    # Set container paths based on OS type
    if ($containerOS -eq 'windows') {
        $containerWorkspace = 'C:/workspace'
        $containerClaude = 'C:/Users/ContainerUser/.claude'
    }
    else {
        $containerWorkspace = '/workspace'
        $containerClaude = '/mnt/host-claude'
    }

    # Build docker run arguments
    $dockerArgs = @(
        'run', '-it', '--rm'
        '-v', "${resolvedPath}:${containerWorkspace}"
        '-w', $containerWorkspace
    )

    # Mount Claude config directory and settings file
    if (Test-Path $ClaudeConfigPath) {
        $dockerArgs += '-v'
        $dockerArgs += "${ClaudeConfigPath}:${containerClaude}:rw"
    }
    else {
        Write-Warning "Claude config path '$ClaudeConfigPath' not found. Container will start without Claude configuration."
    }

    # Mount .claude.json (lives in home dir, separate from .claude/ directory)
    $claudeJsonPath = Join-Path (Split-Path $ClaudeConfigPath) '.claude.json'
    if (Test-Path $claudeJsonPath) {
        $dockerArgs += '-v'
        $dockerArgs += "${claudeJsonPath}:/mnt/host-claude.json:ro"
    }

    # Mount volumes from image config and project config
    $allVolumes = @()
    if ($imageVolumes.Count -gt 0) {
        $allVolumes += $imageVolumes
    }
    if ($config -and $config.volumes) {
        $allVolumes += @($config.volumes)
    }
    foreach ($vol in $allVolumes) {
        $expanded = [Environment]::ExpandEnvironmentVariables($vol)
        # Enforce read-only unless the volume spec already includes a mode.
        # Use a regex that accounts for Windows drive letters (e.g. C:/host:C:/container).
        if ($expanded -notmatch ':(ro|rw)$') {
            $expanded = "${expanded}:ro"
        }
        $dockerArgs += '-v'
        $dockerArgs += $expanded
    }

    # Pass API key if set
    if ($env:ANTHROPIC_API_KEY) {
        $dockerArgs += '-e'
        $dockerArgs += 'ANTHROPIC_API_KEY'
    }

    # Pass host path so the container can link conversation history for /resume
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_HOST_PATH=$resolvedPath"

    # Add image tag
    $dockerArgs += $imageTag

    # Add any extra arguments for claude
    if ($ClaudeArgs -and $ClaudeArgs.Count -gt 0) {
        $dockerArgs += $ClaudeArgs
    }

    # Launch the container
    & docker @dockerArgs
}
