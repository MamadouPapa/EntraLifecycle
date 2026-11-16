# Text rendering of a plan (Format-ELPlan), in the spirit of "terraform plan".

$script:ELPlanTextActionWidth = 26
$script:ELPlanTextTargetWidth = 40

function Get-ELPlanTextHeader {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $mode = ''
    if ($Plan.IsDemo) { $mode = ' [MODE DÉMO - tenant fictif]' }
    $reference = ([datetime]$Plan.ReferenceDate).ToString($script:ELDateFormat)
    'EntraLifecycle - plan {0} (domaine {1}, date de référence {2}){3}' -f $Plan.SourceFile, $Plan.UpnDomain, $reference, $mode
    'Symboles : + création/ajout, ~ modification, - retrait/révocation, . information, (!) risque élevé'
}

function Get-ELPlanTextBody {
    <#
    .SYNOPSIS
        One block per matricule (in order of first action), actions in application order.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()] [object[]] $Actions = @()
    )

    $sorted = @($Actions | Where-Object { $null -ne $_ } | Sort-Object -Property Order)
    if ($sorted.Count -eq 0) {
        ''
        'Aucune action : le tenant est déjà conforme à l''export RH.'
        return
    }
    $matricules = @($sorted | ForEach-Object { $_.Matricule } | Select-Object -Unique)
    foreach ($matricule in $matricules) {
        $personActions = @($sorted | Where-Object { $_.Matricule -eq $matricule })
        $first = $personActions[0]
        ''
        '  # {0} - {1} - {2}' -f $matricule, $script:ELMovementLabel[[string]$first.Mouvement], $first.UserPrincipalName
        foreach ($action in $personActions) { ConvertTo-ELPlanTextLine -Action $action }
    }
}

function ConvertTo-ELPlanTextLine {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Action
    )

    $symbol = $script:ELActionSymbol[[string]$Action.Action]
    if (-not $symbol) { $symbol = '?' }
    $flags = @()
    if ($Action.Risk -eq $script:ELRisk.High) { $flags += '(!)' }
    if ($Action.Status -eq $script:ELStatus.Deferred) { $flags += ('(différé au {0})' -f $Action.DateEffet) }
    if ($Action.Action -eq 'ScheduleLicenseRemoval') { $flags += ('(retrait le {0})' -f $Action.Parameters.RemovalDate) }
    $line = '  {0} {1} {2}' -f $symbol, ([string]$Action.Action).PadRight($script:ELPlanTextActionWidth), ([string]$Action.Target).PadRight($script:ELPlanTextTargetWidth)
    (($line + ' ' + ($flags -join ' ')).TrimEnd())
}

function Get-ELPlanTextIssue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Title,
        [AllowEmptyCollection()] [object[]] $Issues = @()
    )

    $list = @($Issues | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return }
    ''
    '{0} ({1}) :' -f $Title, $list.Count
    foreach ($issue in $list) {
        '  ! ligne {0} [{1}] {2}' -f $issue.Ligne, $issue.Matricule, $issue.Message
    }
}

function Get-ELPlanTextTotal {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $actions = @($Plan.Actions)
    $counts = @{ '+' = 0; '~' = 0; '-' = 0 }
    foreach ($action in $actions) {
        $symbol = $script:ELActionSymbol[[string]$action.Action]
        if ($symbol -and $counts.ContainsKey($symbol)) { $counts[$symbol]++ }
    }
    $summary = $Plan.Summary
    'Plan : {0} à créer/ajouter, {1} à modifier, {2} à retirer/révoquer ({3} différée(s), {4} à risque élevé) ; {5} erreur(s), {6} avertissement(s).' -f `
        $counts['+'], $counts['~'], $counts['-'], $summary.DeferredActions, $summary.HighRiskActions, @($Plan.Errors).Count, @($Plan.Warnings).Count
    'Rien n''est modifié tant que Invoke-ELPlan n''est pas exécuté et confirmé.'
}
