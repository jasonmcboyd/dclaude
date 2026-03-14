param(
    [Parameter(Mandatory, ParameterSetName = 'ByName')]
    [ValidateSet('pwsh', 'dotnet-core', 'dotnet-framework')]
    [string]$Name,

    [Parameter(Mandatory, ParameterSetName = 'All')]
    [switch]$All
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Detect Docker's current container OS mode
$osType = docker info --format '{{.OSType}}' 2>$null
if (-not $osType) {
    throw 'Docker is not running or not installed.'
}
$Platform = if ($osType -eq 'windows') { 'Windows' } else { 'Linux' }
Write-Host "Detected Docker mode: $Platform"

$imageMap = @{
    'pwsh'             = @{
        'Windows' = @{
            BaseImage = 'mcr.microsoft.com/powershell:lts-windowsservercore-ltsc2022'
            Tag       = 'dclaude-pwsh:latest'
        }
        'Linux'   = @{
            BaseImage = 'mcr.microsoft.com/powershell:lts'
            Tag       = 'dclaude-pwsh-linux:latest'
        }
    }
    'dotnet-core'      = @{
        'Windows' = @{
            BaseImage = 'mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2022'
            Tag       = 'dclaude-dotnet-core:latest'
        }
        'Linux'   = @{
            BaseImage = 'mcr.microsoft.com/dotnet/sdk:10.0'
            Tag       = 'dclaude-dotnet-core-linux:latest'
        }
    }
    'dotnet-framework' = @{
        'Windows' = @{
            BaseImage = 'mcr.microsoft.com/dotnet/framework/sdk:4.8.1-windowsservercore-ltsc2022'
            Tag       = 'dclaude-dotnet-framework:latest'
        }
    }
}

$names = if ($All) {
    $imageMap.Keys | Where-Object { $imageMap[$_].ContainsKey($Platform) }
}
else {
    if (-not $imageMap[$Name].ContainsKey($Platform)) {
        $available = $imageMap[$Name].Keys -join ', '
        throw "'$Name' is not available for $Platform. Available platforms: $available"
    }
    @($Name)
}

$dockerfile = if ($Platform -eq 'Linux') { 'Dockerfile.linux' } else { 'Dockerfile' }
$imagesDir = Join-Path $PSScriptRoot '..\Images'
$dockerfilePath = Join-Path $imagesDir $dockerfile

foreach ($n in $names) {
    $image = $imageMap[$n][$Platform]
    Write-Host "Building $($image.Tag) from $($image.BaseImage) ($Platform)..."
    docker build --build-arg "BASE_IMAGE=$($image.BaseImage)" -t $image.Tag -f $dockerfilePath $imagesDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build '$n' ($Platform)."
    }
}
