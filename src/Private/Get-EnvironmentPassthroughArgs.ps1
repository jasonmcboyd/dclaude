function Get-EnvironmentPassthroughArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostPath,

        [Parameter()]
        [string[]]$Patterns = @()
    )

    $dockerArgs = @()

    # Always pass through Claude Code variables
    $allPatterns = @('^ANTHROPIC_', '^CLAUDE_CODE_', '^CLOUD_ML_')

    # Convert user-specified patterns (e.g. 'NUGET_*', 'AZURE_DEVOPS_PAT') to regex
    foreach ($p in $Patterns) {
        if ($p -match '[*?]') {
            # Glob-style pattern — convert to regex
            $escaped = [regex]::Escape($p) -replace '\\[*]', '.*' -replace '\\[?]', '.'
            $allPatterns += "^${escaped}$"
        }
        else {
            # Exact name
            $allPatterns += "^$([regex]::Escape($p))$"
        }
    }

    $combinedRegex = ($allPatterns -join '|')

    foreach ($envVar in Get-ChildItem Env:) {
        if ($envVar.Name -match $combinedRegex) {
            $dockerArgs += '-e'
            $dockerArgs += $envVar.Name
        }
    }

    # Pass host path so the container can link conversation history for /resume
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_HOST_PATH=$HostPath"

    return $dockerArgs
}
