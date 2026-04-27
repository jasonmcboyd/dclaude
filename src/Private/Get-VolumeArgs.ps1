function Get-VolumeArgs {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$ImageVolumes = @(),

        [Parameter()]
        [string[]]$ProjectVolumes = @(),

        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS
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

    # Expand environment variables, translate container-side paths for the
    # target OS, and apply default read-only mode.
    $expandedVolumes = foreach ($vol in $allVolumes) {
        $expanded = [Environment]::ExpandEnvironmentVariables($vol)

        # Parse volume spec into host:container[:mode].
        # Windows paths contain drive-letter colons (e.g. C:\foo:C:\bar:rw),
        # so we match optional drive letters on each side.
        if ($expanded -match '^([A-Za-z]:)?([^:]+):([A-Za-z]:)?([^:]+)(?::(ro|rw))?$') {
            $hostPath = "$($Matches[1])$($Matches[2])"
            $containerPath = "$($Matches[3])$($Matches[4])"
            $mode = $Matches[5]
            $containerPath = ConvertTo-ContainerPath -HostPath $containerPath -ContainerOS $ContainerOS
            $result = "${hostPath}:${containerPath}"
            if ($mode) { $result += ":$mode" }
            Set-VolumeDefaultMode $result
        }
        else {
            Set-VolumeDefaultMode $expanded
        }
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
