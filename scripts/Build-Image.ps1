param(
    [Parameter(Mandatory)]
    [ValidateSet('pwsh', 'dotnet-core', 'dotnet-framework')]
    [string]$Name
)

$imageMap = @{
    'pwsh'             = @{
        BaseImage = 'mcr.microsoft.com/powershell:lts-windowsservercore-ltsc2022'
        Tag       = 'dclaude-pwsh:latest'
    }
    'dotnet-core'      = @{
        BaseImage = 'mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2022'
        Tag       = 'dclaude-dotnet-core:latest'
    }
    'dotnet-framework' = @{
        BaseImage = 'mcr.microsoft.com/dotnet/framework/sdk:4.8.1-windowsservercore-ltsc2022'
        Tag       = 'dclaude-dotnet-framework:latest'
    }
}

$image = $imageMap[$Name]
$dockerfilePath = Join-Path $PSScriptRoot '..\Images\Dockerfile'

Write-Host "Building $($image.Tag) from $($image.BaseImage)..."
docker build --build-arg "BASE_IMAGE=$($image.BaseImage)" -t $image.Tag -f $dockerfilePath (Split-Path $dockerfilePath)
