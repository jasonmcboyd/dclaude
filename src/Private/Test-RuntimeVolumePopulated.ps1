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

    if ($ContainerOS -eq 'linux') {
        docker run --rm -v "${VolumeName}:/check" $script:DClaudeImages.ProvisionLinux test -f /check/node/bin/node 2>$null
    }
    else {
        docker run --rm -v "${VolumeName}:C:\check" $script:DClaudeImages.ProvisionWindows cmd /c "if exist C:\check\node\node.exe (exit 0) else (exit 1)" 2>$null
    }

    return $LASTEXITCODE -eq 0
}
