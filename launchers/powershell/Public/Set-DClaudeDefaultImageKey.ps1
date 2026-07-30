<#
.SYNOPSIS
    Sets the default Docker image key for dclaude.

.DESCRIPTION
    Sets the 'defaultImageKey' property in the dclaude settings file for the
    specified scope. The image key must reference an image registered in the
    user config (~/.dclaude/settings.json) via Add-DClaudeImage.

.PARAMETER ImageKey
    Name of a registered image to use as default. Supports tab completion.

.PARAMETER Scope
    Target settings file: User (~/.dclaude/settings.json),
    Project (.dclaude/settings.json), or ProjectLocal (.dclaude/settings.local.json).
    Defaults to ProjectLocal.

.EXAMPLE
    Set-DClaudeDefaultImageKey -ImageKey 'pwsh'

    Sets the default image key to 'pwsh' in the project's settings.local.json.

.EXAMPLE
    Set-DClaudeDefaultImageKey -ImageKey 'dotnet' -Scope User

    Sets the default image key to 'dotnet' in the user config.
#>
function Set-DClaudeDefaultImageKey {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            try {
                $images = Get-DClaudeImage
                if (-not $images) { return }
                $images | Select-Object -ExpandProperty Name -Unique |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                    }
            }
            catch {}
        })]
        [string]$ImageKey,

        [Parameter()]
        [ValidateSet('User', 'Project', 'ProjectLocal')]
        [string]$Scope = 'ProjectLocal'
    )

    $resolved = Resolve-SettingsScope -Scope $Scope
    if (-not $resolved) { return }

    $config = Read-SettingsFile -Directory $resolved.Directory -FileName $resolved.FileName
    if (-not $config) {
        $config = [PSCustomObject]@{}
    }

    if ($PSCmdlet.ShouldProcess("$Scope config", "Set defaultImageKey to '$ImageKey'")) {
        $config | Add-Member -MemberType NoteProperty -Name 'defaultImageKey' -Value $ImageKey -Force
        Save-SettingsFile -Directory $resolved.Directory -Config $config -FileName $resolved.FileName
    }
}
