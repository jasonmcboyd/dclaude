function Get-EnvironmentPassthroughArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostPath
    )

    $dockerArgs = @()

    # Pass through Claude Code environment variables (API keys, Vertex/Bedrock config, etc.)
    foreach ($envVar in Get-ChildItem Env:) {
        if ($envVar.Name -match '^(ANTHROPIC_|CLAUDE_CODE_|CLOUD_ML_)') {
            $dockerArgs += '-e'
            $dockerArgs += $envVar.Name
        }
    }

    # Pass host path so the container can link conversation history for /resume
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_HOST_PATH=$HostPath"

    return $dockerArgs
}
