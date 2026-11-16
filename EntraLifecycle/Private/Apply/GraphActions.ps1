# Microsoft Graph write operations, one per action type. Every call uses -ErrorAction Stop so that
# failures surface to Invoke-ELActionSafely, which records them and moves on, and -Confirm:$false
# because the confirmation is handled once per action by Invoke-ELPlan (no double prompt).

function Invoke-ELPlanAction {
    <#
    .SYNOPSIS
        Skip rules, then confirmation, then the isolated Graph (or demo) call for one action.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [System.Management.Automation.PSCmdlet] $Cmdlet
    )

    $skip = Get-ELSkipResult -Action $Action -State $State
    if ($skip) { return $skip }
    if ($Cmdlet.ShouldProcess($Action.Target, (Get-ELActionDescription -Action $Action))) {
        return Invoke-ELActionSafely -Action $Action -State $State
    }
    New-ELActionResult -Action $Action -Result $script:ELResult.NotApplied
}

function Invoke-ELActionSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State
    )

    try {
        if ($State.IsDemo) { $outputs = @(Invoke-ELDemoAction -Action $Action -State $State) }
        else { $outputs = @(Invoke-ELGraphAction -Action $Action -State $State) }
        $handoff = $outputs | Where-Object { $null -ne $_ -and $_.PSObject.TypeNames -contains 'EntraLifecycle.Handoff' } | Select-Object -First 1
        if ($handoff) { $State.Handoffs.Add($handoff) }
        New-ELActionResult -Action $Action -Result $script:ELResult.Success
    }
    catch {
        New-ELActionResult -Action $Action -Result $script:ELResult.Failure -Message $_.Exception.Message
    }
}

function Invoke-ELGraphAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State
    )

    if ($Action.Action -eq 'CreateUser') {
        Invoke-ELCreateUser -Action $Action -State $State
        return
    }

    $userId = Resolve-ELApplyUserId -Action $Action -State $State
    $parameters = $Action.Parameters
    switch ($Action.Action) {
        'UpdateAttributes' { Update-MgUser -UserId $userId -BodyParameter $parameters.Body -Confirm:$false -ErrorAction Stop | Out-Null }
        'DisableAccount' { Update-MgUser -UserId $userId -BodyParameter @{ accountEnabled = $false } -Confirm:$false -ErrorAction Stop | Out-Null }
        'RevokeSessions' { Revoke-MgUserSignInSession -UserId $userId -Confirm:$false -ErrorAction Stop | Out-Null }
        'SetManager' { Invoke-ELSetManager -Action $Action -State $State -UserId $userId }
        'AddGroup' { New-MgGroupMember -GroupId $parameters.GroupId -DirectoryObjectId $userId -Confirm:$false -ErrorAction Stop | Out-Null }
        'RemoveGroup' { Remove-MgGroupMemberByRef -GroupId $parameters.GroupId -DirectoryObjectId $userId -Confirm:$false -ErrorAction Stop | Out-Null }
        'AssignLicense' {
            Set-MgUserLicense -UserId $userId -AddLicenses @(@{ SkuId = $parameters.SkuId }) -RemoveLicenses @() -Confirm:$false -ErrorAction Stop | Out-Null
        }
        'RemoveLicense' {
            Set-MgUserLicense -UserId $userId -AddLicenses @() -RemoveLicenses @($parameters.SkuId) -Confirm:$false -ErrorAction Stop | Out-Null
        }
        'IssueTemporaryAccessPass' { Invoke-ELIssueTemporaryAccessPass -Action $Action -UserId $userId }
        default { throw ('Action non prise en charge : {0}' -f $Action.Action) }
    }
}

function Invoke-ELCreateUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State
    )

    $body = @{}
    foreach ($key in $Action.Parameters.Body.Keys) { $body[$key] = $Action.Parameters.Body[$key] }
    $initialPassword = New-ELRandomPassword
    $body['passwordProfile'] = @{ password = $initialPassword; forceChangePasswordNextSignIn = $true }

    $user = New-MgUser -BodyParameter $body -Confirm:$false -ErrorAction Stop
    if (-not $user -or -not $user.Id) { throw 'New-MgUser n''a renvoyé aucun identifiant' }
    $State.UserIds[$Action.Matricule] = [string]$user.Id
}

function Invoke-ELSetManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [string] $UserId
    )

    $managerId = Resolve-ELApplyManagerId -Action $Action -State $State
    $reference = @{ '@odata.id' = $script:ELGraphUserRefBase + $managerId }
    Set-MgUserManagerByRef -UserId $UserId -BodyParameter $reference -Confirm:$false -ErrorAction Stop | Out-Null
}

function Invoke-ELIssueTemporaryAccessPass {
    <#
    .SYNOPSIS
        Creates a one-time TAP and returns it only inside a handoff object, as a SecureString.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [string] $UserId
    )

    $parameters = $Action.Parameters
    $lifetime = [int]$parameters.LifetimeInMinutes
    $body = @{ isUsableOnce = [bool]$parameters.IsUsableOnce; lifetimeInMinutes = $lifetime }
    $method = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $UserId -BodyParameter $body -Confirm:$false -ErrorAction Stop
    if (-not $method -or -not $method.TemporaryAccessPass) { throw 'Microsoft Graph n''a renvoyé aucun Temporary Access Pass' }
    New-ELHandoff -Action $Action -Secret (ConvertTo-ELSecureString -Value ([string]$method.TemporaryAccessPass))
}

function New-ELHandoff {
    <#
    .SYNOPSIS
        Credential handoff for the manager: the TAP exists only here, as a read-only SecureString.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [System.Security.SecureString] $Secret
    )

    $parameters = $Action.Parameters
    [pscustomobject]@{
        PSTypeName          = 'EntraLifecycle.Handoff'
        Matricule           = $Action.Matricule
        UserPrincipalName   = $Action.Target
        ManagerMatricule    = [string]$parameters.ManagerMatricule
        TemporaryAccessPass = $Secret
        IsUsableOnce        = [bool]$parameters.IsUsableOnce
        ExpiresAt           = (Get-Date).AddMinutes([int]$parameters.LifetimeInMinutes)
    }
}

function Resolve-ELApplyUserId {
    <#
    .SYNOPSIS
        Object id of the action's user: from the plan, from an account created earlier in this run,
        or looked up by employeeId.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State
    )

    $planned = [string]$Action.Parameters.UserId
    if ($planned) { return $planned }
    Resolve-ELUserIdByMatricule -Matricule $Action.Matricule -State $State
}

function Resolve-ELApplyManagerId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State
    )

    $planned = [string]$Action.Parameters.ManagerId
    if ($planned) { return $planned }
    Resolve-ELUserIdByMatricule -Matricule ([string]$Action.Parameters.ManagerMatricule) -State $State
}

function Resolve-ELUserIdByMatricule {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Matricule,
        [Parameter(Mandatory)] [object] $State
    )

    if ($State.UserIds.ContainsKey($Matricule)) { return [string]$State.UserIds[$Matricule] }
    $found = @(Find-ELLiveUser -EmployeeId $Matricule)
    if ($found.Count -ne 1) {
        throw ('Compte introuvable (ou ambigu) pour l''employeeId {0} au moment de l''application' -f $Matricule)
    }
    $State.UserIds[$Matricule] = [string]$found[0].Id
    [string]$found[0].Id
}
