# Building blocks shared by the joiner, mover and leaver planners: group diff, license diff,
# attribute diff and manager change. Only catalog-managed groups and SKUs are ever removed.

function Get-ELGroupChange {
    <#
    .SYNOPSIS
        RemoveGroup for managed groups held but not targeted (when -RemoveUnneeded), then AddGroup
        for targeted groups not held. Groups missing from the tenant become warnings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State,
        [AllowEmptyCollection()] [string[]] $TargetGroups = @(),
        [AllowEmptyCollection()] [string[]] $CurrentGroupIds = @(),
        [AllowEmptyString()] [string] $UserId = '',
        [switch] $RemoveUnneeded,
        [AllowEmptyString()] [string] $RemovalReason = ''
    )

    $tenantGroups = $State.Snapshot.Groups
    $common = @{ RowContext = $RowContext; State = $State; UserId = $UserId }
    $removals = @()
    if ($RemoveUnneeded) {
        $removals = @(foreach ($name in $State.Config.ManagedGroups) {
                $group = $tenantGroups[$name]
                if ($group -and ($CurrentGroupIds -contains $group.Id) -and ($TargetGroups -notcontains $name)) {
                    New-ELGroupAction @common -Kind 'RemoveGroup' -Group $group -Reason $RemovalReason
                }
            })
    }
    $additions = @(foreach ($name in $TargetGroups) {
            $group = $tenantGroups[$name]
            if ($group -and ($CurrentGroupIds -notcontains $group.Id)) {
                New-ELGroupAction @common -Kind 'AddGroup' -Group $group -Reason ''
            }
        })
    $warnings = @(foreach ($name in $TargetGroups) {
            if (-not $tenantGroups.ContainsKey($name)) {
                New-ELRowIssue -RowContext $RowContext -Message ('Groupe « {0} » introuvable dans le tenant : ajout ignoré' -f $name)
            }
        })
    New-ELRowResult -Actions ($removals + $additions) -Warnings $warnings
}

