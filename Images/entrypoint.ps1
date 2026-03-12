$hostDir = 'C:\mnt\host-claude'
$claudeDir = "$env:USERPROFILE\.claude"
$claudeJson = "$env:USERPROFILE\.claude.json"

# Selectively link/copy from the host .claude directory.
# Symlink large data dirs (zero-cost, writes persist to host).
# Copy small config files (so we can sanitize without affecting host).
if (Test-Path $hostDir) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

    # Symlink directories — writes go straight to host.
    # Skip 'projects' — handled below to avoid duplicate session entries in /resume.
    Get-ChildItem $hostDir -Directory | ForEach-Object {
        if ($_.Name -eq 'projects') { return }
        $target = "$claudeDir\$($_.Name)"
        if (-not (Test-Path $target)) {
            New-Item -ItemType SymbolicLink -Path $target -Target $_.FullName -Force | Out-Null
        }
    }

    # Copy top-level files (small config files)
    Get-ChildItem $hostDir -File | ForEach-Object {
        Copy-Item $_.FullName "$claudeDir\$($_.Name)" -Force
    }
}

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
