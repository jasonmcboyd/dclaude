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
