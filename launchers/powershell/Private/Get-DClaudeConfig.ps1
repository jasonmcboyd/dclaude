function Get-DClaudeConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = $PWD
    )

    # Walk up the directory tree collecting ALL .dclaude configs (closest first)
    $configs = @()
    $current = (Resolve-Path -Path $Path).Path
    while ($current) {
        $configDir = Join-Path $current '.dclaude'
        if (Test-Path -Path $configDir -PathType Container) {
            $cfg = Merge-SettingsFiles -Directory $configDir -Label "project config ($configDir)"
            if ($cfg) { $configs += $cfg }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }

    if ($configs.Count -eq 0) { return $null }
    if ($configs.Count -eq 1) { return $configs[0] }

    # Compose: closest config wins for scalars; arrays merge additively
    $result = $configs[0]
    for ($i = 1; $i -lt $configs.Count; $i++) {
        $farther = $configs[$i]
        foreach ($prop in $farther.PSObject.Properties) {
            $name = $prop.Name
            $hasAlready = $result.PSObject.Properties[$name]

            if ($name -eq 'envPassthrough') {
                $existing = @(if ($hasAlready) { $result.$name } else { @() })
                $result | Add-Member -MemberType NoteProperty -Name $name -Value ($existing + @($prop.Value)) -Force
            }
            elseif ($name -eq 'volumes') {
                if (-not $hasAlready) {
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
                                if ($existingSpecs.Contains($spec)) { continue }
                                $cp = Get-VolumeContainerPath $spec
                                if ($cp -and $existingPaths.Contains($cp)) {
                                    Write-Verbose "Volume '$spec' skipped: container path '$cp' already mapped by a closer config"
                                    continue
                                }
                                $accepted += $spec
                                if ($cp) { [void]$existingPaths.Add($cp) }
                            }
                            if ($accepted.Count -gt 0) {
                                $result.$name.$pk = $existing + $accepted
                            }
                        }
                        else {
                            $result.$name | Add-Member -MemberType NoteProperty -Name $pk -Value @($platform.Value) -Force
                        }
                    }
                }
            }
            elseif (-not $hasAlready) {
                $result | Add-Member -MemberType NoteProperty -Name $name -Value $prop.Value -Force
            }
        }
    }

    return $result
}
