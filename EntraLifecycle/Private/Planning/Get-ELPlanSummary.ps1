# Plan counters used by the console output and the HTML report.

function Get-ELPlanSummary {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [object[]] $Actions = @()
    )

    $all = @($Actions | Where-Object { $null -ne $_ })
    $byMovement = foreach ($movement in @($script:ELMovement.Joiner, $script:ELMovement.Mover, $script:ELMovement.Leaver)) {
        $subset = @($all | Where-Object { $_.Mouvement -eq $movement })
        [pscustomobject]@{
            Mouvement = $movement
            Libelle   = $script:ELMovementLabel[$movement]
            Personnes = @($subset | ForEach-Object { $_.Matricule } | Sort-Object -Unique).Count
            Actions   = $subset.Count
        }
    }
    $byAction = foreach ($name in @($script:ELActionLabel.Keys)) {
        $count = @($all | Where-Object { $_.Action -eq $name }).Count
        if ($count -gt 0) {
            [pscustomobject]@{ Action = $name; Libelle = $script:ELActionLabel[$name]; Nombre = $count }
        }
    }

    [pscustomobject]@{
        PSTypeName      = 'EntraLifecycle.PlanSummary'
        TotalActions    = $all.Count
        ReadyActions    = @($all | Where-Object { $_.Status -eq $script:ELStatus.Ready }).Count
        DeferredActions = @($all | Where-Object { $_.Status -eq $script:ELStatus.Deferred }).Count
        HighRiskActions = @($all | Where-Object { $_.Risk -eq $script:ELRisk.High }).Count
        ByMovement      = @($byMovement)
        ByAction        = @($byAction)
    }
}
