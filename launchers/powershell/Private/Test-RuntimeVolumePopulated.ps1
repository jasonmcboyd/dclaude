function Test-RuntimeVolumePopulated {
    <#
    .SYNOPSIS
        Tests whether a runtime volume has been populated with the Node.js runtime.
    .DESCRIPTION
        Mounts the volume read-only-ish into a stock image and checks for the node
        binary. Used to decide whether a volume is usable (selection) or still needs
        provisioning. Windows uses servercore (not nanoserver) for the same reason
        provisioning does: nanoserver's restrictive ACLs on first mount break later writes.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'linux')]
        [string]$ContainerOS,

        [Parameter(Mandatory)]
        [string]$VolumeName
    )

    # When the Go entrypoint is enabled the volume must also carry the entrypoint binary,
    # otherwise an older or partial volume would be treated as usable. The default (flag off)
    # path is unchanged.
    $goEnabled = Test-GoEntrypointEnabled

    if ($ContainerOS -eq 'linux') {
        if ($goEnabled) {
            docker run --rm -v "${VolumeName}:/check" $script:DClaudeImages.ProvisionLinux sh -c 'test -f /check/node/bin/node && test -x /check/bin/dclaude-entrypoint' 2>$null
        }
        else {
            docker run --rm -v "${VolumeName}:/check" $script:DClaudeImages.ProvisionLinux test -f /check/node/bin/node 2>$null
        }
    }
    else {
        $check = if ($goEnabled) {
            'if exist C:\check\node\node.exe (if exist C:\check\bin\dclaude-entrypoint.exe (exit 0) else (exit 1)) else (exit 1)'
        } else {
            'if exist C:\check\node\node.exe (exit 0) else (exit 1)'
        }
        docker run --rm -v "${VolumeName}:C:\check" $script:DClaudeImages.ProvisionWindows cmd /c $check 2>$null
    }

    return $LASTEXITCODE -eq 0
}
