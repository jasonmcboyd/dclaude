function Test-DockerAvailable {
    [CmdletBinding()]
    param()

    # Check that docker command exists
    if (-not (Get-Command 'docker' -ErrorAction SilentlyContinue)) {
        throw 'Docker is not installed. Install Docker Desktop from https://docs.docker.com/desktop/setup/install/windows-install/'
    }

    # Check that Docker daemon is running
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker is not running. Start Docker Desktop and try again.'
    }

    # Check that Docker is in Windows container mode
    $osType = ($dockerInfo | Select-String -Pattern '^\s*OSType:\s*(.+)$').Matches |
        ForEach-Object { $_.Groups[1].Value.Trim() }

    if ($osType -ne 'windows') {
        throw "Docker is in Linux container mode. Switch to Windows containers: right-click Docker Desktop tray icon > 'Switch to Windows containers...'"
    }
}
