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
    $config = Read-SettingsFile -Directory $directory

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

    if ($PSCmdlet.ShouldProcess("Project config at '$directory'", 'Set')) {
        Save-SettingsFile -Directory $directory -Config $config
    }
}
