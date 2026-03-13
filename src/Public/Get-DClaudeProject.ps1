function Get-DClaudeProject {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $PWD
    )

    $config = Get-DClaudeConfig -Path $Path

    if (-not $config) {
        return
    }

    $result = [PSCustomObject]@{
        ImageKey = if ($config.PSObject.Properties['imageKey']) { $config.imageKey } else { $null }
        Image    = if ($config.PSObject.Properties['image']) { $config.image } else { $null }
        Volumes  = if ($config.PSObject.Properties['volumes']) { @($config.volumes) } else { @() }
    }

    return $result
}
