# Apply-time state, per-action results and skip rules. Secrets (initial passwords, Temporary Access
# Pass values) are never part of a result: they only ever travel inside a Handoff (SecureString).

function New-ELApplyState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $AuditLogPath,
        [Parameter(Mandatory)] [bool] $WriteAudit,
        [bool] $IsDemo = $false
    )

    [pscustomobject]@{
        RunId            = [guid]::NewGuid().ToString()
        AuditLogPath     = $AuditLogPath
        WriteAudit       = $WriteAudit
        IsDemo           = $IsDemo
        Actor            = Get-ELActor -IsDemo $IsDemo
        UserIds          = @{}
        FailedMatricules = New-ELNameSet
        Handoffs         = New-Object System.Collections.Generic.List[object]
    }
}

function Get-ELActor {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [bool] $IsDemo = $false
    )

    if ($IsDemo) { return 'demo:{0}' -f [Environment]::UserName }
    $context = $null
    if (Get-Command -Name 'Get-MgContext' -ErrorAction SilentlyContinue) { $context = Get-MgContext }
    if ($context -and $context.Account) { return [string]$context.Account }
    if ($context -and $context.AppName) { return 'application:{0}' -f $context.AppName }
    [Environment]::UserName
}

function Resolve-ELAuditLogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Path
    )

    $target = $Path
    if (-not $target) {
        $fileName = 'EntraLifecycle-audit-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
        $target = Join-Path -Path (Join-Path -Path (Get-Location).ProviderPath -ChildPath 'audit') -ChildPath $fileName
    }
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($target)
}

function New-ELActionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [string] $Result,
        [AllowNull()] [AllowEmptyString()] [string] $Message = ''
    )

    $errorText = $null
    if ($Message) { $errorText = $Message }
    [pscustomobject]@{
        PSTypeName = 'EntraLifecycle.ActionResult'
        Order      = $Action.Order
        Matricule  = $Action.Matricule
        Mouvement  = $Action.Mouvement
        Action     = $Action.Action
        Target     = $Action.Target
        Result     = $Result
        Error      = $errorText
    }
}

function Get-ELSkipResult {
    <#
    .SYNOPSIS
        Result for actions that must not reach Graph: deferred, informational, or whose account
        creation did not succeed earlier in the run. $null means "apply it".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State
    )

    if ($Action.Status -eq $script:ELStatus.Deferred) {
        return New-ELActionResult -Action $Action -Result $script:ELResult.Deferred -Message ('Date d''effet {0} non atteinte : action non appliquée' -f $Action.DateEffet)
    }
    if ($Action.Action -eq 'ScheduleLicenseRemoval') {
        return New-ELActionResult -Action $Action -Result $script:ELResult.Scheduled
    }
    if ($Action.Action -eq 'SkipExisting') {
        return New-ELActionResult -Action $Action -Result $script:ELResult.Skipped
    }
    $failed = Get-ELFailedDependency -Action $Action -State $State
    if ($failed) {
        return New-ELActionResult -Action $Action -Result $script:ELResult.Cancelled -Message ('Compte {0} non créé : action annulée' -f $failed)
    }
    $null
}

function Get-ELFailedDependency {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State
    )

    if ($State.FailedMatricules.Contains($Action.Matricule)) { return $Action.Matricule }
    $managerMatricule = [string]$Action.Parameters.ManagerMatricule
    if ($Action.Action -eq 'SetManager' -and $managerMatricule -and $State.FailedMatricules.Contains($managerMatricule)) {
        return $managerMatricule
    }
    ''
}

function Register-ELActionOutcome {
    <#
    .SYNOPSIS
        A CreateUser that did not succeed (failure, refusal at the confirmation prompt) cancels every
        later action of the same person and the SetManager actions that point to them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [object] $Result
    )

    if ($Result.Action -eq 'CreateUser' -and $Result.Result -ne $script:ELResult.Success) {
        [void]$State.FailedMatricules.Add($Result.Matricule)
    }
}

function Get-ELActionDescription {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Action
    )

    '{0} [{1}]' -f $script:ELActionLabel[$Action.Action], $Action.Matricule
}

function Test-ELPlanFreshness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Plan
    )

    $age = (Get-Date) - [datetime]$Plan.GeneratedAt
    if ($age.TotalHours -gt $script:ELPlanMaxAgeHours) {
        Write-Warning ('Plan généré il y a plus de {0} h : l''état du tenant a pu changer, régénérez-le avec Get-ELPlan.' -f $script:ELPlanMaxAgeHours)
    }
}

function New-ELApplyResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $State,
        [AllowEmptyCollection()] [object[]] $Results = @()
    )

    $auditPath = $null
    if ($State.WriteAudit) { $auditPath = $State.AuditLogPath }
    $failed = @($Results | Where-Object { $_.Result -eq $script:ELResult.Failure }).Count
    $succeeded = @($Results | Where-Object { $_.Result -eq $script:ELResult.Success }).Count
    Write-Verbose ('Application : {0} succès, {1} échec(s), {2} action(s) au total.' -f $succeeded, $failed, $Results.Count)

    [pscustomobject]@{
        PSTypeName   = 'EntraLifecycle.ApplyResult'
        RunId        = $State.RunId
        IsDemo       = $State.IsDemo
        Succeeded    = $succeeded
        Failed       = $failed
        AuditLogPath = $auditPath
        Results      = $Results
        Handoffs     = $State.Handoffs.ToArray()
    }
}
