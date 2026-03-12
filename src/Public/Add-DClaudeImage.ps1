function Add-DClaudeImage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Tag,

        [Parameter()]
        [string[]]$Volumes,

        [Parameter()]
        [ValidateSet('Windows', 'Linux')]
        [string]$Platform,

        [Parameter()]
        [switch]$Force
    )

    $directory = Join-Path $HOME '.dclaude'
    $config = Read-SettingsFile -Directory $directory

    if (-not $config) {
        $config = [PSCustomObject]@{ images = [PSCustomObject]@{} }
    }

    if (-not $config.PSObject.Properties['images'] -or -not $config.images) {
        $config | Add-Member -MemberType NoteProperty -Name 'images' -Value ([PSCustomObject]@{}) -Force
    }

    # Create image entry if it doesn't exist
    if (-not $config.images.PSObject.Properties[$Name]) {
        $config.images | Add-Member -MemberType NoteProperty -Name $Name -Value ([PSCustomObject]@{})
    }

    if (-not $Platform) {
        $osType = Test-DockerAvailable
        if (-not $osType) { return }
        $Platform = if ($osType -eq 'windows') { 'Windows' } else { 'Linux' }
        Write-Verbose "Inferred platform '$Platform' from Docker"
    }

    $platformKey = $Platform.ToLower()

    # Check if platform already exists for this entry
    if ($config.images.$Name.PSObject.Properties[$platformKey] -and -not $Force) {
        Write-Error "Image '$Name' already has a '$platformKey' platform entry. Use -Force to overwrite or Remove-DClaudeImage to remove it first."
        return
    }

    $platformEntry = [PSCustomObject]@{ tag = $Tag }
    if ($Volumes -and $Volumes.Count -gt 0) {
        $platformEntry | Add-Member -MemberType NoteProperty -Name 'volumes' -Value @($Volumes)
    }

    if ($PSCmdlet.ShouldProcess("Image '$Name' ($platformKey)", 'Add')) {
        $config.images.$Name | Add-Member -MemberType NoteProperty -Name $platformKey -Value $platformEntry -Force
        Save-SettingsFile -Directory $directory -Config $config
    }
}
