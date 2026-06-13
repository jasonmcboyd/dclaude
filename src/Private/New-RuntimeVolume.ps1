function New-RuntimeVolume {
    <#
    .SYNOPSIS
        Provisions a runtime volume (Node.js + Claude Code, plus MinGit on Windows)
        into a named Docker volume.
    .DESCRIPTION
        Runs a stock provisioning image with the given volume mounted read-write and
        populates it with the dclaude runtime. The caller supplies the exact volume name;
        this function never selects or computes names. When -ClaudeCodeVersion is given,
        that specific version of @anthropic-ai/claude-code is installed, otherwise latest.

        This is the single source of truth for provisioning — both Initialize-RuntimeVolume
        (lazy first-run provisioning) and Update-DClaudeRuntime call it.

        Returns $true on success, $false on failure (the caller decides how to report).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter(Mandatory)]
        [string]$VolumeName,

        [Parameter()]
        [string]$ClaudeCodeVersion
    )

    $nodeVersion = $script:DClaudeVersions.NodeJS
    $claudePackage = if ($ClaudeCodeVersion) {
        "@anthropic-ai/claude-code@$ClaudeCodeVersion"
    } else {
        '@anthropic-ai/claude-code'
    }

    Write-Host "[dclaude] Provisioning runtime volume ($VolumeName)..." -ForegroundColor DarkGray

    if ($ContainerOS -eq 'linux') {
        $provisionImage = $script:DClaudeImages.ProvisionLinux
        $script = ('set -e && apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && ARCH=$(uname -m) && case "$ARCH" in x86_64) NODE_ARCH=x64;; aarch64) NODE_ARCH=arm64;; armv7l) NODE_ARCH=armv7l;; *) echo "Unsupported: $ARCH" && exit 1;; esac && mkdir -p /out/node && curl -fsSL "https://nodejs.org/dist/v__NODE__/node-v__NODE__-linux-${NODE_ARCH}.tar.gz" | tar -xz --strip-components=1 -C /out/node && export PATH="/out/node/bin:$PATH" && npm install -g __CLAUDE__ --prefix /out/node && apt-get install -y -qq git >/dev/null 2>&1 && mkdir -p /out/git/bin /out/git/libexec && cp -a /usr/bin/git* /out/git/bin/ && cp -a /usr/lib/git-core /out/git/libexec/').Replace('__NODE__', $nodeVersion).Replace('__CLAUDE__', $claudePackage)
        Write-Verbose "dclaude: provisioning image: $provisionImage"
        Write-Verbose "dclaude: provisioning script: $script"
        docker run --rm -v "${VolumeName}:/out" $provisionImage sh -c $script | Out-Host
    }
    else {
        # Use servercore (not nanoserver) for provisioning so the volume is created and
        # written by the same container identity used for the populated-check. Nanoserver
        # sets restrictive ACLs on the volume backing directory when it first mounts it,
        # which then prevents servercore from writing during provisioning ("Access is denied.").
        $provisionImage = $script:DClaudeImages.ProvisionWindows
        $minGitVersion = $script:DClaudeVersions.MinGit
        $minGitTag = "v$minGitVersion"
        $minGitFile = "MinGit-$($minGitVersion.Replace('.windows.', '.'))-64-bit.zip"
        $script = ('cd C:\out && curl -sLo node.zip https://nodejs.org/dist/v__NODE__/node-v__NODE__-win-x64.zip && tar -xf node.zip && ren node-v__NODE__-win-x64 node && del node.zip && curl -sLo mingit.zip https://github.com/git-for-windows/git/releases/download/__MINGIT_TAG__/__MINGIT_FILE__ && mkdir mingit && tar -xf mingit.zip -C mingit && del mingit.zip && set PATH=C:\out\node;%PATH% && C:\out\node\npm install -g __CLAUDE__ --prefix C:\out\node && icacls C:\out /grant Everyone:(OI)(CI)F /t /q').Replace('__NODE__', $nodeVersion).Replace('__MINGIT_TAG__', $minGitTag).Replace('__MINGIT_FILE__', $minGitFile).Replace('__CLAUDE__', $claudePackage)
        Write-Verbose "dclaude: provisioning image: $provisionImage"
        Write-Verbose "dclaude: provisioning script: $script"
        docker run --rm -v "${VolumeName}:C:\out" $provisionImage cmd /c $script | Out-Host
    }

    if ($LASTEXITCODE -eq 0) { return $true }

    # On Windows, Docker's --rm cleanup can fail to detach the container VHD
    # (windowsfilter driver issue) and return non-zero even when the provisioning
    # script itself succeeded. Verify the volume is actually populated before failing.
    if ($ContainerOS -eq 'windows') {
        docker run --rm -v "${VolumeName}:C:\check" $script:DClaudeImages.ProvisionWindows cmd /c "if exist C:\check\node\node.exe (exit 0) else (exit 1)" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Verbose 'dclaude: provisioning exit code was non-zero (Docker --rm VHD cleanup issue) but volume is populated — continuing'
            return $true
        }
    }

    return $false
}
