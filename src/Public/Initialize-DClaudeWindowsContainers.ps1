<#
.SYNOPSIS
    One-time setup to enable .claude.json persistence in Windows containers.

.DESCRIPTION
    Windows containers cannot bind-mount individual files, only directories.
    This command moves ~/.claude.json into the ~/.claude/ directory and replaces
    the original with a symbolic link. This allows the file to travel through
    the directory mount into the container while remaining transparent to the
    host Claude Code installation. Only needs to be run once per system.

.PARAMETER ClaudeConfigPath
    Path to the Claude configuration directory. Defaults to ~/.claude.

.EXAMPLE
    Initialize-DClaudeWindowsContainers

    Sets up the .claude.json symlink using the default Claude config path.
#>
function Initialize-DClaudeWindowsContainers {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$ClaudeConfigPath = (Join-Path $HOME '.claude')
    )

    $claudeJsonPath = Join-Path (Split-Path $ClaudeConfigPath) '.claude.json'
    $claudeJsonInDir = Join-Path $ClaudeConfigPath '.claude.json'

    if (-not (Test-Path $claudeJsonPath)) {
        Write-Verbose ".claude.json not found at '$claudeJsonPath'. Nothing to do."
        return
    }

    $item = Get-Item -Force $claudeJsonPath
    if ($item.Target) {
        Write-Verbose ".claude.json is already a symlink pointing to '$($item.Target)'. Nothing to do."
        return
    }

    if (-not (Test-Path $ClaudeConfigPath)) {
        New-Item -ItemType Directory -Path $ClaudeConfigPath -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($claudeJsonPath, 'Move into .claude directory and replace with symlink')) {
        try {
            Copy-Item -Path $claudeJsonPath -Destination $claudeJsonInDir -Force
            New-Item -ItemType SymbolicLink -Path $claudeJsonPath -Target $claudeJsonInDir -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Copied .claude.json into '$ClaudeConfigPath' and created symlink at '$claudeJsonPath'."
        }
        catch {
            # Roll back: remove the copy if the symlink failed
            if (Test-Path $claudeJsonInDir) {
                Remove-Item -Path $claudeJsonInDir -Force
            }
            Write-Error "Failed to create symlink: $_"
        }
    }
}
