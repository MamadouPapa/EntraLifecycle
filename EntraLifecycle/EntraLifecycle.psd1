@{
    RootModule           = 'EntraLifecycle.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '597ec4a5-9153-4401-be3e-2e68f1c99a61'
    Author               = 'Papa Mamadou Gueye'
    CompanyName          = 'Community'
    Copyright            = '(c) 2026 Papa Mamadou Gueye. MIT License.'
    Description          = 'Joiner-Mover-Leaver identity lifecycle automation for Entra ID (Microsoft Graph) with a plan/apply safety model.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Get-ELPlan', 'Format-ELPlan', 'Export-ELPlanReport', 'Invoke-ELPlan')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('EntraID', 'MicrosoftGraph', 'IAM', 'Identity', 'JML', 'Lifecycle', 'Security')
            LicenseUri = 'https://opensource.org/licenses/MIT'
        }
    }
}
