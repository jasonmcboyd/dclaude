function Get-VolumeArgs {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$UserVolumes = @(),

        [Parameter()]
        [string[]]$ImageVolumes = @(),

        [Parameter()]
        [string[]]$ProjectVolumes = @(),

        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS
    )

    $allVolumes = @()
    $volumeTiers = @()
    if ($UserVolumes.Count -gt 0) {
        $allVolumes += $UserVolumes
        $volumeTiers += @('user') * $UserVolumes.Count
    }
    if ($ImageVolumes.Count -gt 0) {
        $allVolumes += $ImageVolumes
        $volumeTiers += @('image') * $ImageVolumes.Count
    }
    if ($ProjectVolumes.Count -gt 0) {
        $allVolumes += $ProjectVolumes
        $volumeTiers += @('project') * $ProjectVolumes.Count
    }

    if ($allVolumes.Count -eq 0) {
        return @()
    }

    foreach ($vi in 0..($allVolumes.Count - 1)) {
        Write-Debug "[volumes] $($volumeTiers[$vi]): $($allVolumes[$vi])"
    }

    # Dedup by container path: later entries (higher priority) win.
    # Priority order: user < image < project (project is last in $allVolumes).
    $seenPaths = @{}
    $dedupedVolumes = @()
    for ($i = 0; $i -lt $allVolumes.Count; $i++) {
        $cp = Get-VolumeContainerPath $allVolumes[$i]
        if ($cp) {
            if ($seenPaths.ContainsKey($cp)) {
                $prevIdx = $seenPaths[$cp]
                Write-Verbose "Volume '$($allVolumes[$prevIdx])' overridden by '$($allVolumes[$i])' (same container path '$cp')"
                Write-Debug "[volumes] Conflict on $cp`: $($volumeTiers[$i]) '$($allVolumes[$i])' overrides $($volumeTiers[$prevIdx]) '$($allVolumes[$prevIdx])'"
                $dedupedVolumes[$prevIdx] = $null
            }
            $seenPaths[$cp] = $i
        }
        $dedupedVolumes += $allVolumes[$i]
    }
    $allVolumes = @($dedupedVolumes | Where-Object { $_ -ne $null })

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
