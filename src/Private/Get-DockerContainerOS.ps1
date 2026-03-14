function Get-DockerContainerOS {
    [CmdletBinding()]
    param()

    # Check that docker command exists
    if (-not (Get-Command 'docker' -ErrorAction SilentlyContinue)) {
        Write-Error 'Docker is not installed. Install Docker from https://docs.docker.com/get-docker/'
        return
    }

    # Check that Docker daemon is running
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Docker is not running. Start Docker Desktop and try again.'
        return
    }

    # Detect container OS type
    $osTypeMatch = $dockerInfo | Select-String -Pattern '^\s*OSType:\s*(.+)$'

    if (-not $osTypeMatch) {
        Write-Error "Unable to determine Docker OS type from 'docker info' output. Ensure Docker is running correctly."
        return
    }

    $osType = $osTypeMatch.Matches | ForEach-Object { $_.Groups[1].Value.Trim() }

    return $osType
}
