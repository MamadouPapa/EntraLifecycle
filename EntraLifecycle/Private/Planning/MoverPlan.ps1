# Mover (Mutation): converge the account to the new role. Managed groups and licenses that the new
# role does not need are removed (least privilege: no accumulation of rights across mutations).

function Get-ELMoverPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State
    )

    $row = $RowContext.Row
    $user = Get-ELSnapshotUser -Snapshot $State.Snapshot -EmployeeId $row.Matricule
    if (-not $user) {
        $message = 'Mutation impossible : aucun compte ne porte l''employeeId {0} (vérifier l''export RH ou traiter comme une arrivée)' -f $row.Matricule
        return New-ELRowResult -Errors @(New-ELRowIssue -RowContext $RowContext -Message $message)
    }

    $context = New-ELRowContext -Index $RowContext.Index -Row $row -Today $RowContext.Today -UserPrincipalName $user.UserPrincipalName
    $attributes = Get-ELAttributeAction -RowContext $context -User $user -Role $row.Role
    $groups = Get-ELGroupChange -RowContext $context -State $State -TargetGroups $row.Role.Groups -CurrentGroupIds $user.GroupIds `
        -UserId $user.Id -RemoveUnneeded -RemovalReason 'droit non requis par le nouveau rôle'
    $licenses = Get-ELLicenseChange -RowContext $context -State $State -TargetSkus $row.Role.Licenses -CurrentSkuIds $user.SkuIds `
        -UserId $user.Id -RemoveUnneeded
    $manager = Get-ELManagerChange -RowContext $context -State $State -CurrentManagerId $user.ManagerId -UserId $user.Id

    $warnings = @($groups.Warnings + $licenses.Warnings + $manager.Warnings)
    if (-not $user.AccountEnabled) {
        $warnings += New-ELRowIssue -RowContext $context -Message 'Mutation d''un compte désactivé : vérifier la situation RH'
    }
    $actions = @($attributes) + $groups.Actions + $licenses.Actions + $manager.Actions
    New-ELRowResult -Actions $actions -Warnings $warnings
}
