<#
.SYNOPSIS
    Removes environment variable passthrough patterns from dclaude settings.

.DESCRIPTION
    Removes one or more patterns from the 'envPassthrough' array in the
    specified dclaude settings file. Errors if a pattern is not found in
    the target file.

.PARAMETER Pattern
    One or more environment variable name patterns to remove.

.PARAMETER Scope
    Target settings file: User, Project, or ProjectLocal.
    Defaults to ProjectLocal.

.EXAMPLE
    Remove-DClaudeEnvPassthrough -Pattern 'NUGET_*'

    Removes the NUGET_* pattern from the project's settings.local.json.
#>
function Remove-DClaudeEnvPassthrough {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$Pattern,

        [Parameter()]
        [ValidateSet('User', 'Project', 'ProjectLocal')]
        [string]$Scope = 'ProjectLocal'
    )

    $resolved = Resolve-SettingsScope -Scope $Scope
    if (-not $resolved) { return }

    $config = Read-SettingsFile -Directory $resolved.Directory -FileName $resolved.FileName
    if (-not $config -or -not $config.PSObject.Properties['envPassthrough'] -or $config.envPassthrough -isnot [array]) {
        Write-Error "No envPassthrough patterns found in $Scope config."
        return
    }

    $existing = [array]$config.envPassthrough
    foreach ($p in $Pattern) {
        if ($p -notin $existing) {
            Write-Error "Pattern '$p' not found in $Scope config envPassthrough."
            return
        }
    }

    if ($PSCmdlet.ShouldProcess("$Scope config", "Remove envPassthrough patterns: $($Pattern -join ', ')")) {
        $newList = @($existing | Where-Object { $_ -notin $Pattern })
        if ($newList.Count -eq 0) {
            $config.PSObject.Properties.Remove('envPassthrough')
        }
        else {
            $config | Add-Member -MemberType NoteProperty -Name 'envPassthrough' -Value @($newList) -Force
        }
        Save-SettingsFile -Directory $resolved.Directory -Config $config -FileName $resolved.FileName
    }
}
