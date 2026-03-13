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
Register-ArgumentCompleter -CommandName 'Set-DClaudeProject' -ParameterName 'ImageKey' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $images = Get-DClaudeImage
    if (-not $images) { return }

    try {
        $platform = (Test-DockerAvailable).ToLower()
        $images = @($images | Where-Object { $_.Platform -eq $platform })
    }
    catch {
        # Docker not available — complete with all image names
    }

    $images | Select-Object -ExpandProperty Name -Unique |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}