function New-ELGroupAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [ValidateSet('AddGroup', 'RemoveGroup')] [string] $Kind,
        [Parameter(Mandatory)] [object] $Group,
        [AllowEmptyString()] [string] $UserId = '',
        [AllowEmptyString()] [string] $Reason = ''
    )

    $isPrivileged = $State.Config.PrivilegedGroups -contains $Group.DisplayName
    $risk = $script:ELRisk.Low
    if ($Kind -eq 'RemoveGroup') { $risk = $script:ELRisk.Medium }
    if ($isPrivileged) { $risk = $script:ELRisk.High }

    $verb = 'Retrait du groupe'
    if ($Kind -eq 'AddGroup') { $verb = 'Ajout au groupe' }
    $detail = '{0} « {1} »' -f $verb, $Group.DisplayName
    if ($Reason) { $detail = '{0} ({1})' -f $detail, $Reason }
    if ($isPrivileged) { $detail = '{0} - groupe à privilèges' -f $detail }

    New-ELAction -RowContext $RowContext -Action $Kind -Target $Group.DisplayName -Detail $detail -Risk $risk `
        -Parameters @{ GroupId = $Group.Id; UserId = $UserId }
}

function Get-ELLicenseChange {
    <#
    .SYNOPSIS
        AssignLicense for targeted SKUs not held, then RemoveLicense for managed SKUs no longer needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State,
        [AllowEmptyCollection()] [string[]] $TargetSkus = @(),
        [AllowEmptyCollection()] [string[]] $CurrentSkuIds = @(),
        [AllowEmptyString()] [string] $UserId = '',
        [switch] $RemoveUnneeded
    )

    $skus = $State.Snapshot.Skus
    $additions = @(foreach ($partNumber in $TargetSkus) {
            if ($skus.ContainsKey($partNumber) -and ($CurrentSkuIds -notcontains $skus[$partNumber])) {
                New-ELAction -RowContext $RowContext -Action 'AssignLicense' -Target $partNumber `
                    -Detail ('Attribution de la licence « {0} »' -f $partNumber) `
                    -Parameters @{ UserId = $UserId; SkuId = $skus[$partNumber] }
            }
        })
    $removals = @()
    if ($RemoveUnneeded) {
        $removals = @(foreach ($partNumber in $State.Config.ManagedSkus) {
                $isHeld = $skus.ContainsKey($partNumber) -and ($CurrentSkuIds -contains $skus[$partNumber])
                if ($isHeld -and ($TargetSkus -notcontains $partNumber)) {
                    New-ELAction -RowContext $RowContext -Action 'RemoveLicense' -Target $partNumber -Risk $script:ELRisk.Medium `
                        -Detail ('Retrait de la licence « {0} » (non requise par le nouveau rôle)' -f $partNumber) `
                        -Parameters @{ UserId = $UserId; SkuId = $skus[$partNumber] }
                }
            })
    }
    $warnings = @(foreach ($partNumber in $TargetSkus) {
            if (-not $skus.ContainsKey($partNumber)) {
                New-ELRowIssue -RowContext $RowContext -Message ('Licence « {0} » absente des abonnements du tenant : attribution ignorée' -f $partNumber)
            }
        })
    New-ELRowResult -Actions ($additions + $removals) -Warnings $warnings
}

function Get-ELAttributeAction {
    <#
    .SYNOPSIS
        UpdateAttributes when department, jobTitle or usageLocation differ from the target role.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $User,
        [Parameter(Mandatory)] [object] $Role
    )

    $desired = [ordered]@{ department = $Role.Department; jobTitle = $Role.JobTitle; usageLocation = $Role.UsageLocation }
    $current = @{ department = $User.Department; jobTitle = $User.JobTitle; usageLocation = $User.UsageLocation }
    $body = @{}
    $changes = @(foreach ($key in $desired.Keys) {
            if ([string]$current[$key] -cne [string]$desired[$key]) {
                $body[$key] = $desired[$key]
                '{0} : « {1} » → « {2} »' -f $key, $current[$key], $desired[$key]
            }
        })
    if ($changes.Count -eq 0) { return }

    New-ELAction -RowContext $RowContext -Action 'UpdateAttributes' -Target $User.UserPrincipalName `
        -Detail ('Mise à jour : {0}' -f ($changes -join ' ; ')) -Parameters @{ UserId = $User.Id; Body = $body }
}

function Get-ELManagerChange {
    <#
    .SYNOPSIS
        SetManager when the HR manager differs from the current one. The manager may be an existing
        account or a joiner created by the same plan (resolved at apply time).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $RowContext,
        [Parameter(Mandatory)] [object] $State,
        [AllowEmptyString()] [string] $CurrentManagerId = '',
        [AllowEmptyString()] [string] $UserId = ''
    )

    $managerMatricule = $RowContext.Row.Manager
    if (-not $managerMatricule) { return New-ELRowResult }

    $manager = Get-ELSnapshotUser -Snapshot $State.Snapshot -EmployeeId $managerMatricule
    $parameters = @{ UserId = $UserId; ManagerId = ''; ManagerMatricule = $managerMatricule }
    if ($manager) {
        if ($CurrentManagerId -and $CurrentManagerId -eq $manager.Id) { return New-ELRowResult }
        $parameters.ManagerId = $manager.Id
        $detail = 'Rattachement au manager {0} ({1})' -f $manager.DisplayName, $managerMatricule
        return New-ELRowResult -Actions @(New-ELAction -RowContext $RowContext -Action 'SetManager' -Target $manager.UserPrincipalName -Detail $detail -Parameters $parameters)
    }
    if ($State.JoinerMatricules.Contains($managerMatricule)) {
        $detail = 'Rattachement au manager {0} (compte créé par ce même plan)' -f $managerMatricule
        return New-ELRowResult -Actions @(New-ELAction -RowContext $RowContext -Action 'SetManager' -Target $managerMatricule -Detail $detail -Parameters $parameters)
    }
    $message = 'Manager « {0} » introuvable (ni dans le tenant, ni parmi les arrivées du plan) : rattachement ignoré' -f $managerMatricule
    New-ELRowResult -Warnings @(New-ELRowIssue -RowContext $RowContext -Message $message)
}
