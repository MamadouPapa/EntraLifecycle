function Get-ELPlan {
    <#
    .SYNOPSIS
        Builds the Joiner-Mover-Leaver plan from an HR export. Read-only: nothing changes in the tenant.

    .DESCRIPTION
        Validates every HR row against the role catalog, reads the current tenant state (users by
        employeeId, group memberships, licenses, manager) with Get-Mg* cmdlets only, and returns an
        ordered list of actions with their risk level. Invalid rows become plan errors.
        Apply the plan with Invoke-ELPlan after review; render it with Export-ELPlanReport.

    .PARAMETER CsvPath
        HR export (UTF-8, ';' or ',' delimiter detected automatically) with the columns
        Matricule, Prenom, Nom, Service, Poste, Manager, DateEffet (yyyy-MM-dd), Mouvement (Arrivee|Mutation|Depart).

    .PARAMETER ConfigPath
        Role catalog (JSON), see config/roles.json.

    .PARAMETER DemoMode
        Plans against an in-memory fake tenant (contoso.example) instead of Microsoft Graph.

    .PARAMETER ReferenceDate
        Date used to split ready and deferred actions and to compute license removal dates.
        Default: today. Useful to rehearse a future plan or to make the demo reproducible.

    .EXAMPLE
        $plan = Get-ELPlan -CsvPath .\samples\rh-export-demo.csv -ConfigPath .\config\roles.json -DemoMode
        $plan.Actions | Format-Table Order, Matricule, Mouvement, Action, Target, Risk, Status
    #>
    [CmdletBinding()]
    [OutputType('EntraLifecycle.Plan')]
    param(
        [Parameter(Mandatory)] [string] $CsvPath,
        [Parameter(Mandatory)] [string] $ConfigPath,
        [switch] $DemoMode,
        [datetime] $ReferenceDate = (Get-Date).Date
    )

    $config = Import-ELConfig -Path $ConfigPath
    if ($DemoMode) {
        $fixture = Read-ELJsonFile -Path $script:ELDemoFixturePath -Label 'Tenant de démonstration'
        $config = Copy-ELConfigWithDomain -Config $config -Domain ([string]$fixture.domain)
        $import = Import-ELHrCsv -Path $CsvPath -Config $config
        $snapshot = ConvertTo-ELFixtureSnapshot -Fixture $fixture
    }
    else {
        $import = Import-ELHrCsv -Path $CsvPath -Config $config
        $snapshot = Get-ELLiveSnapshot -Import $import -Config $config
    }

    $plan = New-ELPlanCore -Import $import -Config $config -Snapshot $snapshot -Today $ReferenceDate.Date `
        -IsDemo ([bool]$DemoMode) -SourceFile (Split-Path -Path $CsvPath -Leaf)
    Write-Verbose ('Plan : {0} action(s), {1} erreur(s), {2} avertissement(s).' -f $plan.Summary.TotalActions, @($plan.Errors).Count, @($plan.Warnings).Count)
    $plan
}
