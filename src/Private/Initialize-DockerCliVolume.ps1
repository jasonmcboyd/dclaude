function Initialize-DockerCliVolume {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS
    )

    $dockerVersion = $script:DClaudeVersions.DockerCLI
    $composeVersion = $script:DClaudeVersions.DockerCompose
    $buildxVersion = $script:DClaudeVersions.DockerBuildX
    $checkLinux = $script:DClaudeImages.CheckLinux
    $checkWindows = $script:DClaudeImages.CheckWindows
    $provisionWindows = $script:DClaudeImages.ProvisionWindows

    $volumeName = "dclaude-docker-cli-$ContainerOS"
    $mountPath = if ($ContainerOS -eq 'linux') { '/opt/docker-cli' } else { 'C:/docker-cli' }

    # Check for the actual binary, not just the volume — Docker auto-creates
    # empty volumes on first mount, so volume existence doesn't mean populated.
    if ($ContainerOS -eq 'linux') {
        $volumePopulated = docker run --rm -v "${volumeName}:/check" $checkLinux test -f /check/docker 2>$null
        $volumePopulated = ($LASTEXITCODE -eq 0)
    }
    else {
        $volumePopulated = docker run --rm -v "${volumeName}:C:\check" $checkWindows cmd /c "if exist C:\check\docker.exe (exit 0) else (exit 1)" 2>$null
        $volumePopulated = ($LASTEXITCODE -eq 0)
    }

    if (-not $volumePopulated) {
        Write-Host "[dclaude] Provisioning Docker CLI volume ($volumeName)..." -ForegroundColor DarkGray
        if ($ContainerOS -eq 'linux') {
            $script = ('apk add --no-cache curl >/dev/null 2>&1 && ARCH=$(uname -m) && case "$ARCH" in x86_64) GOARCH=amd64;; aarch64) GOARCH=arm64;; *) GOARCH=$ARCH;; esac && curl -fsSL "https://download.docker.com/linux/static/stable/${ARCH}/docker-__DOCKER__.tgz" | tar -xz --strip-components=1 -C /out docker/docker && mkdir -p /out/cli-plugins && curl -fsSL -o /out/cli-plugins/docker-compose "https://github.com/docker/compose/releases/download/v__COMPOSE__/docker-compose-linux-${ARCH}" && chmod +x /out/cli-plugins/docker-compose && curl -fsSL -o /out/cli-plugins/docker-buildx "https://github.com/docker/buildx/releases/download/v__BUILDX__/buildx-v__BUILDX__-linux-${GOARCH}" && chmod +x /out/cli-plugins/docker-buildx').Replace('__DOCKER__', $dockerVersion).Replace('__COMPOSE__', $composeVersion).Replace('__BUILDX__', $buildxVersion)
            docker run --rm -v "${volumeName}:/out" "${checkLinux}:latest" sh -c $script
        }
        else {
            $script = ('curl -sLo docker.zip https://download.docker.com/win/static/stable/x86_64/docker-__DOCKER__.zip && tar -xf docker.zip --strip-components=1 -C C:\out docker/docker.exe && del docker.zip && mkdir C:\out\cli-plugins && curl -sLo C:\out\cli-plugins\docker-compose.exe https://github.com/docker/compose/releases/download/v__COMPOSE__/docker-compose-windows-x86_64.exe && curl -sLo C:\out\cli-plugins\docker-buildx.exe https://github.com/docker/buildx/releases/download/v__BUILDX__/buildx-v__BUILDX__-windows-amd64.exe').Replace('__DOCKER__', $dockerVersion).Replace('__COMPOSE__', $composeVersion).Replace('__BUILDX__', $buildxVersion)
            docker run --rm -v "${volumeName}:C:\out" $provisionWindows cmd /c $script
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to provision Docker CLI volume. Check network connectivity."
            return
        }
    }

    return [PSCustomObject]@{
        VolumeName = $volumeName
        MountPath  = $mountPath
    }
}
