function Resolve-ContainerPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter(Mandatory)]
        [string]$ResolvedPath,

        [Parameter(Mandatory)]
        [string]$ClaudeConfigPath,

        # Windows only: the container's default-user profile dir (forward-slash form), from
        # Get-ContainerUserProfile. When omitted, falls back to the ContainerAdministrator
        # profile, preserving the prior hardcoded behavior.
        [Parameter()]
        [string]$ContainerUserProfile
    )

    $errors = @()
    $dockerArgs = @()

    # Translate the host workspace path for the container's OS (e.g. Windows -> Linux)
    # On same-platform, this is a no-op. On Windows->Linux, converts C:\... to /c/...
    $workspace = ConvertTo-ContainerPath -HostPath $ResolvedPath -ContainerOS $ContainerOS

    # Mount ~/.claude directly at the container's ~/.claude so all reads/writes
    # go straight to the host filesystem. No staging path or symlinks needed.
    if ($ContainerOS -eq 'windows') {
        $profileDir = if ($ContainerUserProfile) { $ContainerUserProfile } else { 'C:/Users/ContainerAdministrator' }
        $claudeHome = "$profileDir/.claude"
    }
    else {
        $claudeHome = '/home/claude/.claude'
    }

    if (Test-Path $ClaudeConfigPath) {
        $dockerArgs += '-v'
        $dockerArgs += "${ClaudeConfigPath}:${claudeHome}:rw"
    }
    else {
        Write-Warning "Claude config path '$ClaudeConfigPath' not found. Container will start without Claude configuration."
    }

    # Mount .claude.json (lives in home dir, separate from .claude/ directory).
    # Windows: Initialize-DClaudeWindowsContainers symlinks it into ~/.claude/
    # so it travels with the directory mount above.
    # Linux: mount it inside the directory mount as a nested read-only bind.
    $claudeJsonPath = Join-Path (Split-Path $ClaudeConfigPath) '.claude.json'
    if (Test-Path $claudeJsonPath) {
        if ($ContainerOS -eq 'windows') {
            if (-not (Get-Item $claudeJsonPath).Target) {
                $errors += ".claude.json is not symlinked into '$ClaudeConfigPath'. Run Initialize-DClaudeWindowsContainers to fix this."
            }
        }
        else {
            $dockerArgs += '-v'
            $dockerArgs += "${claudeJsonPath}:${claudeHome}/.claude.json:ro"
        }
    }

    # Mask cross-platform directories in Linux containers (host has Windows-specific content).
    if ($ContainerOS -ne 'windows') {
        $dockerArgs += '--mount'
        $dockerArgs += "type=tmpfs,destination=${claudeHome}/plugins"
        $dockerArgs += '--mount'
        $dockerArgs += "type=tmpfs,destination=${claudeHome}/session-env"
    }

    # Mount the host project directory directly at the container's project path.
    # This must be a bind mount (not a symlink) because Claude Code's multi-worktree
    # resume uses readdir with {withFileTypes: true}, which returns isDirectory()=false
    # for symlinks -- causing symlinked project dirs to be silently skipped.
    $hostKey = $ResolvedPath -replace '[/\\:]', '-'
    $hostProjectDir = Join-Path $ClaudeConfigPath 'projects' $hostKey
    if (Test-Path $hostProjectDir) {
        # The container project key is derived from the container-side workspace path
        $containerKey = $workspace -replace '[/\\:]', '-'
        $containerProjectDir = "$claudeHome/projects/$containerKey"
        $dockerArgs += '-v'
        $dockerArgs += "${hostProjectDir}:${containerProjectDir}"
    }

    return [PSCustomObject]@{
        Workspace  = $workspace
        ClaudeHome = $claudeHome
        DockerArgs = $dockerArgs
        Errors     = $errors
    }
}
