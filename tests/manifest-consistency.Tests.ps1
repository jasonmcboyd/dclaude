Describe 'Module manifest consistency' {

    It 'CI manifest exports the same functions as the dev manifest' {
        $devManifest = Import-PowerShellDataFile -Path "$PSScriptRoot/../src/dclaude.psd1"
        $devFunctions = $devManifest.FunctionsToExport | Sort-Object

        # Parse CI script to extract FunctionsToExport list
        $ciContent = Get-Content "$PSScriptRoot/../scripts/create-module-manifest.ps1" -Raw
        $ciMatch = [regex]::Match($ciContent, "FunctionsToExport\s*=\s*@\(([^)]+)\)")
        $ciMatch.Success | Should -BeTrue -Because 'CI script should contain FunctionsToExport'

        $ciFunctions = $ciMatch.Groups[1].Value -split "`n" |
            ForEach-Object { $_.Trim().Trim("'").Trim('"') } |
            Where-Object { $_ -ne '' } |
            Sort-Object

        $ciFunctions | Should -Be $devFunctions
    }

    It 'manifest FunctionsToExport matches files in src/Public/' {
        $devManifest = Import-PowerShellDataFile -Path "$PSScriptRoot/../src/dclaude.psd1"
        $devFunctions = $devManifest.FunctionsToExport | Sort-Object

        $publicFiles = Get-ChildItem "$PSScriptRoot/../src/Public" -Filter '*.ps1' |
            ForEach-Object { $_.BaseName } |
            Sort-Object

        $publicFiles | Should -Be $devFunctions
    }
}
