function Set-DClaudeProject {
    [CmdletBinding(DefaultParameterSetName = 'ByImageKey', SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName = 'ByImageKey', Mandatory)]
        [ValidateSet([DClaudeImageKeyCompleter])]
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
