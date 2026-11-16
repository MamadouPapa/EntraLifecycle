# Planning engine: pure function of (validated rows, role catalog, tenant snapshot, reference date).
# It never calls Microsoft Graph, which keeps demo mode and tests on the exact same code path.

function New-ELPlanCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Import,
        [Parameter(Mandatory)] [object] $Config,
        [Parameter(Mandatory)] [object] $Snapshot,
        [Parameter(Mandatory)] [datetime] $Today,
        [bool] $IsDemo = $false,
        [AllowEmptyString()] [string] $SourceFile = ''
    )

    $state = New-ELPlanState -Import $Import -Config $Config -Snapshot $Snapshot
    $entries = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[object]
    foreach ($issue in @($Import.Errors)) { $errors.Add($issue) }

    $index = 0
    foreach ($row in @($Import.Rows)) {
        $context = New-ELRowContext -Index $index -Row $row -Today $Today
        $result = Get-ELRowPlan -RowContext $context -State $state
        $sequence = 0
        foreach ($action in $result.Actions) {
            $phase = Get-ELActionPhase -Action $action.Action
            $entries.Add([pscustomobject]@{ Phase = $phase; RowIndex = $index; Sequence = $sequence; Action = $action })
            $sequence++
        }
        foreach ($issue in $result.Errors) { $errors.Add($issue) }
        foreach ($issue in $result.Warnings) { $warnings.Add($issue) }
        $index++
    }

    $actions = @(Get-ELOrderedAction -Entries $entries.ToArray())
    [pscustomobject]@{
        PSTypeName    = 'EntraLifecycle.Plan'
        GeneratedAt   = Get-Date
        ReferenceDate = $Today.Date
        IsDemo        = $IsDemo
        SourceFile    = $SourceFile
        UpnDomain     = $Config.UpnDomain
        RetentionDays = $Config.RetentionDays
        RowCount      = $Import.RowCount
        ValidRowCount = @($Import.Rows).Count
        Actions       = $actions
        Errors        = $errors.ToArray()
        Warnings      = $warnings.ToArray()
        Summary       = Get-ELPlanSummary -Actions $actions
    }
}

function New-ELPlanState {
    <#
    .SYNOPSIS
        Mutable planning state: UPNs reserved during this run (starts as a copy of the tenant's).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Import,
        [Parameter(Mandatory)] [object] $Config,
        [Parameter(Mandatory)] [object] $Snapshot
    )

    $newJoiners = @($Import.Rows | Where-Object {
            $_.Mouvement -eq $script:ELMovement.Joiner -and -not $Snapshot.Users.ContainsKey($_.Matricule)
        } | ForEach-Object { $_.Matricule })

    [pscustomobject]@{
        Config           = $Config
        Snapshot         = $Snapshot
        ReservedUpns     = New-ELNameSet -Values @($Snapshot.TakenUpns)
        JoinerMatricules = New-ELNameSet -Values $newJoiners
    }
}

function Get-ELRowPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State
    )

    $row = $RowContext.Row
    if ($State.Snapshot.AmbiguousEmployeeIds.Contains($row.Matricule)) {
        $message = 'Plusieurs comptes portent l''employeeId {0} : corriger l''annuaire avant tout traitement automatique' -f $row.Matricule
        return New-ELRowResult -Errors @(New-ELRowIssue -RowContext $RowContext -Message $message)
    }
    if ($row.Mouvement -eq $script:ELMovement.Joiner) { return Get-ELJoinerPlan -RowContext $RowContext -State $State }
    if ($row.Mouvement -eq $script:ELMovement.Mover) { return Get-ELMoverPlan -RowContext $RowContext -State $State }
    Get-ELLeaverPlan -RowContext $RowContext -State $State
}

function Get-ELActionPhase {
    <#
    .SYNOPSIS
        Account creations run first so that managers created by the plan exist before SetManager.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [string] $Action
    )

    if ($Action -eq 'CreateUser') { return 0 }
    1
}

function Get-ELOrderedAction {
    <#
    .SYNOPSIS
        Sorts by phase, HR row order, then intra-row sequence; returns numbered copies (Order = 1..N).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [object[]] $Entries = @()
    )

    $order = 0
    foreach ($entry in @($Entries | Sort-Object -Property Phase, RowIndex, Sequence)) {
        $order++
        $copy = $entry.Action.PSObject.Copy()
        $copy.Order = $order
        $copy
    }
}
