# Live tenant: read-only Microsoft Graph queries (Get-Mg* only) scoped to the matricules, managers,
# catalog groups and UPN stems that the HR export actually references.

function Assert-ELGraphConnection {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-MgContext' -ErrorAction SilentlyContinue)) {
        throw 'Module Microsoft.Graph introuvable : Install-Module Microsoft.Graph -Scope CurrentUser, ou utilisez -DemoMode.'
    }
    if (-not (Get-MgContext)) {
        throw 'Aucune session Microsoft Graph : exécutez Connect-MgGraph avec les permissions documentées dans le README, ou utilisez -DemoMode.'
    }
}

function Get-ELLiveSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Import,
        [Parameter(Mandatory)] [object] $Config
    )

    Assert-ELGraphConnection
    $groups = Get-ELLiveGroupMap -Names $Config.ManagedGroups
    $skus = Get-ELLiveSkuMap
    $users = @{}
    $ambiguous = New-ELNameSet

    $employeeIds = Get-ELUniqueList -Values @($Import.Rows | ForEach-Object { $_.Matricule; $_.Manager })
    foreach ($employeeId in $employeeIds) {
        $found = @(Find-ELLiveUser -EmployeeId $employeeId)
        if ($found.Count -gt 1) { [void]$ambiguous.Add($employeeId); continue }
        if ($found.Count -eq 1) { $users[$employeeId] = ConvertTo-ELLiveTenantUser -User $found[0] }
    }

    $taken = Get-ELLiveTakenUpn -Import $Import -Users $users
    New-ELSnapshot -Users $users -Groups $groups -Skus $skus -TakenUpns $taken -AmbiguousEmployeeIds $ambiguous
}

function Get-ELLiveGroupMap {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [string[]] $Names = @()
    )

    $map = @{}
    foreach ($name in $Names) {
        $filter = "displayName eq '{0}'" -f (ConvertTo-ELODataLiteral -Value $name)
        $found = @(Get-MgGroup -Filter $filter -Property @('id', 'displayName') -All -ErrorAction Stop)
        if ($found.Count -eq 1) {
            $map[$name] = [pscustomobject]@{ Id = [string]$found[0].Id; DisplayName = $name }
        }
        elseif ($found.Count -gt 1) {
            Write-Warning ('Plusieurs groupes se nomment « {0} » : groupe ignoré, utilisez un nom unique.' -f $name)
        }
    }
    $map
}

function Get-ELLiveSkuMap {
    [CmdletBinding()]
    param()

    $map = @{}
    foreach ($sku in @(Get-MgSubscribedSku -All -ErrorAction Stop)) {
        $map[[string]$sku.SkuPartNumber] = [string]$sku.SkuId
    }
    $map
}

function Find-ELLiveUser {
    <#
    .SYNOPSIS
        Users whose employeeId equals the matricule (the matricule format is validated upstream).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $EmployeeId
    )

    $filter = "employeeId eq '{0}'" -f (ConvertTo-ELODataLiteral -Value $EmployeeId)
    @(Get-MgUser -Filter $filter -Property $script:ELUserProperties -All -ErrorAction Stop)
}

function ConvertTo-ELLiveTenantUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $User
    )

    $memberships = @(Get-MgUserMemberOf -UserId $User.Id -All -ErrorAction Stop)
    $groupIds = @($memberships | Where-Object { (Get-ELODataType -Object $_) -eq $script:ELODataGroupType } | ForEach-Object { [string]$_.Id })
    $roles = @($memberships | Where-Object { (Get-ELODataType -Object $_) -eq $script:ELODataRoleType } |
            ForEach-Object { [string](Get-ELAdditionalProperty -Object $_ -Name 'displayName') })
    $skuIds = @(Get-MgUserLicenseDetail -UserId $User.Id -All -ErrorAction Stop | ForEach-Object { [string]$_.SkuId })

    New-ELTenantUser -Id ([string]$User.Id) -EmployeeId ([string]$User.EmployeeId) `
        -UserPrincipalName ([string]$User.UserPrincipalName) -DisplayName ([string]$User.DisplayName) `
        -Department ([string]$User.Department) -JobTitle ([string]$User.JobTitle) `
        -UsageLocation ([string]$User.UsageLocation) -AccountEnabled ([bool]$User.AccountEnabled) `
        -ManagerId (Get-ELLiveManagerId -UserId ([string]$User.Id)) `
        -GroupIds $groupIds -SkuIds $skuIds -DirectoryRoles $roles
}

function Get-ELLiveManagerId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $UserId
    )

    try {
        $manager = Get-MgUserManager -UserId $UserId -ErrorAction Stop
        if ($manager) { return [string]$manager.Id }
    }
    catch {
        # Graph answers 404 when no manager is set: treated as "no manager".
        Write-Verbose ('Aucun manager lu pour {0} : {1}' -f $UserId, $_.Exception.Message)
    }
    ''
}

function Get-ELLiveTakenUpn {
    <#
    .SYNOPSIS
        UPNs already used in the tenant for the stems of new joiners (startswith filter).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Import,
        [Parameter(Mandatory)] [hashtable] $Users
    )

    $taken = New-ELNameSet
    $newJoiners = @($Import.Rows | Where-Object { $_.Mouvement -eq $script:ELMovement.Joiner -and -not $Users.ContainsKey($_.Matricule) })
    foreach ($row in $newJoiners) {
        try {
            $stem = Get-ELUpnStem -GivenName $row.Prenom -Surname $row.Nom
        }
        catch {
            # Unusable name: the planner reports it as a row error.
            Write-Verbose $_.Exception.Message
            continue
        }
        $filter = "startswith(userPrincipalName,'{0}')" -f (ConvertTo-ELODataLiteral -Value $stem)
        foreach ($user in @(Get-MgUser -Filter $filter -Property @('userPrincipalName') -All -ErrorAction Stop)) {
            [void]$taken.Add([string]$user.UserPrincipalName)
        }
    }
    , $taken
}

function Get-ELODataType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Object
    )

    [string](Get-ELAdditionalProperty -Object $Object -Name '@odata.type')
}

function Get-ELAdditionalProperty {
    <#
    .SYNOPSIS
        Reads a key from the AdditionalProperties dictionary that Graph SDK directory objects expose.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Object,
        [Parameter(Mandatory)] [string] $Name
    )

    $bag = $Object.AdditionalProperties
    if ($null -eq $bag) { return $null }
    if ($bag.ContainsKey($Name)) { return $bag[$Name] }
    $null
}
