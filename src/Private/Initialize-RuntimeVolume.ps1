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
        # Use servercore for both check and provision so the volume is always created
        # and written by the same container identity. Nanoserver sets restrictive ACLs
        # on the volume backing directory when it first mounts it, which then prevents
        # servercore from writing during provisioning ("Access is denied.").
        $volumePopulated = docker run --rm -v "${volumeName}:C:\check" mcr.microsoft.com/windows/servercore:ltsc2022 cmd /c "if exist C:\check\node\node.exe (exit 0) else (exit 1)" 2>$null
        $volumePopulated = ($LASTEXITCODE -eq 0)
    }

    if (-not $volumePopulated) {
        Write-Host "dclaude: provisioning runtime volume ($volumeName)..." -ForegroundColor DarkGray
        if ($ContainerOS -eq 'linux') {
            $provisionImage = 'debian:bookworm-slim'
            $script = 'set -e && apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && ARCH=$(uname -m) && case "$ARCH" in x86_64) NODE_ARCH=x64;; aarch64) NODE_ARCH=arm64;; armv7l) NODE_ARCH=armv7l;; *) echo "Unsupported: $ARCH" && exit 1;; esac && mkdir -p /out/node && curl -fsSL "https://nodejs.org/dist/v22.14.0/node-v22.14.0-linux-${NODE_ARCH}.tar.gz" | tar -xz --strip-components=1 -C /out/node && export PATH="/out/node/bin:$PATH" && npm install -g @anthropic-ai/claude-code --prefix /out/node && apt-get install -y -qq git >/dev/null 2>&1 && mkdir -p /out/git/bin /out/git/libexec && cp -a /usr/bin/git* /out/git/bin/ && cp -a /usr/lib/git-core /out/git/libexec/'
            Write-Verbose "dclaude: provisioning image: $provisionImage"
            Write-Verbose "dclaude: provisioning script: $script"
            docker run --rm -v "${volumeName}:/out" $provisionImage sh -c $script | Out-Host
        }
        else {
            $provisionImage = 'mcr.microsoft.com/windows/servercore:ltsc2022'
            $script = @'
cd C:\out && curl -sLo node.zip https://nodejs.org/dist/v22.14.0/node-v22.14.0-win-x64.zip && tar -xf node.zip && ren node-v22.14.0-win-x64 node && del node.zip && curl -sLo mingit.zip https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/MinGit-2.47.1.2-64-bit.zip && mkdir mingit && tar -xf mingit.zip -C mingit && del mingit.zip && set PATH=C:\out\node;%PATH% && C:\out\node\npm install -g @anthropic-ai/claude-code --prefix C:\out\node
'@
            Write-Verbose "dclaude: provisioning image: $provisionImage"
            Write-Verbose "dclaude: provisioning script: $script"
            docker run --rm -v "${volumeName}:C:\out" $provisionImage cmd /c $script | Out-Host
        }
        if ($LASTEXITCODE -ne 0) {
            # On Windows, Docker's --rm cleanup can fail to detach the container VHD
            # (windowsfilter driver issue) and return non-zero even when the provisioning
            # script itself succeeded. Verify the volume is actually populated before failing.
            if ($ContainerOS -eq 'windows') {
                $verifyImage = 'mcr.microsoft.com/windows/servercore:ltsc2022'
                $verifyPopulated = docker run --rm -v "${volumeName}:C:\check" $verifyImage cmd /c "if exist C:\check\node\node.exe (exit 0) else (exit 1)" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Verbose "dclaude: provisioning exit code was non-zero (Docker --rm VHD cleanup issue) but volume is populated — continuing"
                }
                else {
                    Write-Error "Failed to provision runtime volume. Check network connectivity."
                    return
                }
            }
            else {
                Write-Error "Failed to provision runtime volume. Check network connectivity."
                return
            }
        }
    }

    return [PSCustomObject]@{
        VolumeName = $volumeName
        MountPath  = $mountPath
    }
}
