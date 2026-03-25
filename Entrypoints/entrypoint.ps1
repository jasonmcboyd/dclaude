$ErrorActionPreference = 'Stop'

try {

# --- Runtime volume PATH setup ---
$runtimePath = if ($env:DCLAUDE_RUNTIME) { $env:DCLAUDE_RUNTIME } else { 'C:\dclaude-runtime' }
$env:PATH = "$runtimePath\node;$runtimePath\mingit\cmd;$env:PATH"

# Ensure truecolor support for CLI tools (stock images may not set this)
if (-not $env:COLORTERM) { $env:COLORTERM = 'truecolor' }

# Ensure .claude directory exists
$claudeDir = "$env:USERPROFILE\.claude"
New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

$hostDir = 'C:\mnt\host-claude'
$claudeJson = "$env:USERPROFILE\.claude.json"

# Workspace path: use host-path mount if provided, fall back to legacy C:\workspace
$Workspace = if ($env:DCLAUDE_WORKSPACE) { $env:DCLAUDE_WORKSPACE } else { 'C:\workspace' }

# Trust the workspace directory to avoid "dubious ownership" errors from git.
# This runs here instead of the Dockerfile because the workspace path is dynamic.
if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global --add safe.directory ($Workspace -replace '\\', '/')
}
else {
    Write-Host "[dclaude] WARN: git is not installed in this image. Some Claude Code features may not work." -ForegroundColor Yellow
}

# Selectively link from the host .claude directory.
# Symlink dirs and files so writes (e.g. OAuth token refresh) persist to host.
if (Test-Path $hostDir) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

    # Symlink directories — writes go straight to host.
    # Note: unlike the Linux entrypoint, we do NOT skip 'plugins' or 'session-env'
    # because Windows containers share the same OS and path structure as the host.
    # Skip 'projects' — handled below to avoid duplicate session entries in /resume.
    # Skip 'rules' — handled below so we can inject a container context file.
    Get-ChildItem $hostDir -Directory | ForEach-Object {
        if ($_.Name -eq 'projects') { return }
        if ($_.Name -eq 'rules') { return }
        $target = "$claudeDir\$($_.Name)"
        if (-not (Test-Path $target)) {
            New-Item -ItemType SymbolicLink -Path $target -Target $_.FullName -Force | Out-Null
        }
    }

    # Symlink top-level files so writes (e.g. OAuth token refresh) persist to host.
    Get-ChildItem $hostDir -File | ForEach-Object {
        $target = "$claudeDir\$($_.Name)"
        New-Item -ItemType SymbolicLink -Path $target -Target $_.FullName -Force | Out-Null
    }
}

# Create rules directory as a real dir (not symlink) so we can add container
# context without it reaching the host. Symlink individual host rules files in.
$containerRulesDir = "$claudeDir\rules"
New-Item -ItemType Directory -Path $containerRulesDir -Force | Out-Null
$hostRulesDir = "$hostDir\rules"
if (Test-Path $hostRulesDir) {
    Get-ChildItem $hostRulesDir -File | ForEach-Object {
        New-Item -ItemType SymbolicLink -Path "$containerRulesDir\$($_.Name)" -Target $_.FullName -Force | Out-Null
    }
}

# Generate container context rules file so Claude knows it's in a container.
$hostPath = $env:DCLAUDE_HOST_PATH
$contextLines = @(
    '# Container Environment (dclaude)'
    ''
    'You are running inside a dclaude Docker container.'
    ''
    '## Key Facts'
    "- The workspace at ``$Workspace`` is mounted from the host path ``$hostPath``."
    "- The container image is ``$($env:DCLAUDE_IMAGE ?? 'unknown')``."
    '- Your home directory and .claude config are container-local, with select items symlinked to the host for persistence.'
    '- Paths referenced in CLAUDE.md or other instructions (e.g., project directories, repo paths) may refer to host-only locations that are not mounted in this container.'
    ''
    '## When a Path Does Not Exist'
    ''
    'If a path mentioned in instructions or config does not exist in the container:'
    ''
    '1. Do NOT search for it or attempt workarounds.'
    '2. Inform the user that the path is not available because it was not mounted into the container.'
    '3. Suggest they add a volume mount in their dclaude project or image configuration if they need access.'
    ''
    '## Available Mounts'
    ''
    "| Host Path | Container Path | Mode |"
    "| --- | --- | --- |"
    "| ``$hostPath`` | ``$Workspace`` | read/write |"
)

$volumes = $env:DCLAUDE_VOLUMES
if ($volumes) {
    foreach ($vol in ($volumes -split '\|')) {
        # Parse volume spec: host:container[:mode]
        # Use regex to detect and strip trailing :ro or :rw (same approach as entrypoint.sh)
        if ($vol -match ':(ro|rw)$') {
            $volMode = $Matches[1]
            $volNoMode = $vol -replace ':(ro|rw)$', ''
        }
        else {
            $volMode = 'ro'
            $volNoMode = $vol
        }
        # Split on the last colon to get host and container paths.
        # This handles Windows drive letters (e.g. C:/host:C:/container) correctly.
        if ($volNoMode -match '^(.+):([^:]+)$') {
            $volHost = $Matches[1]
            $volContainer = $Matches[2]
        }
        else {
            $volHost = $volNoMode
            $volContainer = $volNoMode
        }
        $modeLabel = if ($volMode -eq 'rw') { 'read/write' } else { 'read-only' }
        $contextLines += "| ``$volHost`` | ``$volContainer`` | $modeLabel |"
    }
}

