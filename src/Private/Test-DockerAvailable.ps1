function Test-DockerAvailable {
    [CmdletBinding()]
    param()

    # Check that docker command exists
    if (-not (Get-Command 'docker' -ErrorAction SilentlyContinue)) {
        throw 'Docker is not installed. Install Docker from https://docs.docker.com/get-docker/'
    }

    # Check that Docker daemon is running
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker is not running. Start Docker Desktop and try again.'
    }

    # Detect container OS type
    $osTypeMatch = $dockerInfo | Select-String -Pattern '^\s*OSType:\s*(.+)$'

    if (-not $osTypeMatch) {
        throw "Unable to determine Docker OS type from 'docker info' output. Ensure Docker is running correctly."
    }

    $osType = $osTypeMatch.Matches | ForEach-Object { $_.Groups[1].Value.Trim() }

    return $osType
}
