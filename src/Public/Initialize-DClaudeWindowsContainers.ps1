function Initialize-DClaudeWindowsContainers {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ClaudeConfigPath = (Join-Path $HOME '.claude')
    )

    $claudeJsonPath = Join-Path (Split-Path $ClaudeConfigPath) '.claude.json'
    $claudeJsonInDir = Join-Path $ClaudeConfigPath '.claude.json'

    if (-not (Test-Path $claudeJsonPath)) {
        Write-Host ".claude.json not found at '$claudeJsonPath'. Nothing to do."
        return
    }

    $item = Get-Item $claudeJsonPath
    if ($item.Target) {
        Write-Host ".claude.json is already a symlink pointing to '$($item.Target)'. Nothing to do."
        return
    }

    if (-not (Test-Path $ClaudeConfigPath)) {
        New-Item -ItemType Directory -Path $ClaudeConfigPath -Force | Out-Null
    }

    try {
        Copy-Item -Path $claudeJsonPath -Destination $claudeJsonInDir -Force
        New-Item -ItemType SymbolicLink -Path $claudeJsonPath -Target $claudeJsonInDir -Force -ErrorAction Stop | Out-Null
        Write-Host "Copied .claude.json into '$ClaudeConfigPath' and created symlink at '$claudeJsonPath'."
    }
    catch {
        # Roll back: remove the copy if the symlink failed
        if (Test-Path $claudeJsonInDir) {
            Remove-Item -Path $claudeJsonInDir -Force
        }
        Write-Error "Failed to create symlink: $_"
    }
}
