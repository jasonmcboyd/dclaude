function New-RuntimeVolume {
    <#
    .SYNOPSIS
        Provisions a runtime volume (Node.js + Claude Code, plus MinGit on Windows)
        into a named Docker volume.
    .DESCRIPTION
        Runs a stock provisioning image with the given volume mounted read-write and
        populates it with the dclaude runtime. The caller supplies the exact volume name;
        this function never selects or computes names.

        Version resolution: if -ClaudeCodeVersion is given, that exact version is installed.
        Otherwise the concrete latest version is resolved up front via Get-LatestClaudeCodeVersion.
        When a concrete version is known (either way), the volume is pre-created with a
        'dclaude.cc-version' label recording it, and Claude Code is pinned to that exact
        version so the label always matches reality. If the latest version cannot be resolved
        (e.g. offline), provisioning falls back to installing plain 'latest' with NO label;
        such a volume reads back as having an unknown version.

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

    # Callers always compute a brand-new revision name, so an existing name signals a logic
    # error or a collision from concurrent updates (the user may run many instances at once).
    # Refuse rather than provision over it: `docker volume create` silently no-ops on an
    # existing name and ignores the new label, which would leave the label describing a
    # different version than what actually gets installed.
    docker volume inspect $VolumeName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Error "Runtime volume '$VolumeName' already exists; refusing to provision over it."
        return $false
    }

    $nodeVersion = $script:DClaudeVersions.NodeJS

    # Resolve a concrete version up front so we can both pin the install and stamp it as an
    # immutable volume label (Docker labels can only be set at volume-create time). Fall back
    # to a label-less 'latest' install only when the version genuinely can't be resolved.
    $resolvedVersion = if ($ClaudeCodeVersion) { $ClaudeCodeVersion } else { Get-LatestClaudeCodeVersion }
    $claudePackage = if ($resolvedVersion) {
        "@anthropic-ai/claude-code@$resolvedVersion"
    } else {
        Write-Verbose 'dclaude: latest Claude Code version unresolved — installing plain latest without a version label'
        '@anthropic-ai/claude-code'
    }

    # The runtime volume carries only Node.js + Claude Code (+ MinGit on Windows). The Go
    # entrypoint binary is NOT provisioned here — it ships in the module and is mounted into the
    # container from the host at launch (see Get-DClaudeEntrypointBinary / Invoke-DClaude).

    # Pre-create the volume with the version label when we have a concrete version. Labels are
    # immutable after creation, so this must happen before the provisioning 'docker run'.
    if ($resolvedVersion) {
        docker volume create --label "$script:DClaudeRuntimeVersionLabel=$resolvedVersion" $VolumeName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create runtime volume '$VolumeName'."
            return $false
        }
    }

    Write-Host "[dclaude] Provisioning runtime volume ($VolumeName) — downloading Node.js$(if ($ContainerOS -eq 'windows') { ' + MinGit' }) and installing Claude Code. Runs quietly inside a container; first use can take a few minutes." -ForegroundColor DarkGray

    if ($ContainerOS -eq 'linux') {
        $provisionImage = $script:DClaudeImages.ProvisionLinux
        $script = ('set -e && apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && ARCH=$(uname -m) && case "$ARCH" in x86_64) NODE_ARCH=x64;; aarch64) NODE_ARCH=arm64;; armv7l) NODE_ARCH=armv7l;; *) echo "Unsupported: $ARCH" && exit 1;; esac && echo "[dclaude] Downloading Node.js v__NODE__..." && mkdir -p /out/node && curl -fsSL "https://nodejs.org/dist/v__NODE__/node-v__NODE__-linux-${NODE_ARCH}.tar.gz" | tar -xz --strip-components=1 -C /out/node && export PATH="/out/node/bin:$PATH" && echo "[dclaude] Installing Claude Code..." && npm install -g __CLAUDE__ --prefix /out/node && echo "[dclaude] Bundling git..." && apt-get install -y -qq git >/dev/null 2>&1 && mkdir -p /out/git/bin /out/git/libexec && cp -a /usr/bin/git* /out/git/bin/ && cp -a /usr/lib/git-core /out/git/libexec/').Replace('__NODE__', $nodeVersion).Replace('__CLAUDE__', $claudePackage)
        $runArgs = @('run', '--rm', '-v', "${VolumeName}:/out", $provisionImage, 'sh', '-c', $script)
        Write-Verbose "dclaude: provisioning image: $provisionImage"
        Write-Verbose "dclaude: provisioning script: $script"
        docker @runArgs | Out-Host
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
        $script = ('cd C:\out && echo [dclaude] Downloading Node.js v__NODE__... && curl -sLo node.zip https://nodejs.org/dist/v__NODE__/node-v__NODE__-win-x64.zip && tar -xf node.zip && ren node-v__NODE__-win-x64 node && del node.zip && echo [dclaude] Downloading MinGit... && curl -sLo mingit.zip https://github.com/git-for-windows/git/releases/download/__MINGIT_TAG__/__MINGIT_FILE__ && mkdir mingit && tar -xf mingit.zip -C mingit && del mingit.zip && set PATH=C:\out\node;%PATH% && echo [dclaude] Installing Claude Code... && C:\out\node\npm install -g __CLAUDE__ --prefix C:\out\node && echo [dclaude] Setting permissions... && icacls C:\out /grant Everyone:(OI)(CI)F /t /q').Replace('__NODE__', $nodeVersion).Replace('__MINGIT_TAG__', $minGitTag).Replace('__MINGIT_FILE__', $minGitFile).Replace('__CLAUDE__', $claudePackage)
        $runArgs = @('run', '--rm', '-v', "${VolumeName}:C:\out", $provisionImage, 'cmd', '/c', $script)
        Write-Verbose "dclaude: provisioning image: $provisionImage"
        Write-Verbose "dclaude: provisioning script: $script"
        docker @runArgs | Out-Host
    }

    if ($LASTEXITCODE -eq 0) { return $true }

    # On Windows, Docker's --rm cleanup can fail to detach the container VHD
    # (windowsfilter driver issue) and return non-zero even when the provisioning
    # script itself succeeded. Verify the volume is actually populated before failing.
    if ($ContainerOS -eq 'windows') {
        $verify = 'if exist C:\check\node\node.exe (exit 0) else (exit 1)'
        docker run --rm -v "${VolumeName}:C:\check" $script:DClaudeImages.ProvisionWindows cmd /c $verify 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Verbose 'dclaude: provisioning exit code was non-zero (Docker --rm VHD cleanup issue) but volume is populated — continuing'
            return $true
        }
    }

    # Provisioning genuinely failed — remove the empty/partial volume so it doesn't linger
    # as an orphan (Remove-StaleRuntimeVolumes keeps the highest revision and would not
    # reclaim a stuck empty one at the top of the current version).
    docker volume rm $VolumeName 2>$null | Out-Null

    return $false
}
