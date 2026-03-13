$hostDir = 'C:\mnt\host-claude'
$claudeDir = "$env:USERPROFILE\.claude"
$claudeJson = "$env:USERPROFILE\.claude.json"

# Selectively link from the host .claude directory.
# Symlink dirs and files so writes (e.g. OAuth token refresh) persist to host.
if (Test-Path $hostDir) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

    # Symlink directories — writes go straight to host.
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
    # Exception: .claude.json is copied (not symlinked) so we can sanitize it
    # without modifying the host file.
    Get-ChildItem $hostDir -File | ForEach-Object {
        if ($_.Name -eq '.claude.json') {
            Copy-Item $_.FullName "$claudeDir\$($_.Name)" -Force
            return
        }
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
    "- The workspace at ``C:\workspace`` is mounted from the host path ``$hostPath``."
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
    "| ``$hostPath`` | ``C:\workspace`` | read/write |"
)

$volumes = $env:DCLAUDE_VOLUMES
if ($volumes) {
    foreach ($vol in ($volumes -split '\|')) {
        $parts = $vol -split ':'
        # Volume format: host:container or host:container:mode
        # On Windows, paths may start with a drive letter (e.g. C:/foo), so we
        # need to handle the colon in drive letters. Split on ':' and recombine.
        if ($parts.Count -ge 4) {
            # e.g. C:/host:C:/container:ro → host=C:/host, container=C:/container, mode=ro
            $volHost = "$($parts[0]):$($parts[1])"
            $volContainer = "$($parts[2]):$($parts[3])"
            $volMode = if ($parts.Count -ge 5) { $parts[4] } else { 'read-only' }
        }
        elseif ($parts.Count -eq 3) {
            # Could be host:container:mode (Linux) or C:/host:container (Windows no mode)
            if ($parts[2] -in @('ro', 'rw')) {
                $volHost = $parts[0]
                $volContainer = $parts[1]
                $volMode = $parts[2]
            }
            else {
                $volHost = "$($parts[0]):$($parts[1])"
                $volContainer = $parts[2]
                $volMode = 'read-only'
            }
        }
        else {
            $volHost = $parts[0]
            $volContainer = $parts[1]
            $volMode = 'read-only'
        }
        $modeLabel = if ($volMode -eq 'rw') { 'read/write' } elseif ($volMode -eq 'ro') { 'read-only' } else { $volMode }
        $contextLines += "| ``$volHost`` | ``$volContainer`` | $modeLabel |"
    }
}

$contextLines -join "`n" | Set-Content "$containerRulesDir\dclaude-context.md" -Encoding UTF8

# Sanitize .claude.json — strip Windows paths and pre-accept container workspace
$claudeJsonInDir = "$claudeDir\.claude.json"
if ((Test-Path $claudeJsonInDir) -and -not (Test-Path $claudeJson)) {
    $cfg = Get-Content $claudeJsonInDir -Raw | ConvertFrom-Json

    $cfg.PSObject.Properties.Remove('projects')
    $cfg.PSObject.Properties.Remove('githubRepoPaths')

    $cfg | Add-Member -MemberType NoteProperty -Name 'officialMarketplaceAutoInstallAttempted' -Value $true -Force
    $cfg | Add-Member -MemberType NoteProperty -Name 'officialMarketplaceAutoInstalled' -Value $true -Force

    $cfg | Add-Member -MemberType NoteProperty -Name 'projects' -Value ([PSCustomObject]@{
        'C:/workspace' = [PSCustomObject]@{
            allowedTools = @()
            hasTrustDialogAccepted = $true
        }
    }) -Force

    $cfg | ConvertTo-Json -Depth 10 | Set-Content $claudeJson -Encoding UTF8
}

# Link host conversation history so /resume finds conversations from the host.
# Symlink the container's project key (C--workspace) to the host project dir
# inside the bind mount. The symlink lives on the local filesystem (not inside
# the bind mount), so reparse points work.
$hostPath = $env:DCLAUDE_HOST_PATH
$hostProjectsDir = "$hostDir\projects"
if ($hostPath -and (Test-Path $hostProjectsDir)) {
    $hostKey = $hostPath -replace '[/\\:]', '-'
    $hostProjectDir = "$hostProjectsDir\$hostKey"

    if (-not (Test-Path $hostProjectDir)) {
        New-Item -ItemType Directory -Path $hostProjectDir -Force | Out-Null
    }

    $containerProjectsDir = "$claudeDir\projects"
    New-Item -ItemType Directory -Path $containerProjectsDir -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path "$containerProjectsDir\C--workspace" -Target $hostProjectDir -Force | Out-Null
}

& C:\nodejs\claude.cmd --dangerously-skip-permissions @args
