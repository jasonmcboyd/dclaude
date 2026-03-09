$claudeDir = "$env:USERPROFILE\.claude"
$claudeJson = "$env:USERPROFILE\.claude.json"
$claudeJsonInDir = "$claudeDir\.claude.json"

# Copy .claude.json from the mounted .claude directory to the home directory,
# sanitizing it for the container environment (same approach as entrypoint.sh).
if ((Test-Path $claudeJsonInDir) -and -not (Test-Path $claudeJson)) {
    $cfg = Get-Content $claudeJsonInDir -Raw | ConvertFrom-Json

    # Remove host-specific Windows paths that don't apply in the container
    $cfg.PSObject.Properties.Remove('projects')
    $cfg.PSObject.Properties.Remove('githubRepoPaths')

    # Prevent the marketplace extension install prompt
    $cfg | Add-Member -MemberType NoteProperty -Name 'officialMarketplaceAutoInstallAttempted' -Value $true -Force
    $cfg | Add-Member -MemberType NoteProperty -Name 'officialMarketplaceAutoInstalled' -Value $true -Force

    # Pre-accept trust for the container workspace so Claude doesn't prompt every run
    $cfg | Add-Member -MemberType NoteProperty -Name 'projects' -Value ([PSCustomObject]@{
        'C:/workspace' = [PSCustomObject]@{
            allowedTools = @()
            hasTrustDialogAccepted = $true
        }
    }) -Force

    $cfg | ConvertTo-Json -Depth 10 | Set-Content $claudeJson -Encoding UTF8
}

# Link host conversation history so /resume finds conversations from the host.
# Container workspace is C:/workspace → key "C--workspace". Windows containers
# cannot create junctions inside bind mounts, so we copy host sessions into the
# container key dir. New container sessions persist via the bind mount and are
# merged back into the host project dir on subsequent runs.
$hostPath = $env:DCLAUDE_HOST_PATH
$projectsDir = "$claudeDir\projects"
if ($hostPath -and (Test-Path $projectsDir)) {
    $hostKey = $hostPath -replace '[/\\:]', '-'
    $hostProjectDir = "$projectsDir\$hostKey"
    $containerKey = 'C--workspace'
    $containerProjectDir = "$projectsDir\$containerKey"

    # Ensure the host project directory exists
    if (-not (Test-Path $hostProjectDir)) {
        New-Item -ItemType Directory -Path $hostProjectDir -Force | Out-Null
    }

    # Merge any orphaned container sessions into the host project dir
    if (Test-Path $containerProjectDir) {
        Get-ChildItem $containerProjectDir -File | ForEach-Object {
            if (-not (Test-Path "$hostProjectDir\$($_.Name)")) {
                Move-Item $_.FullName $hostProjectDir
            }
        }
    }
    else {
        New-Item -ItemType Directory -Path $containerProjectDir -Force | Out-Null
    }

    # Copy host sessions into the container key dir so /resume can find them
    Get-ChildItem $hostProjectDir -File | ForEach-Object {
        if (-not (Test-Path "$containerProjectDir\$($_.Name)")) {
            Copy-Item $_.FullName $containerProjectDir
        }
    }
}

& C:\nodejs\claude.cmd --dangerously-skip-permissions @args
