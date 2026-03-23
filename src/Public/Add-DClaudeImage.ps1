<#
.SYNOPSIS
    Registers a Docker image in the dclaude user configuration.

.DESCRIPTION
    Adds or updates an image entry in ~/.dclaude/settings.json. Each image can
    have platform-specific entries (Windows, Linux) with a tag and optional
    volume mounts. If -Platform is not specified, the current Docker mode is
    auto-detected.

.PARAMETER Name
    Name for the image entry (e.g. 'pwsh', 'dotnet-core').

.PARAMETER Tag
    Docker image tag (e.g. 'dclaude-pwsh:latest').

.PARAMETER Volumes
    Optional volume mount specifications (e.g. 'C:/host:C:/container:ro').

.PARAMETER Platform
    Target platform: Windows or Linux. Auto-detected from Docker if omitted.

.PARAMETER Force
    Overwrite an existing platform entry for this image name.

.EXAMPLE
    Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh:latest'

    Registers the image for the current Docker platform (auto-detected).

.EXAMPLE
    Add-DClaudeImage -Name 'pwsh' -Tag 'dclaude-pwsh-linux:latest' -Platform Linux

    Registers the image explicitly for Linux.
#>
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
        [hashtable]$Env,

        [Parameter()]
        [ValidateSet('Windows', 'Linux')]
        [string]$Platform,

        [Parameter()]
        [switch]$Force
    )

    $directory = Join-Path $HOME '.dclaude'
    $mergedConfig = Get-DClaudeUserConfig
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
        $osType = Get-DockerContainerOS
        if (-not $osType) { return }
        $Platform = if ($osType -eq 'windows') { 'Windows' } else { 'Linux' }
        Write-Verbose "Inferred platform '$Platform' from Docker"
    }

    $platformKey = $Platform.ToLower()

    # Check merged config (base + local override) so local overrides are not silently shadowed
    $existsInMerged = $mergedConfig -and
        $mergedConfig.PSObject.Properties['images'] -and
        $mergedConfig.images -and
        $mergedConfig.images.PSObject.Properties[$Name] -and
        $mergedConfig.images.$Name.PSObject.Properties[$platformKey]
    if ($existsInMerged -and -not $Force) {
        Write-Error "Image '$Name' already has a '$platformKey' platform entry. Use -Force to overwrite or Remove-DClaudeImage to remove it first."
        return
    }

    $platformEntry = [PSCustomObject]@{ tag = $Tag }
    if ($Volumes -and $Volumes.Count -gt 0) {
        $platformEntry | Add-Member -MemberType NoteProperty -Name 'volumes' -Value @($Volumes)
    }
    if ($Env -and $Env.Count -gt 0) {
        $envObject = [PSCustomObject]@{}
        foreach ($key in $Env.Keys) {
            $envObject | Add-Member -MemberType NoteProperty -Name $key -Value $Env[$key]
        }
        $platformEntry | Add-Member -MemberType NoteProperty -Name 'env' -Value $envObject
    }

    if ($PSCmdlet.ShouldProcess("Image '$Name' ($platformKey)", 'Add')) {
        $config.images.$Name | Add-Member -MemberType NoteProperty -Name $platformKey -Value $platformEntry -Force
        Save-SettingsFile -Directory $directory -Config $config
    }
}
