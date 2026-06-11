function Resolve-SettingsScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('User', 'Project', 'ProjectLocal')]
        [string]$Scope,

        [Parameter()]
        [string]$Path = $PWD
    )

    if ($Scope -eq 'User') {
        return [PSCustomObject]@{
            Directory = Join-Path $HOME '.dclaude'
            FileName  = 'settings.json'
        }
    }

    # Walk up the directory tree looking for a .dclaude folder
    $current = (Resolve-Path -Path $Path).Path
    while ($current) {
        $configDir = Join-Path $current '.dclaude'
        if (Test-Path -Path $configDir -PathType Container) {
            $fileName = if ($Scope -eq 'ProjectLocal') { 'settings.local.json' } else { 'settings.json' }
            return [PSCustomObject]@{
                Directory = $configDir
                FileName  = $fileName
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) {
            break
        }
        $current = $parent
    }

    Write-Error "No .dclaude project directory found. Run from within a project that has a .dclaude/ folder, or use -Scope User."
    return $null
}
