# Self-contained HTML rendering of a plan: inline CSS, no script, strict CSP, all values encoded.

function ConvertTo-ELPlanHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $parts = @(
        Get-ELReportHead -Plan $Plan
        '<body><main>'
        Get-ELReportHeader -Plan $Plan
        Get-ELReportCards -Plan $Plan
        Get-ELReportMovementSection -Plan $Plan
        Get-ELReportActionCountSection -Plan $Plan
        Get-ELReportRiskSection -Plan $Plan
        Get-ELReportActionSection -Plan $Plan
        Get-ELReportIssueSection -Title 'Erreurs de validation (lignes non traitées)' -Issues @($Plan.Errors) -EmptyText 'Aucune erreur de validation.'
        Get-ELReportIssueSection -Title 'Avertissements' -Issues @($Plan.Warnings) -EmptyText 'Aucun avertissement.'
        Get-ELReportFooter
        '</main></body></html>'
    )
    $parts -join [Environment]::NewLine
}

function Get-ELReportHead {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    '<!DOCTYPE html>'
    '<html lang="fr">'
    '<head>'
    '<meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    '<meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''">'
    '<title>EntraLifecycle - plan ' + (ConvertTo-ELHtml -Value $Plan.SourceFile) + '</title>'
    '<style>' + $script:ELReportCss + '</style>'
    '</head>'
}

function Get-ELReportHeader {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $badge = ''
    if ($Plan.IsDemo) { $badge = ' <span class="badge demo">MODE DÉMO - tenant fictif</span>' }
    $generatedAt = ([datetime]$Plan.GeneratedAt).ToString('yyyy-MM-dd HH:mm')
    $referenceDate = ([datetime]$Plan.ReferenceDate).ToString($script:ELDateFormat)
    $values = @(
        (ConvertTo-ELHtml -Value $Plan.SourceFile)
        (ConvertTo-ELHtml -Value $Plan.UpnDomain)
        (ConvertTo-ELHtml -Value $generatedAt)
        (ConvertTo-ELHtml -Value $referenceDate)
        (ConvertTo-ELHtml -Value $Plan.RetentionDays)
    )
    $meta = 'Source : {0} · Domaine : {1} · Généré le {2} · Date de référence : {3} · Rétention des licences après départ : {4} jours' -f $values

    '<header><h1>Plan de cycle de vie des identités' + $badge + '</h1>'
    '<p class="meta">' + $meta + '</p>'
    '<p class="notice">Ce rapport décrit un plan : rien n''est modifié dans le tenant tant que Invoke-ELPlan n''est pas exécuté et confirmé. Les actions différées attendent leur date d''effet.</p>'
    '</header>'
}

function Get-ELReportCards {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $summary = $Plan.Summary
    $cards = @(
        @('Lignes lues', $Plan.RowCount, ''),
        @('Lignes valides', $Plan.ValidRowCount, ''),
        @('Erreurs', @($Plan.Errors).Count, 'alert'),
        @('Actions', $summary.TotalActions, ''),
        @('À appliquer', $summary.ReadyActions, ''),
        @('Différées', $summary.DeferredActions, ''),
        @('Risque élevé', $summary.HighRiskActions, 'alert')
    )
    $items = foreach ($card in $cards) {
        $class = 'card'
        if ($card[2] -eq 'alert' -and [int]$card[1] -gt 0) { $class = 'card alert' }
        '<div class="' + $class + '"><span class="value">' + (ConvertTo-ELHtml -Value $card[1]) + '</span><span class="label">' + (ConvertTo-ELHtml -Value $card[0]) + '</span></div>'
    }
    '<section class="cards">' + ($items -join '') + '</section>'
}

function Get-ELReportMovementSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $rows = @(foreach ($item in @($Plan.Summary.ByMovement)) {
            '<tr>' + (ConvertTo-ELHtmlCell -Value $item.Libelle) + (ConvertTo-ELHtmlCell -Value $item.Personnes -Numeric) + (ConvertTo-ELHtmlCell -Value $item.Actions -Numeric) + '</tr>'
        })
    $table = ConvertTo-ELHtmlTable -Header @('Mouvement', 'Personnes', 'Actions') -Rows $rows -EmptyText 'Aucun mouvement.'
    ConvertTo-ELHtmlSection -Title 'Synthèse par mouvement' -Body $table
}

