function ConvertTo-ContainerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostPath,

        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS
    )

    # Windows host path into a Linux container: C:\Users\jason\... -> /c/Users/jason/...
    # This matches the convention Docker Desktop uses for cross-platform mounts.
    if ($ContainerOS -eq 'linux' -and $HostPath -match '^([A-Za-z]):(.*)') {
        $driveLetter = $Matches[1].ToLower()
        $rest = $Matches[2] -replace '\\', '/'
        # Strip trailing slash unless the result would be just the drive root
        $result = "/$driveLetter$rest"
        $result = $result.TrimEnd('/')
        if ($result -eq "/$driveLetter") {
            $result = "/$driveLetter/"
        }
        return $result
    }

    # Same-platform or Linux-to-Linux: return as-is
    return $HostPath
}
