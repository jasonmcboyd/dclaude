function Get-ContainerUserProfile {
    <#
    .SYNOPSIS
        Probes a Windows container image for its default user's profile directory.
    .DESCRIPTION
        Replaces the hardcoded 'C:/Users/ContainerAdministrator' assumption (which is silently
        wrong for images whose default user differs). Runs `cmd /c echo %USERPROFILE%` in the
        image and returns the result with forward slashes (the convention used for container
        mount targets). Falls back to ContainerAdministrator with a warning if the probe fails,
        so a probe failure never makes things worse than the old hardcode.

        Linux containers don't need this — the claude user is created by the entrypoint at a
        fixed home — so this is Windows-only.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Image
    )

    $fallback = 'C:/Users/ContainerAdministrator'

    $out = docker run --rm --entrypoint cmd $Image /c 'echo %USERPROFILE%' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) {
        Write-Warning "Could not probe %USERPROFILE% for image '$Image'; using $fallback."
        return $fallback
    }

    $profilePath = "$(@($out)[0])".Trim()
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        Write-Warning "Empty %USERPROFILE% from image '$Image'; using $fallback."
        return $fallback
    }
    return ($profilePath -replace '\\', '/')
}
