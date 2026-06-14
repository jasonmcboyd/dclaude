$ErrorActionPreference = 'Stop'
if ($env:DCLAUDE_VERBOSE) { $VerbosePreference = 'Continue' }

try {

# --- Runtime volume PATH setup ---
Write-Verbose "[dclaude] Setting up runtime paths..."
$runtimePath = if ($env:DCLAUDE_RUNTIME) { $env:DCLAUDE_RUNTIME } else { 'C:\dclaude-runtime' }
$env:PATH = "$runtimePath\node;$runtimePath\mingit\cmd;$env:PATH"

# Ensure truecolor support for CLI tools (stock images may not set this)
if (-not $env:COLORTERM) { $env:COLORTERM = 'truecolor' }

$claudeDir = "$env:USERPROFILE\.claude"
$claudeJson = "$env:USERPROFILE\.claude.json"

# Workspace path: use host-path mount if provided, fall back to legacy C:\workspace
$Workspace = if ($env:DCLAUDE_WORKSPACE) { $env:DCLAUDE_WORKSPACE } else { 'C:\workspace' }

Write-Verbose "[dclaude] Configuring git safe.directory..."
if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global --add safe.directory ($Workspace -replace '\\', '/')
}
else {
    Write-Host "[dclaude] WARN: git is not installed in this image. Some Claude Code features may not work."
}

Write-Verbose "[dclaude] Sanitizing .claude.json..."
# Sanitize .claude.json — strip Windows paths and pre-accept container workspace,
# but preserve MCP server config from the host project entry.
$claudeJsonInDir = "$claudeDir\.claude.json"
$hostPath = $env:DCLAUDE_HOST_PATH
if ((Test-Path $claudeJsonInDir) -and -not (Test-Path $claudeJson)) {
    try {
        $cfg = Get-Content $claudeJsonInDir -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "[dclaude] Failed to parse .claude.json: $_"
        exit 1
    }

    # Look up host project entry to preserve MCP fields before deleting projects.
    $mcpFields = @('mcpServers', 'mcpContextUris', 'enabledMcpjsonServers', 'disabledMcpjsonServers')
    $preserved = @{}
    if ($cfg.PSObject.Properties['projects'] -and $hostPath) {
        $candidates = @($hostPath, ($hostPath -replace '\\', '/'))
        foreach ($candidate in $candidates) {
            $entry = $cfg.projects.PSObject.Properties[$candidate]
            if ($entry) {
                foreach ($f in $mcpFields) {
                    if ($entry.Value.PSObject.Properties[$f]) {
                        $preserved[$f] = $entry.Value.$f
                    }
                }
                break
            }
        }
    }

    $cfg.PSObject.Properties.Remove('projects')
    $cfg.PSObject.Properties.Remove('githubRepoPaths')
    # Host install descriptors (e.g. 'native' -> ~/.local/bin/claude) are wrong in the
    # container, where claude is the npm install in the runtime volume; stripping them
    # avoids a spurious /doctor 'missing native binary' warning.
    $cfg.PSObject.Properties.Remove('installMethod')
    $cfg.PSObject.Properties.Remove('autoUpdatesProtectedForNative')

    $cfg | Add-Member -MemberType NoteProperty -Name 'officialMarketplaceAutoInstallAttempted' -Value $true -Force
    $cfg | Add-Member -MemberType NoteProperty -Name 'officialMarketplaceAutoInstalled' -Value $true -Force

    # Pre-accept the workspace path (use forward slashes for consistency with Claude Code)
    $workspaceKey = $Workspace -replace '\\', '/'
    $projectEntry = [PSCustomObject]@{
        allowedTools           = @()
        hasTrustDialogAccepted = $true
    }
    foreach ($f in $preserved.Keys) {
        $projectEntry | Add-Member -MemberType NoteProperty -Name $f -Value $preserved[$f]
    }
    $cfg | Add-Member -MemberType NoteProperty -Name 'projects' -Value ([PSCustomObject]@{
        $workspaceKey = $projectEntry
    }) -Force

    $cfg | ConvertTo-Json -Depth 10 | Set-Content $claudeJson -Encoding UTF8
}

Write-Verbose "[dclaude] Checking project session history..."
# The project dir may already be bind-mounted by Invoke-DClaude (preferred, since
# bind mounts appear as real directories to readdir). Fall back to the directory
# that already exists in the direct mount.
$containerKey = $Workspace -replace '[/\\:]', '-'
$projectTarget = "$claudeDir\projects\$containerKey"
if (Test-Path $projectTarget) {
    $sessionCount = @(Get-ChildItem $projectTarget -Filter '*.jsonl' -ErrorAction SilentlyContinue).Count
    Write-Host "[dclaude] Project dir with $sessionCount session(s)"
}
else {
    Write-Warning "[dclaude] No project dir found for key '$containerKey'"
}

}
catch {
    Write-Host "[dclaude] FATAL at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    exit 1
}

# Link Docker CLI from the provisioned volume (mounted by -DockerAccess),
# but only if the image doesn't already have docker installed.
Write-Host "[dclaude] Setting up Docker CLI..."
$dockerCliPath = 'C:\docker-cli'
if (-not (Get-Command docker -ErrorAction SilentlyContinue) -and (Test-Path "$dockerCliPath\docker.exe")) {
    $env:PATH = "$dockerCliPath;$env:PATH"
    # Docker discovers plugins in ~/.docker/cli-plugins/ — symlink them there
    $pluginsSrc = "$dockerCliPath\cli-plugins"
    if (Test-Path $pluginsSrc) {
        $pluginsDst = "$env:USERPROFILE\.docker\cli-plugins"
        New-Item -ItemType Directory -Path $pluginsDst -Force | Out-Null
        Get-ChildItem $pluginsSrc -File | ForEach-Object {
            Write-Host "[dclaude] Linking docker plugin: $($_.Name)"
            New-Item -ItemType SymbolicLink -Path "$pluginsDst\$($_.Name)" -Target $_.FullName -Force | Out-Null
        }
    }
}

# Run init scripts (user common → user image → project common → project image)
Write-Host "[dclaude] Running init scripts..."
$initBase = 'C:\mnt\init.d'
foreach ($initDir in @("$initBase\user-common", "$initBase\user-image", "$initBase\project-common", "$initBase\project-image")) {
    if (Test-Path $initDir) {
        Get-ChildItem $initDir -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
            Write-Host "[dclaude] Running init script: $($_.Name)"
            try {
                . $_.FullName
                Write-Verbose "[dclaude] Init script complete: $($_.Name)"
            }
            catch {
                Write-Warning "[dclaude] Init script '$($_.Name)' failed: $($_.Exception.Message)"
            }
        }
    }
}

Write-Host "[dclaude] Launching claude..."
# Reset ErrorActionPreference so claude.cmd stderr does not trigger
# a PowerShell terminating error under the script-level 'Stop' preference.
$ErrorActionPreference = 'Continue'
& claude.cmd --dangerously-skip-permissions @args
exit $LASTEXITCODE
