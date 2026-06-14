function Write-LaunchSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImageTag,

        [Parameter()]
        [string]$ImageName,

        [Parameter(Mandatory)]
        [string[]]$DockerArgs
    )

    # The image is default-visible status; the detailed mount + env breakdown is verbose
    # (inspect it with -Verbose) so normal output stays clean.
    if ($ImageName) {
        Write-Host "[dclaude] Image: $ImageName ($ImageTag)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "[dclaude] Image: $ImageTag" -ForegroundColor DarkGray
    }

    Write-Verbose "[dclaude] Mounting volumes:"
    for ($i = 0; $i -lt $DockerArgs.Count; $i++) {
        if ($DockerArgs[$i] -eq '-v' -and ($i + 1) -lt $DockerArgs.Count) {
            Write-Verbose "  $($DockerArgs[$i + 1])"
        }
    }

    $envVars = @()
    for ($i = 0; $i -lt $DockerArgs.Count; $i++) {
        if ($DockerArgs[$i] -eq '-e' -and ($i + 1) -lt $DockerArgs.Count) {
            $envVars += $DockerArgs[$i + 1]
        }
    }
    if ($envVars.Count -gt 0) {
        Write-Verbose "[dclaude] Environment variables:"
        foreach ($envVar in $envVars) {
            Write-Verbose "  $envVar"
        }
    }
}
