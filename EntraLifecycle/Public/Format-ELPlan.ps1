function Format-ELPlan {
    <#
    .SYNOPSIS
        Renders a plan as Terraform-like text: one block per person, one line per action.

    .DESCRIPTION
        Symbols: "+" grant or create, "~" change, "-" revoke or remove, "." informational.
        Deferred actions are flagged with their effective date, high-risk actions with "(!)".
        The text contains no secret: a plan never holds a password or a Temporary Access Pass.

    .PARAMETER Plan
        Output of Get-ELPlan.

    .EXAMPLE
        Get-ELPlan -CsvPath .\samples\rh-export-demo.csv -ConfigPath .\config\roles.json -DemoMode | Format-ELPlan
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [object] $Plan
    )

    process {
        Assert-ELPlan -Plan $Plan
        Get-ELPlanTextHeader -Plan $Plan
        Get-ELPlanTextBody -Actions @($Plan.Actions)
        Get-ELPlanTextIssue -Title 'Erreurs (lignes non traitées)' -Issues @($Plan.Errors)
        Get-ELPlanTextIssue -Title 'Avertissements' -Issues @($Plan.Warnings)
        ''
        Get-ELPlanTextTotal -Plan $Plan
    }
}
