<#
.SYNOPSIS
    Configures the dclaude image and volumes for a project.

.DESCRIPTION
    Writes project-level dclaude settings to .dclaude/settings.local.json in
    the specified directory. This file is intended for machine-specific overrides
    and should not be committed to version control. Use -ImageKey to reference a
    registered image or -Image for a direct Docker tag.

.PARAMETER ImageKey
    Key referencing an image registered in ~/.dclaude/settings.json.

.PARAMETER Image
    Docker image tag to use directly.

.PARAMETER Volumes
    Volume mount specifications for this project. Pass an empty array to clear.

.PARAMETER Path
    Project directory. Defaults to the current directory.

.EXAMPLE
    Set-DClaudeProject -ImageKey 'pwsh'

    Sets the current project to use the 'pwsh' image from user config.

.EXAMPLE
    Set-DClaudeProject -Image 'my-custom:latest' -Volumes 'C:/data:C:/data:rw'

    Sets a direct image tag with a writable volume mount.
#>
function Set-DClaudeProject {
    [CmdletBinding(DefaultParameterSetName = 'ByImageKey', SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName = 'ByImageKey', Mandatory)]
        [string]$ImageKey,

        [Parameter(ParameterSetName = 'ByImage', Mandatory)]
        [string]$Image,

        [Parameter()]
        [string[]]$Volumes,

        [Parameter()]
        [string]$Path = $PWD
    )

    $directory = Join-Path $Path '.dclaude'
    $localPath = Join-Path $directory 'settings.local.json'

    $config = $null
    if (Test-Path $localPath) {
        $content = Get-Content -Path $localPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            try {
                $config = $content | ConvertFrom-Json
            }
            catch {
                throw "Failed to parse settings file '$localPath': $_"
            }
        }
    }

    if (-not $config) {
        $config = [PSCustomObject]@{}
    }

    # Set image or imageKey (clear the other)
    switch ($PSCmdlet.ParameterSetName) {
        'ByImageKey' {
            $config | Add-Member -MemberType NoteProperty -Name 'imageKey' -Value $ImageKey -Force
            if ($config.PSObject.Properties['image']) {
                $config.PSObject.Properties.Remove('image')
            }
        }
        'ByImage' {
            $config | Add-Member -MemberType NoteProperty -Name 'image' -Value $Image -Force
            if ($config.PSObject.Properties['imageKey']) {
                $config.PSObject.Properties.Remove('imageKey')
            }
        }
    }

    # Set or clear volumes
    if ($PSBoundParameters.ContainsKey('Volumes')) {
        if ($Volumes -and $Volumes.Count -gt 0) {
            $config | Add-Member -MemberType NoteProperty -Name 'volumes' -Value @($Volumes) -Force
        }
        elseif ($config.PSObject.Properties['volumes']) {
            $config.PSObject.Properties.Remove('volumes')
        }
    }

    if ($PSCmdlet.ShouldProcess("Project config at '$localPath'", 'Set')) {
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $localPath -Encoding UTF8
    }
}
