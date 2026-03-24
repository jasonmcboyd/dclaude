@{
    # Script module file associated with this manifest
    RootModule        = 'dclaude.psm1'

    # Version number of this module
    ModuleVersion     = '0.16.1'

    # Unique identifier for this module
    GUID              = '3a624731-85ed-4119-ac0b-b31add03fe23'

    # Author of this module
    Author            = 'Jason Boyd'

    # Company or vendor of this module
    CompanyName       = 'Jason Boyd'

    # Copyright statement for this module
    Copyright         = '(c) Jason Boyd. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'Launch Docker containers with Claude Code injected at runtime for isolated development environments.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module
    FunctionsToExport = @(
        'Add-DClaudeImage'
        'Get-DClaudeImage'
        'Get-DClaudeProject'
        'Initialize-DClaudeWindowsContainers'
        'Invoke-DClaude'
        'Remove-DClaudeImage'
        'Set-DClaudeProject'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @('dclaude')

    # Private data to pass to the module specified in RootModule
    PrivateData       = @{
        PSData = @{
            # Tags applied to this module for discoverability in PSGallery
            Tags       = @('Docker', 'Claude', 'AI', 'Development', 'Container')

            # URI for the license of this module
            LicenseUri = 'https://github.com/jasonmcboyd/dclaude/blob/main/LICENSE'

            # URI for the project site of this module
            ProjectUri = 'https://github.com/jasonmcboyd/dclaude'
        }
    }
}
