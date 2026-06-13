function Get-RuntimeVolumeClaudeVersion {
    <#
    .SYNOPSIS
        Reads the Claude Code version baked into a runtime volume from its Docker label.
    .DESCRIPTION
        Returns the value of the '$script:DClaudeRuntimeVersionLabel' label set on the volume
        at creation time by New-RuntimeVolume, or $null if the volume has no such label
        (e.g. a legacy volume provisioned before this feature) or does not exist.

        This reads the label via 'docker volume inspect' — it does NOT start a container,
        so it is fast enough to run on every launch.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$VolumeName
    )

    # 'docker volume inspect' with a Go-template format reads only metadata (no container).
    # For a missing map key, the template renders the literal string '<no value>'.
    $label = $script:DClaudeRuntimeVersionLabel
    $output = docker volume inspect --format "{{index .Labels `"$label`"}}" $VolumeName 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    $value = "$output".Trim()
    if (-not $value -or $value -eq '<no value>') { return $null }

    return $value
}
