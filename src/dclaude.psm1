class DClaudeImageKeyCompleter : System.Management.Automation.IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        $images = Get-DClaudeImage
        if (-not $images) { return @() }

        try {
            $platform = (Test-DockerAvailable).ToLower()
            $filtered = @($images | Where-Object { $_.Platform -eq $platform } |
                Select-Object -ExpandProperty Name -Unique)
            if ($filtered.Count -gt 0) { return $filtered }
        }
        catch {
            # Docker not available — fall back to all image names
        }

        return @($images | Select-Object -ExpandProperty Name -Unique)
    }
}

# Dot-source all private functions
$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse | ForEach-Object {
        . $_.FullName
    }
}

# Dot-source all public functions
$publicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse | ForEach-Object {
        . $_.FullName
    }
}

# Export public functions
if (Test-Path $publicPath) {
    $publicFunctions = Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse |
        ForEach-Object { $_.BaseName }
    Export-ModuleMember -Function $publicFunctions
}

# Register aliases
New-Alias -Name 'dclaude' -Value 'Invoke-DClaude' -Force
Export-ModuleMember -Alias 'dclaude'
