# Removes dclaude runtime volumes and reloads the module from source.
# Use this during development to pick up code changes and force volume re-provisioning.

$ErrorActionPreference = 'Stop'

# Remove dclaude runtime volumes
$volumes = docker volume ls --filter 'name=dclaude-runtime-' --format '{{.Name}}' 2>$null
if ($volumes) {
    foreach ($vol in $volumes) {
        Write-Host "Removing volume: $vol" -ForegroundColor DarkGray
        docker volume rm $vol 2>$null | Out-Null
    }
}
else {
    Write-Host "No dclaude runtime volumes found." -ForegroundColor DarkGray
}

# Reload the module from source
Remove-Module -Name dclaude -Force -ErrorAction SilentlyContinue
Import-Module -Name "$PSScriptRoot\..\src\dclaude.psd1" -Force
Write-Host "Module reloaded from source." -ForegroundColor DarkGray
