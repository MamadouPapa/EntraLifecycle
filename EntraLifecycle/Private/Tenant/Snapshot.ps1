# Tenant snapshot: the only view of the tenant the planner sees. Live mode (Graph) and demo mode
# (fixtures) both produce this exact shape, so the planning logic is identical in both modes.

function New-ELTenantUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [AllowEmptyString()] [string] $EmployeeId = '',
        [AllowEmptyString()] [string] $UserPrincipalName = '',
        [AllowEmptyString()] [string] $DisplayName = '',
        [AllowEmptyString()] [string] $Department = '',
        [AllowEmptyString()] [string] $JobTitle = '',
        [AllowEmptyString()] [string] $UsageLocation = '',
        [bool] $AccountEnabled = $true,
        [AllowEmptyString()] [string] $ManagerId = '',
        [string[]] $GroupIds = @(),
        [string[]] $SkuIds = @(),
        [string[]] $DirectoryRoles = @()
    )

    [pscustomobject]@{
        PSTypeName        = 'EntraLifecycle.TenantUser'
        Id                = $Id
        EmployeeId        = $EmployeeId
        UserPrincipalName = $UserPrincipalName
        DisplayName       = $DisplayName
        Department        = $Department
        JobTitle          = $JobTitle
        UsageLocation     = $UsageLocation
        AccountEnabled    = $AccountEnabled
        ManagerId         = $ManagerId
        GroupIds          = @($GroupIds | Where-Object { $_ })
        SkuIds            = @($SkuIds | Where-Object { $_ })
        DirectoryRoles    = @($DirectoryRoles | Where-Object { $_ })
    }
}

function New-ELSnapshot {
    <#
    .SYNOPSIS
        Users: employeeId -> TenantUser. Groups: displayName -> {Id, DisplayName}. Skus: part number -> skuId.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Users,
        [Parameter(Mandatory)] [hashtable] $Groups,
        [Parameter(Mandatory)] [hashtable] $Skus,
        [Parameter(Mandatory)] [object] $TakenUpns,
        [Parameter(Mandatory)] [object] $AmbiguousEmployeeIds
    )

    [pscustomobject]@{
        PSTypeName           = 'EntraLifecycle.Snapshot'
        Users                = $Users
        Groups               = $Groups
        Skus                 = $Skus
        TakenUpns            = $TakenUpns
        AmbiguousEmployeeIds = $AmbiguousEmployeeIds
    }
}

function Get-ELSnapshotUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Snapshot,
        [AllowEmptyString()] [string] $EmployeeId
    )

    if ($EmployeeId -and $Snapshot.Users.ContainsKey($EmployeeId)) { return $Snapshot.Users[$EmployeeId] }
    $null
}

function Get-ELSkuPartNumber {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Snapshot,
        [Parameter(Mandatory)] [string] $SkuId
    )

    foreach ($partNumber in $Snapshot.Skus.Keys) {
        if ($Snapshot.Skus[$partNumber] -eq $SkuId) { return [string]$partNumber }
    }
    $SkuId
}
