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

    if ($ImageName) {
        Write-Host "[dclaude] Image: $ImageName ($ImageTag)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "[dclaude] Image: $ImageTag" -ForegroundColor DarkGray
    }

    Write-Host "[dclaude] Mounting volumes:" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $DockerArgs.Count; $i++) {
        if ($DockerArgs[$i] -eq '-v' -and ($i + 1) -lt $DockerArgs.Count) {
            Write-Host "  $($DockerArgs[$i + 1])" -ForegroundColor DarkGray
        }
    }

    $envVars = @()
    for ($i = 0; $i -lt $DockerArgs.Count; $i++) {
        if ($DockerArgs[$i] -eq '-e' -and ($i + 1) -lt $DockerArgs.Count) {
            $envVars += $DockerArgs[$i + 1]
        }
    }
    if ($envVars.Count -gt 0) {
        Write-Host "[dclaude] Environment variables:" -ForegroundColor DarkGray
        foreach ($envVar in $envVars) {
            Write-Host "  $envVar" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
}