# Append Docker access context if the named pipe is mounted
if (Test-Path '//./pipe/docker_engine') {
    $contextLines += ''
    $contextLines += '## Docker Access'
    $contextLines += ''
    $contextLines += 'The Docker named pipe is mounted into this container. You have access to the `docker` CLI and can build images, run containers, and manage Docker resources on the host. The containers you launch are **sibling containers** (not nested) — they run alongside this container on the same Docker daemon.'
}

# Append environment variables passed from the host
$envList = $env:DCLAUDE_ENV
if ($envList) {
    $contextLines += ''
    $contextLines += '## Environment Variables'
    $contextLines += ''
    $contextLines += 'The following environment variables were passed through from the host:'
    $contextLines += ''
    foreach ($varName in ($envList -split '\|')) {
        if ($varName) {
            $contextLines += "- ``$varName``"
        }
    }
}

$contextLines -join "`n" | Set-Content "$containerRulesDir\dclaude-context.md" -Encoding UTF8

# Sanitize .claude.json — strip Windows paths and pre-accept container workspace
$claudeJsonInDir = "$claudeDir\.claude.json"
if ((Test-Path $claudeJsonInDir) -and -not (Test-Path $claudeJson)) {
    try {
        $cfg = Get-Content $claudeJsonInDir -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "[dclaude] Failed to parse .claude.json: $_"
        exit 1
    }

    $cfg.PSObject.Properties.Remove('projects')
    $cfg.PSObject.Properties.Remove('githubRepoPaths')

    $cfg | Add-Member -MemberType NoteProperty -Name 'officialMarketplaceAutoInstallAttempted' -Value $true -Force
    $cfg | Add-Member -MemberType NoteProperty -Name 'officialMarketplaceAutoInstalled' -Value $true -Force

    # Pre-accept the workspace path (use forward slashes for consistency with Claude Code)
    $workspaceKey = $Workspace -replace '\\', '/'
    $cfg | Add-Member -MemberType NoteProperty -Name 'projects' -Value ([PSCustomObject]@{
        $workspaceKey = [PSCustomObject]@{
            allowedTools = @()
            hasTrustDialogAccepted = $true
        }
    }) -Force

    $cfg | ConvertTo-Json -Depth 10 | Set-Content $claudeJson -Encoding UTF8
}

# Link host conversation history so /resume finds conversations from the host.
# The project dir may already be bind-mounted by Invoke-DClaude (preferred, since
# bind mounts appear as real directories to readdir). Fall back to a symlink if not.
# Derive the container project key from the workspace path
$containerKey = $Workspace -replace '[/\\:]', '-'
$projectTarget = "$claudeDir\projects\$containerKey"
if (Test-Path $projectTarget) {
    # Already bind-mounted by the launcher — nothing to do.
    $sessionCount = @(Get-ChildItem $projectTarget -Filter '*.jsonl' -ErrorAction SilentlyContinue).Count
    Write-Host "[dclaude] Project dir mounted with $sessionCount session(s)" -ForegroundColor DarkGray
}
else {
    $hostProjectsDir = "$hostDir\projects"
    if ($hostPath -and (Test-Path $hostProjectsDir)) {
        $hostKey = $hostPath -replace '[/\\:]', '-'
        $hostProjectDir = "$hostProjectsDir\$hostKey"

        if (-not (Test-Path $hostProjectDir)) {
            New-Item -ItemType Directory -Path $hostProjectDir -Force | Out-Null
        }

        $containerProjectsDir = "$claudeDir\projects"
        New-Item -ItemType Directory -Path $containerProjectsDir -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path "$containerProjectsDir\$containerKey" -Target $hostProjectDir -Force | Out-Null
        $sessionCount = @(Get-ChildItem $hostProjectDir -Filter '*.jsonl' -ErrorAction SilentlyContinue).Count
        Write-Host "[dclaude] Linked $sessionCount session(s) from $hostProjectDir" -ForegroundColor DarkGray
    }
    else {
        Write-Warning "[dclaude] No DCLAUDE_HOST_PATH or no host projects dir (DCLAUDE_HOST_PATH='$hostPath')"
    }
}

}
catch {
    Write-Host "[dclaude] FATAL: Entrypoint failed: $_" -ForegroundColor Red
    exit 1
}

# Link Docker CLI from the provisioned volume (mounted by -DockerAccess),
# but only if the image doesn't already have docker installed.
$dockerCliPath = 'C:\docker-cli'
if (-not (Get-Command docker -ErrorAction SilentlyContinue) -and (Test-Path "$dockerCliPath\docker.exe")) {
    $env:PATH = "$dockerCliPath;$env:PATH"
    # Docker discovers plugins in ~/.docker/cli-plugins/ — symlink them there
    $pluginsSrc = "$dockerCliPath\cli-plugins"
    if (Test-Path $pluginsSrc) {
        $pluginsDst = "$env:USERPROFILE\.docker\cli-plugins"
        New-Item -ItemType Directory -Path $pluginsDst -Force | Out-Null
        Get-ChildItem $pluginsSrc -File | ForEach-Object {
            New-Item -ItemType SymbolicLink -Path "$pluginsDst\$($_.Name)" -Target $_.FullName -Force | Out-Null
        }
    }
}

# Run init scripts (user common → user image → project common → project image)
$initBase = 'C:\mnt\init.d'
foreach ($initDir in @("$initBase\user-common", "$initBase\user-image", "$initBase\project-common", "$initBase\project-image")) {
    if (Test-Path $initDir) {
        Get-ChildItem $initDir -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
            Write-Host "[dclaude] Running init script: $($_.Name)" -ForegroundColor DarkGray
            . $_.FullName
        }
    }
}

# Reset ErrorActionPreference so claude.cmd stderr does not trigger
# a PowerShell terminating error under the script-level 'Stop' preference.
$ErrorActionPreference = 'Continue'
& claude.cmd --dangerously-skip-permissions @args
exit $LASTEXITCODE
