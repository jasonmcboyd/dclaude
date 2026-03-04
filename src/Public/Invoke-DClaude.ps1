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
            $resolved = Resolve-ImageKey $ImageKey
            $imageTag = $resolved.tag
            $imageVolumes = $resolved.volumes
        }
        'Default' {
            if ($config -and $config.image) {
                $imageTag = $config.image
            }
            elseif ($config -and $config.imageKey) {
                $resolved = Resolve-ImageKey $config.imageKey
                $imageTag = $resolved.tag
                $imageVolumes = $resolved.volumes
            }
        }
    }

    if (-not $imageTag) {
        throw "No image specified. Pass -Image, -ImageKey, or create .dclaude/settings.json with an 'image' or 'imageKey' property."
    }

    # Set container paths based on OS type
    if ($containerOS -eq 'windows') {
        $containerWorkspace = 'C:/workspace'
        $containerClaude = 'C:/Users/ContainerUser/.claude'
    }
    else {
        $containerWorkspace = '/workspace'
        $containerClaude = '/root/.claude'
    }

    # Build docker run arguments
    $dockerArgs = @(
        'run', '-it', '--rm'
        '-v', "${resolvedPath}:${containerWorkspace}"
        '-w', $containerWorkspace
    )

    # Mount Claude config if it exists
    if (Test-Path $ClaudeConfigPath) {
        $dockerArgs += '-v'
        $dockerArgs += "${ClaudeConfigPath}:${containerClaude}"
    }
    else {
        Write-Warning "Claude config path '$ClaudeConfigPath' not found. Container will start without Claude configuration."
    }

    # Mount volumes from image config and project config (layered)
    $allVolumes = @()
    if ($imageVolumes.Count -gt 0) {
        $allVolumes += $imageVolumes
    }
    if ($config -and $config.volumes) {
        $allVolumes += @($config.volumes)
    }
    foreach ($vol in $allVolumes) {
        $expanded = [Environment]::ExpandEnvironmentVariables($vol)
        $dockerArgs += '-v'
        $dockerArgs += $expanded
    }

    # Pass API key if set
    if ($env:ANTHROPIC_API_KEY) {
        $dockerArgs += '-e'
        $dockerArgs += "ANTHROPIC_API_KEY=$env:ANTHROPIC_API_KEY"
    }

    # Add image tag
    $dockerArgs += $imageTag

    # Add any extra arguments for claude
    if ($ClaudeArgs -and $ClaudeArgs.Count -gt 0) {
        $dockerArgs += $ClaudeArgs
    }

    # Launch the container
    & docker @dockerArgs
}