function Get-ELReportActionCountSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $rows = @(foreach ($item in @($Plan.Summary.ByAction)) {
            '<tr>' + (ConvertTo-ELHtmlCell -Value $item.Libelle) + (ConvertTo-ELHtmlCell -Value $item.Action) + (ConvertTo-ELHtmlCell -Value $item.Nombre -Numeric) + '</tr>'
        })
    $table = ConvertTo-ELHtmlTable -Header @('Action', 'Code', 'Nombre') -Rows $rows -EmptyText 'Aucune action planifiée.'
    ConvertTo-ELHtmlSection -Title 'Synthèse par action' -Body $table
}

function Get-ELReportRiskSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $highRisk = @($Plan.Actions | Where-Object { $_.Risk -eq $script:ELRisk.High })
    $rows = @(foreach ($action in $highRisk) {
            '<tr>' + (ConvertTo-ELHtmlCell -Value $action.Order -Numeric) + (ConvertTo-ELHtmlCell -Value $action.Matricule) +
            (ConvertTo-ELHtmlCell -Value $action.Action) + (ConvertTo-ELHtmlCell -Value $action.Target) +
            (ConvertTo-ELHtmlCell -Value $action.Detail) + (ConvertTo-ELHtmlCell -Value $action.Status) + '</tr>'
        })
    $table = ConvertTo-ELHtmlTable -Header @('#', 'Matricule', 'Action', 'Cible', 'Détail', 'Statut') -Rows $rows -EmptyText 'Aucune action à risque élevé.'
    $intro = '<p>Actions à valider en priorité : modification de groupes à privilèges, départ d''un compte disposant d''un rôle d''administration.</p>'
    ConvertTo-ELHtmlSection -Title 'Points d''attention (risque élevé)' -Body ($intro + $table)
}

function Get-ELReportActionSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $rows = @(foreach ($action in @($Plan.Actions)) {
            $rowClass = ''
            if ($action.Status -eq $script:ELStatus.Deferred) { $rowClass = ' class="deferred"' }
            $movement = $script:ELMovementLabel[[string]$action.Mouvement]
            '<tr' + $rowClass + '>' + (ConvertTo-ELHtmlCell -Value $action.Order -Numeric) + (ConvertTo-ELHtmlCell -Value $action.Matricule) +
            (ConvertTo-ELHtmlCell -Value $movement) + (ConvertTo-ELHtmlCell -Value $action.Action) +
            (ConvertTo-ELHtmlCell -Value $action.Target) + (ConvertTo-ELHtmlCell -Value $action.Detail) +
            (ConvertTo-ELRiskCell -Risk $action.Risk) + (ConvertTo-ELHtmlCell -Value $action.Status) +
            (ConvertTo-ELHtmlCell -Value $action.DateEffet) + '</tr>'
        })
    $header = @('#', 'Matricule', 'Mouvement', 'Action', 'Cible', 'Détail', 'Risque', 'Statut', 'Date d''effet')
    $table = ConvertTo-ELHtmlTable -Header $header -Rows $rows -EmptyText 'Aucune action : le tenant est déjà conforme à l''export RH.'
    ConvertTo-ELHtmlSection -Title 'Actions planifiées (ordre d''application)' -Body $table
}

function Get-ELReportIssueSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Title,
        [AllowEmptyCollection()] [object[]] $Issues = @(),
        [Parameter(Mandatory)] [string] $EmptyText
    )

    $rows = @(foreach ($issue in @($Issues | Where-Object { $null -ne $_ })) {
            '<tr>' + (ConvertTo-ELHtmlCell -Value $issue.Ligne -Numeric) + (ConvertTo-ELHtmlCell -Value $issue.Matricule) + (ConvertTo-ELHtmlCell -Value $issue.Message) + '</tr>'
        })
    $table = ConvertTo-ELHtmlTable -Header @('Ligne', 'Matricule', 'Message') -Rows $rows -EmptyText $EmptyText
    ConvertTo-ELHtmlSection -Title $Title -Body $table
}

function Get-ELReportFooter {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $text = 'Généré par EntraLifecycle v{0}. Ce rapport ne contient aucun secret (ni mot de passe, ni Temporary Access Pass).' -f $script:ELVersion
    '<footer>' + (ConvertTo-ELHtml -Value $text) + '</footer>'
}
