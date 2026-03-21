function Resolve-ContainerPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter(Mandatory)]
        [string]$ResolvedPath,

        [Parameter(Mandatory)]
        [string]$ClaudeConfigPath
    )

    $errors = @()
    $dockerArgs = @()

    # Translate the host workspace path for the container's OS (e.g. Windows -> Linux)
    # On same-platform, this is a no-op. On Windows->Linux, converts C:\... to /c/...
    $workspace = ConvertTo-ContainerPath -HostPath $ResolvedPath -ContainerOS $ContainerOS

    # Set Claude config mount path based on OS type
    if ($ContainerOS -eq 'windows') {
        # Mount at a staging path, not directly at ~/.claude, so the entrypoint
        # can create symlinks on the local filesystem pointing into the mount.
        # (Windows containers cannot create reparse points inside bind mounts.)
        $claudeMount = 'C:/mnt/host-claude'
    }
    else {
        $claudeMount = '/mnt/host-claude'
    }

    # Mount Claude config directory
    if (Test-Path $ClaudeConfigPath) {
        $dockerArgs += '-v'
        $dockerArgs += "${ClaudeConfigPath}:${claudeMount}:rw"
    }
    else {
        Write-Warning "Claude config path '$ClaudeConfigPath' not found. Container will start without Claude configuration."
    }

    # Mount .claude.json (lives in home dir, separate from .claude/ directory)
    # Windows containers cannot bind-mount single files. On Windows, run
    # Initialize-DClaudeWindowsContainers to symlink .claude.json into
    # ~/.claude/ so it's carried by the directory mount above.
    $claudeJsonPath = Join-Path (Split-Path $ClaudeConfigPath) '.claude.json'
    if (Test-Path $claudeJsonPath) {
        if ($ContainerOS -eq 'windows') {
            if (-not (Get-Item $claudeJsonPath).Target) {
                $errors += ".claude.json is not symlinked into '$ClaudeConfigPath'. Run Initialize-DClaudeWindowsContainers to fix this."
            }
        }
        else {
            $dockerArgs += '-v'
            $dockerArgs += "${claudeJsonPath}:/mnt/host-claude.json:ro"
        }
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
        if ($ContainerOS -eq 'windows') {
            $containerProjectDir = "C:/Users/ContainerAdministrator/.claude/projects/$containerKey"
        }
        else {
            $containerProjectDir = "/home/claude/.claude/projects/$containerKey"
        }
        $dockerArgs += '-v'
        $dockerArgs += "${hostProjectDir}:${containerProjectDir}"
    }

    return [PSCustomObject]@{
        Workspace  = $workspace
        ClaudeMount = $claudeMount
        DockerArgs = $dockerArgs
        Errors     = $errors
    }
}
