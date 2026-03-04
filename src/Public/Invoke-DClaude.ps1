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

    # Validate Docker environment
    Test-DockerAvailable

    # Resolve working directory to absolute path
    if (-not (Test-Path -Path $Path -PathType Container)) {
        throw "Path '$Path' does not exist or is not a directory."
    }
    $resolvedPath = (Resolve-Path -Path $Path).Path

    # Load project config
    $config = Get-DClaudeConfig -Path $resolvedPath

    # Determine image tag
    $imageTag = $null
    switch ($PSCmdlet.ParameterSetName) {
        'ByImage' {
            $imageTag = $Image
        }
        'ByImageKey' {
            $imageTag = Resolve-ImageKey $ImageKey
        }
        'Default' {
            if ($config -and $config.image) {
                $imageTag = $config.image
            }
            elseif ($config -and $config.imageKey) {
                $imageTag = Resolve-ImageKey $config.imageKey
            }
        }
    }

    if (-not $imageTag) {
        throw "No image specified. Pass -Image, -ImageKey, or create .dclaude/dclaude.json with an 'image' or 'imageKey' property."
    }

    # Build docker run arguments
    $dockerArgs = @(
        'run', '-it', '--rm'
        '-v', "${resolvedPath}:C:/workspace"
        '-w', 'C:/workspace'
    )

    # Mount Claude config if it exists
    if (Test-Path $ClaudeConfigPath) {
        $dockerArgs += '-v'
        $dockerArgs += "${ClaudeConfigPath}:C:/Users/ContainerUser/.claude"
    }
    else {
        Write-Warning "Claude config path '$ClaudeConfigPath' not found. Container will start without Claude configuration."
    }

    # Mount volumes from user config and project config (layered)
    $userConfig = Get-DClaudeUserConfig
    $allVolumes = @()
    if ($userConfig -and $userConfig.volumes) {
        $allVolumes += $userConfig.volumes
    }
    if ($config -and $config.volumes) {
        $allVolumes += $config.volumes
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
