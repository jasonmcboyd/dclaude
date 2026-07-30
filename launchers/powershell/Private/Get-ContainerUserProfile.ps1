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

    # The probe runs the image, which pulls it if it isn't local yet. For Windows base images
    # that can be several GB and take many minutes, so pull it explicitly with visible progress
    # first -- otherwise the suppressed pull below looks like an indefinite hang.
    docker image inspect $Image *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[dclaude] Pulling $Image (first use; Windows base images can be several GB)..." -ForegroundColor DarkGray
        docker pull $Image | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not pull '$Image' to probe its user profile; using $fallback."
            return $fallback
        }
    }

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
