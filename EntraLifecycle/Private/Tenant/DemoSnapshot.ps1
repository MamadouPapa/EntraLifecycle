# Demo tenant: builds the snapshot from Data/demo-tenant.json (fake domain contoso.example).
# Fixture users reference groups and licenses by name for readability.

function ConvertTo-ELFixtureSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Fixture
    )

    $groups = @{}
    foreach ($group in @($Fixture.groups | Where-Object { $null -ne $_ })) {
        $groups[[string]$group.displayName] = [pscustomobject]@{ Id = [string]$group.id; DisplayName = [string]$group.displayName }
    }
    $skus = @{}
    foreach ($sku in @($Fixture.skus | Where-Object { $null -ne $_ })) {
        $skus[[string]$sku.skuPartNumber] = [string]$sku.skuId
    }

    $fixtureUsers = @($Fixture.users | Where-Object { $null -ne $_ })
    $idByEmployeeId = @{}
    foreach ($user in $fixtureUsers) {
        if ($user.employeeId) { $idByEmployeeId[[string]$user.employeeId] = [string]$user.id }
    }

    $users = @{}
    foreach ($user in ($fixtureUsers | Where-Object { $_.employeeId })) {
        $users[[string]$user.employeeId] = ConvertTo-ELFixtureUser -User $user -Groups $groups -Skus $skus -IdByEmployeeId $idByEmployeeId
    }

    New-ELSnapshot -Users $users -Groups $groups -Skus $skus `
        -TakenUpns (New-ELNameSet -Values @($fixtureUsers | ForEach-Object { $_.userPrincipalName })) `
        -AmbiguousEmployeeIds (New-ELNameSet)
}

function ConvertTo-ELFixtureUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $User,
        [Parameter(Mandatory)] [hashtable] $Groups,
        [Parameter(Mandatory)] [hashtable] $Skus,
        [Parameter(Mandatory)] [hashtable] $IdByEmployeeId
    )

    $groupIds = @(foreach ($name in @($User.groups | Where-Object { $_ })) {
            if ($Groups.ContainsKey([string]$name)) { $Groups[[string]$name].Id }
        })
    $skuIds = @(foreach ($partNumber in @($User.licenses | Where-Object { $_ })) {
            if ($Skus.ContainsKey([string]$partNumber)) { $Skus[[string]$partNumber] }
        })
    $managerId = ''
    if ($User.managerEmployeeId -and $IdByEmployeeId.ContainsKey([string]$User.managerEmployeeId)) {
        $managerId = $IdByEmployeeId[[string]$User.managerEmployeeId]
    }
    $isEnabled = $true
    if ($null -ne $User.accountEnabled) { $isEnabled = [bool]$User.accountEnabled }

    New-ELTenantUser -Id ([string]$User.id) -EmployeeId ([string]$User.employeeId) `
        -UserPrincipalName ([string]$User.userPrincipalName) -DisplayName ([string]$User.displayName) `
        -Department ([string]$User.department) -JobTitle ([string]$User.jobTitle) `
        -UsageLocation ([string]$User.usageLocation) -AccountEnabled $isEnabled -ManagerId $managerId `
        -GroupIds $groupIds -SkuIds $skuIds -DirectoryRoles @($User.directoryRoles | Where-Object { $_ })
}
