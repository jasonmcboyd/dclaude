function Initialize-RuntimeVolume {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter(Mandatory)]
        [version]$Version
    )

    $volumeName = "dclaude-runtime-$ContainerOS-v$Version"

    if ($ContainerOS -eq 'linux') {
        $mountPath = '/opt/dclaude-runtime'
        $volumePopulated = docker run --rm -v "${volumeName}:/check" debian:bookworm-slim test -f /check/node/bin/node 2>$null
        $volumePopulated = ($LASTEXITCODE -eq 0)
    }
    else {
        $mountPath = 'C:\dclaude-runtime'
        $volumePopulated = docker run --rm -v "${volumeName}:C:\check" mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd /c "if exist C:\check\node\node.exe (exit 0) else (exit 1)" 2>$null
        $volumePopulated = ($LASTEXITCODE -eq 0)
    }

    if (-not $volumePopulated) {
        Write-Host "dclaude: provisioning runtime volume ($volumeName)..." -ForegroundColor DarkGray
        if ($ContainerOS -eq 'linux') {
            $script = 'set -e && apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && ARCH=$(uname -m) && case "$ARCH" in x86_64) NODE_ARCH=x64;; aarch64) NODE_ARCH=arm64;; armv7l) NODE_ARCH=armv7l;; *) echo "Unsupported: $ARCH" && exit 1;; esac && mkdir -p /out/node && curl -fsSL "https://nodejs.org/dist/v22.14.0/node-v22.14.0-linux-${NODE_ARCH}.tar.gz" | tar -xz --strip-components=1 -C /out/node && export PATH="/out/node/bin:$PATH" && npm install -g @anthropic-ai/claude-code --prefix /out/node && apt-get install -y -qq git >/dev/null 2>&1 && mkdir -p /out/git/bin /out/git/libexec && cp -a /usr/bin/git* /out/git/bin/ && cp -a /usr/lib/git-core /out/git/libexec/'
            docker run --rm -v "${volumeName}:/out" debian:bookworm-slim sh -c $script
        }
        else {
            $script = @'
curl -sLo node.zip https://nodejs.org/dist/v22.14.0/node-v22.14.0-win-x64.zip && tar -xf node.zip && move node-v22.14.0-win-x64 C:\out\node && del node.zip && curl -sLo mingit.zip https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/MinGit-2.47.1.2-64-bit.zip && mkdir C:\out\mingit && tar -xf mingit.zip -C C:\out\mingit && del mingit.zip && C:\out\node\npm install -g @anthropic-ai/claude-code --prefix C:\out\node
'@
            docker run --rm -v "${volumeName}:C:\out" mcr.microsoft.com/windows/servercore:ltsc2022 cmd /c $script
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to provision runtime volume. Check network connectivity."
            return
        }
    }

    return [PSCustomObject]@{
        VolumeName = $volumeName
        MountPath  = $mountPath
    }
}
