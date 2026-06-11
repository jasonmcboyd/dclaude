function Test-DClaudeSettingsSchema {
    <#
    .SYNOPSIS
        Validates the structure of a parsed dclaude settings object.
    .DESCRIPTION
        Performs read-only schema validation on a PSCustomObject parsed from a
        dclaude settings JSON file. Returns an array of human-readable error
        strings describing any structural problems found. An empty array
        indicates the config is valid.
    .PARAMETER Config
        The parsed settings object to validate.
    .PARAMETER Label
        A descriptive label (e.g. file path or config source) included in
        error messages to help the user locate the problem.
    .OUTPUTS
        System.String[]  Zero or more validation error messages.
    .EXAMPLE
        $errors = Test-DClaudeSettingsSchema -Config $cfg -Label 'user (~/.dclaude/settings.json)'
        foreach ($e in $errors) { Write-Warning $e }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $errors = @()

    # Validate images property
    if ($Config.PSObject.Properties['images']) {
        if ($Config.images -isnot [PSCustomObject]) {
            $errors += "$Label`: 'images' must be an object, got $($Config.images.GetType().Name)"
        }
        else {
            foreach ($imageProp in $Config.images.PSObject.Properties) {
                $imageName = $imageProp.Name
                $imageEntry = $imageProp.Value
                if ($imageEntry -isnot [PSCustomObject]) {
                    $errors += "$Label`: images.'$imageName' must be an object"
                    continue
                }
                foreach ($platProp in $imageEntry.PSObject.Properties) {
                    $platName = $platProp.Name
                    $platEntry = $platProp.Value
                    if ($platEntry -isnot [PSCustomObject]) {
                        $errors += "$Label`: images.'$imageName'.'$platName' must be an object"
                        continue
                    }
                    if (-not $platEntry.PSObject.Properties['tag'] -or [string]::IsNullOrWhiteSpace($platEntry.tag)) {
                        $errors += "$Label`: images.'$imageName'.'$platName' is missing required 'tag' property"
                    }
                    if ($platEntry.PSObject.Properties['volumes'] -and $platEntry.volumes -isnot [array]) {
                        $errors += "$Label`: images.'$imageName'.'$platName'.volumes must be an array"
                    }
                    if ($platEntry.PSObject.Properties['env'] -and $platEntry.env -isnot [PSCustomObject]) {
                        $errors += "$Label`: images.'$imageName'.'$platName'.env must be an object"
                    }
                }
            }
        }
    }

    # Validate top-level defaultImageKey
    if ($Config.PSObject.Properties['defaultImageKey'] -and $Config.defaultImageKey -isnot [string]) {
        $errors += "$Label`: 'defaultImageKey' must be a string"
    }

    # Deprecated: top-level image and imageKey (replaced by defaultImageKey)
    if ($Config.PSObject.Properties['image'] -and $Config.image -isnot [string]) {
        $errors += "$Label`: 'image' must be a string"
    }
    if ($Config.PSObject.Properties['imageKey'] -and $Config.imageKey -isnot [string]) {
        $errors += "$Label`: 'imageKey' must be a string"
    }

    # Validate top-level volumes ({windows:[...], linux:[...]} object)
    if ($Config.PSObject.Properties['volumes']) {
        $v = $Config.volumes
        if ($v -is [PSCustomObject]) {
            foreach ($platProp in $v.PSObject.Properties) {
                if ($platProp.Name -notin @('windows', 'linux')) {
                    $errors += "$Label`: volumes key '$($platProp.Name)' is not valid; expected 'windows' or 'linux'"
                }
                elseif ($platProp.Value -isnot [array]) {
                    $errors += "$Label`: volumes.'$($platProp.Name)' must be an array"
                }
            }
        }
        else {
            $errors += "$Label`: 'volumes' must be an object with 'windows'/'linux' keys"
        }
    }

    # Deprecated: commonVolumes (renamed to volumes)
    if ($Config.PSObject.Properties['commonVolumes']) {
        $cv = $Config.commonVolumes
        if ($cv -is [array]) {
            # flat array form — valid
        }
        elseif ($cv -is [PSCustomObject]) {
            foreach ($platProp in $cv.PSObject.Properties) {
                if ($platProp.Name -notin @('windows', 'linux')) {
                    $errors += "$Label`: commonVolumes key '$($platProp.Name)' is not valid; expected 'windows' or 'linux'"
                }
                elseif ($platProp.Value -isnot [array]) {
                    $errors += "$Label`: commonVolumes.'$($platProp.Name)' must be an array"
                }
            }
        }
        else {
            $errors += "$Label`: 'commonVolumes' must be an array or an object with 'windows'/'linux' keys"
        }
    }

    # Validate top-level envPassthrough
    if ($Config.PSObject.Properties['envPassthrough'] -and $Config.envPassthrough -isnot [array]) {
        $errors += "$Label`: 'envPassthrough' must be an array"
    }

    , $errors
}
