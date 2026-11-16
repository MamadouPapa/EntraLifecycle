# Factories for the objects that make up a plan: row contexts, actions, issues and row results.

function New-ELRowContext {
    <#
    .SYNOPSIS
        Wraps a validated HR row with its position, effective status and resolved UPN.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int] $Index,
        [Parameter(Mandatory)] [object] $Row,
        [Parameter(Mandatory)] [datetime] $Today,
        [AllowEmptyString()] [string] $UserPrincipalName = ''
    )

    $status = $script:ELStatus.Ready
    if ($Row.DateEffet.Date -gt $Today.Date) { $status = $script:ELStatus.Deferred }

    [pscustomobject]@{
        Index             = $Index
        Row               = $Row
        Today             = $Today.Date
        Status            = $status
        UserPrincipalName = $UserPrincipalName
    }
}

function New-ELAction {
    <#
    .SYNOPSIS
        Creates one plan action. Parameters holds the identifiers needed at apply time.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [string] $Action,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Target,
        [Parameter(Mandatory)] [string] $Detail,
        [string] $Risk = $script:ELRisk.Low,
        [hashtable] $Parameters = @{}
    )

    $row = $RowContext.Row
    [pscustomobject]@{
        PSTypeName        = 'EntraLifecycle.Action'
        Order             = 0
        Matricule         = $row.Matricule
        Mouvement         = $row.Mouvement
        Action            = $Action
        Target            = $Target
        Detail            = $Detail
        Risk              = $Risk
        Status            = $RowContext.Status
        DateEffet         = $row.DateEffet.ToString($script:ELDateFormat)
        UserPrincipalName = $RowContext.UserPrincipalName
        Parameters        = $Parameters
    }
}

function New-ELPlanIssue {
    <#
    .SYNOPSIS
        Validation error or warning attached to an HR row (Ligne = line number in the CSV).
    #>
    [CmdletBinding()]
    param(
        [int] $Line = 0,
        [AllowEmptyString()] [string] $Matricule = '',
        [Parameter(Mandatory)] [string] $Message
    )

    [pscustomobject]@{
        PSTypeName = 'EntraLifecycle.Issue'
        Ligne      = $Line
        Matricule  = $Matricule
        Message    = $Message
    }
}

function New-ELRowIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [string] $Message
    )

    New-ELPlanIssue -Line $RowContext.Row.Line -Matricule $RowContext.Row.Matricule -Message $Message
}

function New-ELRowResult {
    <#
    .SYNOPSIS
        Outcome of planning one row: actions plus blocking errors and non-blocking warnings.
    #>
    [CmdletBinding()]
    param(
        [object[]] $Actions = @(),
        [object[]] $Errors = @(),
        [object[]] $Warnings = @()
    )

    [pscustomobject]@{
        Actions  = @($Actions | Where-Object { $null -ne $_ })
        Errors   = @($Errors | Where-Object { $null -ne $_ })
        Warnings = @($Warnings | Where-Object { $null -ne $_ })
    }
}

function Assert-ELPlan {
    [CmdletBinding()]
    param(
        [AllowNull()] [object] $Plan
    )

    $isPlan = $null -ne $Plan -and
        $null -ne $Plan.PSObject.Properties['Actions'] -and
        $null -ne $Plan.PSObject.Properties['GeneratedAt']
    if (-not $isPlan) {
        throw 'Objet de plan invalide : passez la sortie de Get-ELPlan.'
    }
}
