function Invoke-ELPlan {
    <#
    .SYNOPSIS
        Applies a plan produced by Get-ELPlan, action by action, with confirmation (ConfirmImpact High).

    .DESCRIPTION
        Each action is isolated: a failure is recorded and the run continues. Deferred actions
        (future DateEffet) and informational actions are never sent to Graph. Every decision is
        appended to a JSONL audit log (timestamp, run id, actor, matricule, action, target, result,
        error). Temporary Access Pass values are returned only in the Handoffs property, as
        SecureString, and never written to the console or the audit log. -WhatIf applies nothing
        and writes nothing. A -DemoMode plan is applied to the fictional tenant (no Graph call).

    .PARAMETER Plan
        Output of Get-ELPlan.

    .PARAMETER AuditLogPath
        JSONL audit file (appended). Default: .\audit\EntraLifecycle-audit-<horodatage>.jsonl

    .EXAMPLE
        $plan | Invoke-ELPlan -WhatIf

    .EXAMPLE
        $result = Invoke-ELPlan -Plan $plan -AuditLogPath .\audit\jml.jsonl
        $result.Results | Format-Table Order, Matricule, Action, Target, Result, Error
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('EntraLifecycle.ApplyResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [object] $Plan,
        [string] $AuditLogPath
    )

    process {
        Assert-ELPlan -Plan $Plan
        $isDemo = [bool]$Plan.IsDemo
        if (-not $isDemo) { Assert-ELGraphConnection }
        Test-ELPlanFreshness -Plan $Plan

        $isSimulation = [bool]$WhatIfPreference
        $state = New-ELApplyState -AuditLogPath (Resolve-ELAuditLogPath -Path $AuditLogPath) -WriteAudit (-not $isSimulation) -IsDemo $isDemo
        try {
            Write-ELAuditRunEvent -State $state -Kind 'start' -Detail ([string]$Plan.SourceFile)
        }
        catch {
            throw ('Journal d''audit inaccessible ({0}) : aucune action appliquée. {1}' -f $state.AuditLogPath, $_.Exception.Message)
        }

        $results = New-Object System.Collections.Generic.List[object]
        foreach ($action in @($Plan.Actions | Sort-Object -Property Order)) {
            $result = Invoke-ELPlanAction -Action $action -State $state -Cmdlet $PSCmdlet
            Register-ELActionOutcome -State $state -Result $result
            Write-ELAuditEntry -State $state -Result $result
            $results.Add($result)
        }
        $apply = New-ELApplyResult -State $state -Results $results.ToArray()
        Write-ELAuditRunEvent -State $state -Kind 'end' -Detail ('{0} succès, {1} échec(s)' -f $apply.Succeeded, $apply.Failed)
        $apply
    }
}
