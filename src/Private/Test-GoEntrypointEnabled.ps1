function Test-GoEntrypointEnabled {
    <#
    .SYNOPSIS
        Reports whether the experimental Go container entrypoint is enabled.
    .DESCRIPTION
        Gated on the DCLAUDE_USE_GO_ENTRYPOINT environment variable during the entrypoint
        rework (roadmap phases 1-5). While disabled (the default), provisioning, the
        populated-check, and the launcher behave exactly as before: the runtime volume gets
        only Node.js + Claude Code and the shell entrypoints are used. When enabled, the Go
        entrypoint binary is also provisioned into the volume and the launcher invokes it.

        Truthy values: any non-empty value other than '0', 'false', or 'no' (case-insensitive).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $value = $env:DCLAUDE_USE_GO_ENTRYPOINT
    return -not [string]::IsNullOrWhiteSpace($value) -and $value -notin @('0', 'false', 'no', 'off')
}
