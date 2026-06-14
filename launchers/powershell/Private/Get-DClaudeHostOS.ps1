function Get-DClaudeHostOS {
    <#
    .SYNOPSIS
        Returns the host operating system: 'windows', 'linux', or 'macos'.
    .DESCRIPTION
        The launcher branches on the *container* OS (from docker info) almost everywhere; this
        is the one place it needs the *host* OS. It is the seam for scenario-3 behavior (Linux
        containers on a Linux host), which the Go entrypoint keys off via DCLAUDE_HOST_OS.

        Windows PowerShell 5.1 has no $IsWindows/$IsLinux/$IsMacOS automatic variables and only
        runs on Windows, so their absence implies Windows.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path variable:IsWindows)) { return 'windows' }
    if ($IsWindows) { return 'windows' }
    if ($IsLinux) { return 'linux' }
    if ($IsMacOS) { return 'macos' }
    return 'unknown'
}
