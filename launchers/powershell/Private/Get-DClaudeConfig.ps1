function Get-DClaudeConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $PWD
    )

    # Walk up the directory tree looking for a .dclaude folder
    $current = (Resolve-Path -Path $Path).Path
    while ($current) {
        $configDir = Join-Path $current '.dclaude'
        if (Test-Path -Path $configDir -PathType Container) {
            return Merge-SettingsFiles -Directory $configDir -Label 'project config'
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) {
            # Reached the filesystem root
            break
        }
        $current = $parent
    }

    return $null
}
