function Resolve-DClaudeConfig {
    <#
    .SYNOPSIS
    Resolves the effective dclaude configuration for a directory.

    .DESCRIPTION
    Walks all ancestor directories collecting .dclaude configs, loads the
    user-level config from ~/.dclaude, and composes them with provenance
    tracking. Scalars use closest-wins; envPassthrough and volumes merge
    additively. Displays a formatted summary and returns a structured object.

    .PARAMETER Path
    The directory to resolve configuration for. Defaults to the current directory.

    .EXAMPLE
    Resolve-DClaudeConfig
    Shows the effective config for the current directory.

    .PARAMETER Quiet
    Suppresses the formatted display output. Useful when calling programmatically.

    .EXAMPLE
    $cfg = Resolve-DClaudeConfig -Path C:\repos\myproject
    Captures the effective config object for a specific path.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $PWD,

        [Parameter()]
        [switch]$Quiet
    )

    $resolvedPath = (Resolve-Path -Path $Path).Path

    # Walk ancestors collecting per-directory configs with source labels
    $sources = @()
    $current = $resolvedPath
    $sourceIndex = 1
    while ($current) {
        $configDir = Join-Path $current '.dclaude'
        if (Test-Path -Path $configDir -PathType Container) {
            $cfg = Merge-SettingsFiles -Directory $configDir -Label "project config ($configDir)"
            if ($cfg) {
                $sources += [PSCustomObject]@{
                    Index     = $sourceIndex
                    Directory = $configDir
                    Config    = $cfg
                    IsUser    = $false
                }
                $sourceIndex++
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }

    # Load user config
    $userConfig = Get-DClaudeUserConfig
    if ($userConfig) {
        $userDir = Join-Path $HOME '.dclaude'
        $sources += [PSCustomObject]@{
            Index     = $sourceIndex
            Directory = "$userDir (user)"
            Config    = $userConfig
            IsUser    = $true
        }
    }

    if ($sources.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host "No dclaude configuration found for $resolvedPath"
        }
        return $null
    }

    # Compose with source tracking
    $effectiveImageKey = $null
    $imageKeyProvenance = @()
    $envEntries = @()
    $volumeEntries = @{ linux = @(); windows = @() }
    $otherScalars = [ordered]@{}

    foreach ($src in $sources) {
        $cfg = $src.Config
        $label = "[$($src.Index)] $($src.Directory)"

        foreach ($prop in $cfg.PSObject.Properties) {
            $name = $prop.Name

            if ($name -eq 'defaultImageKey' -or $name -eq 'imageKey') {
                if ($name -eq 'imageKey') {
                    Write-Warning "Config at $($src.Directory) uses deprecated 'imageKey'. Rename to 'defaultImageKey'."
                }
                $imageKeyProvenance += [PSCustomObject]@{
                    Value     = $prop.Value
                    Source    = $src.Directory
                    Label     = $label
                    Effective = (-not $effectiveImageKey)
                }
                if (-not $effectiveImageKey) {
                    $effectiveImageKey = $prop.Value
                }
            }
            elseif ($name -eq 'envPassthrough') {
                foreach ($pattern in @($prop.Value)) {
                    $envEntries += [PSCustomObject]@{
                        Pattern = $pattern
                        Source  = $src.Directory
                        Label   = $label
                    }
                }
            }
            elseif ($name -eq 'volumes' -or $name -eq 'commonVolumes') {
                if ($name -eq 'commonVolumes') {
                    Write-Warning "Config at $($src.Directory) uses deprecated 'commonVolumes'. Rename to 'volumes'."
                }
                if ($prop.Value -is [PSCustomObject]) {
                    foreach ($platform in @('linux', 'windows')) {
                        if ($prop.Value.PSObject.Properties[$platform]) {
                            foreach ($spec in @($prop.Value.$platform)) {
                                $volumeEntries[$platform] += [PSCustomObject]@{
                                    Spec   = $spec
                                    Source = $src.Directory
                                    Label  = $label
                                }
                            }
                        }
                    }
                }
            }
            else {
                if (-not $otherScalars.Contains($name)) {
                    $otherScalars[$name] = [PSCustomObject]@{
                        Value  = $prop.Value
                        Source = $src.Directory
                        Label  = $label
                    }
                }
            }
        }
    }

    # Dedup volumes per platform (exact duplicates and container-path conflicts)
    foreach ($platform in @('linux', 'windows')) {
        $entries = $volumeEntries[$platform]
        if ($entries.Count -le 1) { continue }

        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $deduped = @()
        foreach ($e in $entries) {
            if ($seen.Contains($e.Spec)) {
                Write-Verbose "Volume '$($e.Spec)' from $($e.Label) skipped: exact duplicate"
                continue
            }
            $cp = Get-VolumeContainerPath $e.Spec
            if ($cp -and $seenPaths.Contains($cp)) {
                Write-Verbose "Volume '$($e.Spec)' from $($e.Label) skipped: container path '$cp' already mapped by a closer config"
                continue
            }
            [void]$seen.Add($e.Spec)
            if ($cp) { [void]$seenPaths.Add($cp) }
            $deduped += $e
        }
        $volumeEntries[$platform] = $deduped
    }

    # Format display (unless suppressed)
    if (-not $Quiet) {
    Write-Host ""
    Write-Host "Effective dclaude configuration for $resolvedPath"
    Write-Host ""
    Write-Host "Config sources (closest first):"
    foreach ($src in $sources) {
        Write-Host "  [$($src.Index)] $($src.Directory)"
    }

    Write-Host ""
    if ($effectiveImageKey) {
        Write-Host "Default Image Key: $effectiveImageKey"
        foreach ($p in $imageKeyProvenance) {
            if ($p.Effective) {
                Write-Host "  $($p.Label)"
            }
            else {
                Write-Host "  $($p.Label): $($p.Value) (overridden)"
            }
        }
    }
    else {
        Write-Host "Default Image Key: (not set)"
    }

    Write-Host ""
    Write-Host "Env Passthrough:"
    if ($envEntries.Count -eq 0) {
        Write-Host "  (none)"
    }
    else {
        $maxLen = ($envEntries | ForEach-Object { $_.Pattern.Length } | Measure-Object -Maximum).Maximum
        foreach ($e in $envEntries) {
            Write-Host "  $($e.Pattern.PadRight($maxLen))  $($e.Label)"
        }
    }

    foreach ($platform in @('linux', 'windows')) {
        $entries = $volumeEntries[$platform]
        Write-Host ""
        Write-Host "Volumes ($platform):"
        if ($entries.Count -eq 0) {
            Write-Host "  (none)"
        }
        else {
            $maxLen = ($entries | ForEach-Object { $_.Spec.Length } | Measure-Object -Maximum).Maximum
            foreach ($e in $entries) {
                Write-Host "  $($e.Spec.PadRight($maxLen))  $($e.Label)"
            }
        }
    }
    Write-Host ""
    } # end if (-not $Quiet)

    # Build return object with flat effective values + provenance
    $result = [PSCustomObject]@{
        defaultImageKey = $effectiveImageKey
        envPassthrough  = @($envEntries | ForEach-Object { $_.Pattern })
        volumes         = [PSCustomObject]@{
            linux   = @($volumeEntries.linux | ForEach-Object { $_.Spec })
            windows = @($volumeEntries.windows | ForEach-Object { $_.Spec })
        }
        Sources                    = @($sources | ForEach-Object { $_.Directory })
        DefaultImageKeyProvenance  = $imageKeyProvenance
        EnvPassthroughProvenance   = $envEntries
        VolumesProvenance          = [PSCustomObject]@{
            linux   = @($volumeEntries.linux)
            windows = @($volumeEntries.windows)
        }
    }

    # Carry through other scalar properties (e.g. deprecated 'image')
    foreach ($entry in $otherScalars.GetEnumerator()) {
        $result | Add-Member -MemberType NoteProperty -Name $entry.Key -Value $entry.Value.Value
    }

    return $result
}
