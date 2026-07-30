function Set-VolumeDefaultMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VolumeSpec
    )

    # Append :ro if the volume spec does not already include a mode.
    # The regex accounts for Windows drive letters (e.g. C:/host:C:/container).
    if ($VolumeSpec -notmatch ':(ro|rw)$') {
        return "${VolumeSpec}:ro"
    }
    return $VolumeSpec
}
