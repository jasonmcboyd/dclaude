function Get-VolumeArgs {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$ImageVolumes = @(),

        [Parameter()]
        [string[]]$ProjectVolumes = @()
    )

    $allVolumes = @()
    if ($ImageVolumes.Count -gt 0) {
        $allVolumes += $ImageVolumes
    }
    if ($ProjectVolumes.Count -gt 0) {
        $allVolumes += $ProjectVolumes
    }

    if ($allVolumes.Count -eq 0) {
        return @()
    }

    $dockerArgs = @()

    # Expand environment variables and apply default read-only mode once
    $expandedVolumes = foreach ($vol in $allVolumes) {
        $expanded = [Environment]::ExpandEnvironmentVariables($vol)
        Set-VolumeDefaultMode $expanded
    }

    # Mount each volume
    foreach ($vol in $expandedVolumes) {
        $dockerArgs += '-v'
        $dockerArgs += $vol
    }

    # Pass volume descriptions so the container context file can list them
    $dockerArgs += '-e'
    $dockerArgs += "DCLAUDE_VOLUMES=$($expandedVolumes -join '|')"

    return $dockerArgs
}
