function Invoke-DClaude {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Image,

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

    # Determine image
    $imageTag = $null
    if ($Image) {
        $imageTag = $Image
    }
    else {
        $config = Get-DClaudeConfig -Path $resolvedPath
        if ($config -and $config.image) {
            $imageTag = $config.image
        }
    }

    if (-not $imageTag) {
        throw "No image specified. Either pass -Image or create .dclaude/dclaude.json with:`n{`n  `"image`": `"dclaude-dotnet-framework-4.8`"`n}"
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
