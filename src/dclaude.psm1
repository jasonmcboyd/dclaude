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

# Register argument completers
$script:_completerCache = @{ Platform = $null; Timestamp = [datetime]::MinValue }
Register-ArgumentCompleter -CommandName 'Set-DClaudeProject' -ParameterName 'ImageKey' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    try {
        $images = Get-DClaudeImage
        if (-not $images) { return }

        # Cache docker info result for 30 seconds to avoid subprocess on every tab press
        $cache = $script:_completerCache
        $now = [datetime]::UtcNow
        if (($now - $cache.Timestamp).TotalSeconds -gt 30) {
            $cache.Platform = Get-DockerContainerOS
            $cache.Timestamp = $now
        }
        $platform = $cache.Platform
        if ($platform) {
            $images = @($images | Where-Object { $_.Platform -eq $platform.ToLower() })
        }

        $images | Select-Object -ExpandProperty Name -Unique |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }
    catch {
        # Silently return nothing — completers should not produce errors
    }
}
