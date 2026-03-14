function Get-DockerContainerOS {
    [CmdletBinding()]
    param()

    # Check that docker command exists
    if (-not (Get-Command 'docker' -ErrorAction SilentlyContinue)) {
        Write-Error 'Docker is not installed. Install Docker from https://docs.docker.com/get-docker/'
        return
    }

    # Check that Docker daemon is running and get OS type
    $osType = docker info --format '{{.OSType}}' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Docker is not running. Start Docker Desktop and try again.'
        return
    }

    $osType = "$osType".Trim()
    if ([string]::IsNullOrWhiteSpace($osType)) {
        Write-Error "Unable to determine Docker OS type from 'docker info' output. Ensure Docker is running correctly."
        return
    }

    return $osType
}
