function Get-VolumeContainerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VolumeSpec
    )

    if ($VolumeSpec -match '^([A-Za-z]:)?([^:]+):([A-Za-z]:)?([^:]+)(?::(ro|rw))?$') {
        return "$($Matches[3])$($Matches[4])"
    }

    return $null
}
