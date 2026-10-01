function Resolve-SettingsScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('User', 'Project', 'ProjectLocal')]
        [string]$Scope,

        [Parameter()]
        [string]$Path = $PWD,

        [switch]$ForWrite
    )

    if ($Scope -eq 'User') {
        return [PSCustomObject]@{
            Directory = Join-Path $HOME '.dclaude'
            FileName  = 'settings.json'
        }
    }

    $startPath = (Resolve-Path -Path $Path).Path
    $fileName = if ($Scope -eq 'ProjectLocal') { 'settings.local.json' } else { 'settings.json' }

    # Walk up the directory tree looking for a .dclaude folder
    $current = $startPath
    while ($current) {
        $configDir = Join-Path $current '.dclaude'
        if (Test-Path -Path $configDir -PathType Container) {
            $foundInAncestor = $current -ne $startPath

            if ($ForWrite -and $foundInAncestor) {
                $localDir = Join-Path $startPath '.dclaude'
                $choices = @(
                    [System.Management.Automation.Host.ChoiceDescription]::new(
                        '&Nearest',
                        "Update $configDir\$fileName"
                    )
                    [System.Management.Automation.Host.ChoiceDescription]::new(
                        'Create &local',
                        "Create $localDir and write to $localDir\$fileName"
                    )
                    [System.Management.Automation.Host.ChoiceDescription]::new(
                        '&Cancel',
                        'Do nothing'
                    )
                )
                $decision = $Host.UI.PromptForChoice(
                    'No .dclaude in current directory',
                    "Found .dclaude in ancestor: $configDir",
                    $choices,
                    0
                )

                switch ($decision) {
                    0 { <# use the ancestor — fall through #> }
                    1 {
                        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
                        return [PSCustomObject]@{
                            Directory = $localDir
                            FileName  = $fileName
                        }
                    }
                    default {
                        return $null
                    }
                }
            }

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
