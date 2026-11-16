# Leaver (Depart): disable, revoke sessions, remove catalog-managed groups, then remove licenses once
# the retention period has elapsed. The account itself is never deleted.

function Get-ELLeaverPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State
    )

    $row = $RowContext.Row
    $user = Get-ELSnapshotUser -Snapshot $State.Snapshot -EmployeeId $row.Matricule
    if (-not $user) {
        $message = 'Départ : aucun compte ne porte l''employeeId {0}, rien à révoquer (à vérifier : compte créé sans matricule ?)' -f $row.Matricule
        return New-ELRowResult -Warnings @(New-ELRowIssue -RowContext $RowContext -Message $message)
    }

    $context = New-ELRowContext -Index $RowContext.Index -Row $row -Today $RowContext.Today -UserPrincipalName $user.UserPrincipalName
    $disable = @(Get-ELDisableAction -RowContext $context -User $user)
    $groups = Get-ELGroupChange -RowContext $context -State $State -CurrentGroupIds $user.GroupIds -UserId $user.Id `
        -RemoveUnneeded -RemovalReason 'départ'
    $licenses = @(Get-ELLeaverLicenseAction -RowContext $context -State $State -User $user)
    $warnings = @($groups.Warnings) + @(Get-ELUnmanagedGroupWarning -RowContext $context -State $State -User $user)
    New-ELRowResult -Actions ($disable + $groups.Actions + $licenses) -Warnings $warnings
}

function Get-ELUnmanagedGroupWarning {
    <#
    .SYNOPSIS
        Memberships outside the role catalog are never removed automatically (dynamic, synced or
        project groups): the leaver keeps them disabled, and the group owners must review them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [object] $User
    )

    $managedIds = @(foreach ($name in $State.Config.ManagedGroups) {
            $group = $State.Snapshot.Groups[$name]
            if ($group) { $group.Id }
        })
    $unmanaged = @($User.GroupIds | Where-Object { $managedIds -notcontains $_ })
    if ($unmanaged.Count -eq 0) { return }
    $message = '{0} appartenance(s) hors catalogue conservée(s) sur le compte désactivé : revue manuelle par les propriétaires des groupes' -f $unmanaged.Count
    New-ELRowIssue -RowContext $RowContext -Message $message
}

function Get-ELDisableAction {
    <#
    .SYNOPSIS
        DisableAccount + RevokeSessions for an enabled account (nothing when already disabled).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $User
    )

    if (-not $User.AccountEnabled) { return }

    $roles = @($User.DirectoryRoles | Where-Object { $_ })
    $risk = $script:ELRisk.Medium
    $detail = 'Désactivation du compte (le compte est conservé, jamais supprimé)'
    if ($roles.Count -gt 0) {
        $risk = $script:ELRisk.High
        $detail = '{0} - ATTENTION : rôle(s) d''administration actif(s) : {1}, à retirer manuellement' -f $detail, ($roles -join ', ')
    }
    New-ELAction -RowContext $RowContext -Action 'DisableAccount' -Target $User.UserPrincipalName -Detail $detail -Risk $risk `
        -Parameters @{ UserId = $User.Id }
    New-ELAction -RowContext $RowContext -Action 'RevokeSessions' -Target $User.UserPrincipalName -Risk $script:ELRisk.Medium `
        -Detail 'Révocation des sessions et jetons d''actualisation en cours' -Parameters @{ UserId = $User.Id }
}

function Get-ELLeaverLicenseAction {
    <#
    .SYNOPSIS
        RemoveLicense per SKU when DateEffet + retention is reached, ScheduleLicenseRemoval otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [object] $User
    )

    $heldSkuIds = @($User.SkuIds | Where-Object { $_ })
    if ($heldSkuIds.Count -eq 0) { return }

    $retention = $State.Config.RetentionDays
    $leaveDate = $RowContext.Row.DateEffet.ToString($script:ELDateFormat)
    $removalDate = $RowContext.Row.DateEffet.AddDays($retention).Date
    if ($removalDate -le $RowContext.Today) {
        foreach ($skuId in $heldSkuIds) {
            $partNumber = Get-ELSkuPartNumber -Snapshot $State.Snapshot -SkuId $skuId
            $detail = 'Retrait de la licence « {0} » : fin de la rétention de {1} jours (départ le {2})' -f $partNumber, $retention, $leaveDate
            New-ELAction -RowContext $RowContext -Action 'RemoveLicense' -Target $partNumber -Detail $detail -Risk $script:ELRisk.Medium `
                -Parameters @{ UserId = $User.Id; SkuId = $skuId }
        }
        return
    }

    $partNumbers = @($heldSkuIds | ForEach-Object { Get-ELSkuPartNumber -Snapshot $State.Snapshot -SkuId $_ })
    $removalText = $removalDate.ToString($script:ELDateFormat)
    $detail = 'Retrait des licences prévu le {0} (départ le {1} + {2} jours de rétention) : relancer le plan à cette date' -f $removalText, $leaveDate, $retention
    New-ELAction -RowContext $RowContext -Action 'ScheduleLicenseRemoval' -Target ($partNumbers -join ', ') -Detail $detail `
        -Parameters @{ UserId = $User.Id; RemovalDate = $removalText; SkuIds = $heldSkuIds }
}
