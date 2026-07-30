function Get-DClaudeConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $PWD
    )

    # Walk up the directory tree collecting ALL .dclaude configs (closest first)
    $configs = @()
    $configDirs = @()
    $current = (Resolve-Path -Path $Path).Path
    while ($current) {
        $configDir = Join-Path $current '.dclaude'
        if (Test-Path -Path $configDir -PathType Container) {
            Write-Debug "[config] Walking: $current — found .dclaude"
            $cfg = Merge-SettingsFiles -Directory $configDir -Label "project config ($configDir)"
            if ($cfg) {
                $configs += $cfg
                $configDirs += $configDir
            }
        }
        else {
            Write-Debug "[config] Walking: $current — no .dclaude"
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }

    if ($configs.Count -eq 0) {
        Write-Debug '[config] No project configs found'
        return $null
    }
    if ($configs.Count -eq 1) {
        Write-Debug "[config] Single project config from $($configDirs[0])"
        return $configs[0]
    }

    # Compose: closest config wins for scalars; arrays merge additively
    Write-Debug "[config] Composing $($configs.Count) project configs (closest first):"
    for ($ci = 0; $ci -lt $configDirs.Count; $ci++) {
        Write-Debug "[config]   [$($ci + 1)] $($configDirs[$ci])"
    }

    $result = $configs[0]
    for ($i = 1; $i -lt $configs.Count; $i++) {
        $farther = $configs[$i]
        $fartherLabel = "[$($i + 1)]"
        foreach ($prop in $farther.PSObject.Properties) {
            $name = $prop.Name
            $hasAlready = $result.PSObject.Properties[$name]

            if ($name -eq 'envPassthrough') {
                $existing = @(if ($hasAlready) { $result.$name } else { @() })
                $incoming = @($prop.Value)
                Write-Debug "[config] envPassthrough: merged $($incoming -join ', ') from $fartherLabel"
                $result | Add-Member -MemberType NoteProperty -Name $name -Value ($existing + $incoming) -Force
            }
            elseif ($name -eq 'volumes') {
                if (-not $hasAlready) {
                    Write-Debug "[config] volumes: inherited from $fartherLabel"
                    $result | Add-Member -MemberType NoteProperty -Name $name -Value $prop.Value -Force
                }
                else {
                    foreach ($platform in $prop.Value.PSObject.Properties) {
                        $pk = $platform.Name
                        if ($result.$name.PSObject.Properties[$pk]) {
                            $existing = @($result.$name.$pk)
                            $existingSpecs = [System.Collections.Generic.HashSet[string]]::new(
                                [string[]]$existing, [System.StringComparer]::OrdinalIgnoreCase)
                            $existingPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                            foreach ($spec in $existing) {
                                $cp = Get-VolumeContainerPath $spec
                                if ($cp) { [void]$existingPaths.Add($cp) }
                            }
                            $accepted = @()
                            foreach ($spec in @($platform.Value)) {
                                if ($existingSpecs.Contains($spec)) {
                                    Write-Debug "[config] volumes.$pk`: skipped duplicate '$spec' from $fartherLabel"
                                    continue
                                }
                                $cp = Get-VolumeContainerPath $spec
                                if ($cp -and $existingPaths.Contains($cp)) {
                                    Write-Verbose "Volume '$spec' skipped: container path '$cp' already mapped by a closer config"
                                    Write-Debug "[config] volumes.$pk`: skipped '$spec' from $fartherLabel (container path '$cp' conflict)"
                                    continue
                                }
                                Write-Debug "[config] volumes.$pk`: merged '$spec' from $fartherLabel"
                                $accepted += $spec
                                if ($cp) { [void]$existingPaths.Add($cp) }
                            }
                            if ($accepted.Count -gt 0) {
                                $result.$name.$pk = $existing + $accepted
                            }
                        }
                        else {
                            Write-Debug "[config] volumes.$pk`: inherited from $fartherLabel"
                            $result.$name | Add-Member -MemberType NoteProperty -Name $pk -Value @($platform.Value) -Force
                        }
                    }
                }
            }
            elseif (-not $hasAlready) {
                Write-Debug "[config] $name = '$($prop.Value)' inherited from $fartherLabel"
                $result | Add-Member -MemberType NoteProperty -Name $name -Value $prop.Value -Force
            }
            else {
                Write-Debug "[config] $name = '$($result.$name)' from [1] (overrides '$($prop.Value)' from $fartherLabel)"
            }
        }
    }

    return $result
}
