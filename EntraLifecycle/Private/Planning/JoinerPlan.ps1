# Joiner (Arrivee): create the account, grant the role's groups and licenses, attach the manager and
# issue a one-time Temporary Access Pass. Idempotent: an existing employeeId is never re-created.

function Get-ELJoinerPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State
    )

    $row = $RowContext.Row
    $existing = Get-ELSnapshotUser -Snapshot $State.Snapshot -EmployeeId $row.Matricule
    if ($existing) { return Get-ELExistingJoinerPlan -RowContext $RowContext -State $State -User $existing }

    try {
        $upn = New-ELUserPrincipalName -GivenName $row.Prenom -Surname $row.Nom -Domain $State.Config.UpnDomain -TakenUpn $State.ReservedUpns
    }
    catch {
        return New-ELRowResult -Errors @(New-ELRowIssue -RowContext $RowContext -Message $_.Exception.Message)
    }
    # Reserve the UPN so that a homonym later in the same export gets the next suffix.
    [void]$State.ReservedUpns.Add($upn)
    $context = New-ELRowContext -Index $RowContext.Index -Row $row -Today $RowContext.Today -UserPrincipalName $upn

    $groups = Get-ELGroupChange -RowContext $context -State $State -TargetGroups $row.Role.Groups
    $licenses = Get-ELLicenseChange -RowContext $context -State $State -TargetSkus $row.Role.Licenses
    $manager = Get-ELManagerChange -RowContext $context -State $State
    $actions = @(New-ELCreateUserAction -RowContext $context) + $groups.Actions + $licenses.Actions +
        $manager.Actions + @(New-ELTapAction -RowContext $context)
    New-ELRowResult -Actions $actions -Warnings ($groups.Warnings + $licenses.Warnings + $manager.Warnings)
}

function Get-ELExistingJoinerPlan {
    <#
    .SYNOPSIS
        Joiner already present (re-run after a partial apply, or created by hand): only fills the gaps.
        No removal and no new Temporary Access Pass.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [object] $User
    )

    $row = $RowContext.Row
    $context = New-ELRowContext -Index $RowContext.Index -Row $row -Today $RowContext.Today -UserPrincipalName $User.UserPrincipalName
    $detail = 'Un compte porte déjà l''employeeId {0} : création ignorée, seuls les accès manquants sont complétés' -f $row.Matricule
    $skip = New-ELAction -RowContext $context -Action 'SkipExisting' -Target $User.UserPrincipalName -Detail $detail -Parameters @{ UserId = $User.Id }

    $attributes = Get-ELAttributeAction -RowContext $context -User $User -Role $row.Role
    $groups = Get-ELGroupChange -RowContext $context -State $State -TargetGroups $row.Role.Groups -CurrentGroupIds $User.GroupIds -UserId $User.Id
    $licenses = Get-ELLicenseChange -RowContext $context -State $State -TargetSkus $row.Role.Licenses -CurrentSkuIds $User.SkuIds -UserId $User.Id
    $manager = Get-ELManagerChange -RowContext $context -State $State -CurrentManagerId $User.ManagerId -UserId $User.Id

    $warnings = @($groups.Warnings + $licenses.Warnings + $manager.Warnings)
    if (-not $User.AccountEnabled) {
        $warnings += New-ELRowIssue -RowContext $context -Message 'Compte existant désactivé : réactivation à valider manuellement (réembauche ?)'
    }
    $actions = @($skip) + @($attributes) + $groups.Actions + $licenses.Actions + $manager.Actions
    New-ELRowResult -Actions $actions -Warnings $warnings
}

function New-ELCreateUserAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext
    )

    $row = $RowContext.Row
    $role = $row.Role
    $upn = $RowContext.UserPrincipalName
    $displayName = '{0} {1}' -f $row.Prenom, $row.Nom
    # The initial password is generated at apply time only: it never appears in the plan.
    $body = @{
        accountEnabled    = $true
        displayName       = $displayName
        givenName         = $row.Prenom
        surname           = $row.Nom
        mailNickname      = $upn.Split('@')[0]
        userPrincipalName = $upn
        employeeId        = $row.Matricule
        department        = $role.Department
        jobTitle          = $role.JobTitle
        usageLocation     = $role.UsageLocation
    }
    $detail = 'Création du compte « {0} » ({1} / {2}), employeeId {3}' -f $displayName, $role.Service, $role.Poste, $row.Matricule
    New-ELAction -RowContext $RowContext -Action 'CreateUser' -Target $upn -Detail $detail -Parameters @{ Body = $body }
}

function New-ELTapAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext
    )

    $hours = $script:ELTapLifetimeMinutes / $script:ELMinutesPerHour
    $detail = 'Temporary Access Pass à usage unique, valable {0} h, à remettre au manager par un canal sûr' -f $hours
    New-ELAction -RowContext $RowContext -Action 'IssueTemporaryAccessPass' -Target $RowContext.UserPrincipalName `
        -Detail $detail -Risk $script:ELRisk.Medium -Parameters @{
        UserId            = ''
        LifetimeInMinutes = $script:ELTapLifetimeMinutes
        IsUsableOnce      = $script:ELTapIsUsableOnce
        ManagerMatricule  = $RowContext.Row.Manager
    }
}
