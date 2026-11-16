# Role catalog (config/roles.json): Service + Poste -> groups, licenses, attributes; plus global settings.

function Import-ELConfig {
    <#
    .SYNOPSIS
        Loads and validates the role catalog. Throws one French message listing every problem found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    $data = Read-ELJsonFile -Path $Path -Label 'Catalogue de rôles'
    $problems = @(Test-ELConfigData -Data $data)
    if ($problems.Count -gt 0) {
        throw ('Catalogue de rôles invalide ({0}) : {1}' -f $Path, ($problems -join ' ; '))
    }
    ConvertTo-ELConfig -Data $data
}

function Test-ELConfigData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Data
    )

    $settings = $Data.settings
    if ($null -eq $settings) { return 'section « settings » absente' }

    if ([string]$settings.upnDomain -notmatch $script:ELDomainPattern) {
        'settings.upnDomain absent ou invalide'
    }
    $retention = [string]$settings.leaverLicenseRetentionDays
    if ($retention -notmatch '^\d{1,4}$' -or [int]$retention -gt $script:ELMaxRetentionDays) {
        'settings.leaverLicenseRetentionDays doit être un entier entre 0 et {0}' -f $script:ELMaxRetentionDays
    }
    if ($settings.defaultUsageLocation -and [string]$settings.defaultUsageLocation -notmatch $script:ELUsageLocationPattern) {
        'settings.defaultUsageLocation doit être un code pays à deux lettres'
    }

    $roles = @($Data.roles | Where-Object { $null -ne $_ })
    if ($roles.Count -eq 0) { 'aucun rôle défini dans « roles »' }

    $keys = New-ELNameSet
    $index = 0
    foreach ($role in $roles) {
        $index++
        Test-ELRoleData -Role $role -Index $index
        $key = Get-ELRoleKey -Service $role.service -Poste $role.poste
        if (-not $keys.Add($key)) { 'rôle n°{0} : couple Service/Poste en double' -f $index }
    }
}

function Test-ELRoleData {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Role,
        [Parameter(Mandatory)] [int] $Index
    )

    if ([string]::IsNullOrWhiteSpace([string]$Role.service) -or [string]::IsNullOrWhiteSpace([string]$Role.poste)) {
        'rôle n°{0} : « service » et « poste » sont obligatoires' -f $Index
    }
    foreach ($listName in @('groups', 'licenses')) {
        $list = $Role.$listName
        if ($null -eq $list) {
            'rôle n°{0} : liste « {1} » absente' -f $Index, $listName
            continue
        }
        $invalid = @(@($list) | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) })
        if ($invalid.Count -gt 0) { 'rôle n°{0} : « {1} » ne doit contenir que des noms non vides' -f $Index, $listName }
    }
    if ($Role.usageLocation -and [string]$Role.usageLocation -notmatch $script:ELUsageLocationPattern) {
        'rôle n°{0} : « usageLocation » doit être un code pays à deux lettres' -f $Index
    }
}

function ConvertTo-ELConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Data
    )

    $settings = $Data.settings
    $defaultLocation = $script:ELDefaultUsageLocation
    if ($settings.defaultUsageLocation) { $defaultLocation = ([string]$settings.defaultUsageLocation).ToUpperInvariant() }

    $roles = @($Data.roles | ForEach-Object { ConvertTo-ELRole -Role $_ -DefaultUsageLocation $defaultLocation })

    [pscustomobject]@{
        PSTypeName           = 'EntraLifecycle.Config'
        UpnDomain            = ([string]$settings.upnDomain).ToLowerInvariant()
        RetentionDays        = [int]$settings.leaverLicenseRetentionDays
        DefaultUsageLocation = $defaultLocation
        PrivilegedGroups     = @(Get-ELUniqueList -Values @($settings.privilegedGroups))
        Roles                = $roles
        ManagedGroups        = @(Get-ELUniqueList -Values @($roles | ForEach-Object { $_.Groups }))
        ManagedSkus          = @(Get-ELUniqueList -Values @($roles | ForEach-Object { $_.Licenses }))
    }
}

function ConvertTo-ELRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Role,
        [Parameter(Mandatory)] [string] $DefaultUsageLocation
    )

    $service = ([string]$Role.service).Trim()
    $poste = ([string]$Role.poste).Trim()
    $department = $service
    if ($Role.department) { $department = ([string]$Role.department).Trim() }
    $jobTitle = $poste
    if ($Role.jobTitle) { $jobTitle = ([string]$Role.jobTitle).Trim() }
    $usageLocation = $DefaultUsageLocation
    if ($Role.usageLocation) { $usageLocation = ([string]$Role.usageLocation).ToUpperInvariant() }

    [pscustomobject]@{
        PSTypeName    = 'EntraLifecycle.Role'
        Service       = $service
        Poste         = $poste
        Key           = Get-ELRoleKey -Service $service -Poste $poste
        Department    = $department
        JobTitle      = $jobTitle
        UsageLocation = $usageLocation
        Groups        = @(Get-ELUniqueList -Values @($Role.groups))
        Licenses      = @(Get-ELUniqueList -Values @($Role.licenses))
    }
}

function Get-ELRoleKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Service,
        [AllowEmptyString()] [string] $Poste
    )

    '{0}|{1}' -f (ConvertTo-ELComparableText -Text $Service), (ConvertTo-ELComparableText -Text $Poste)
}

function Find-ELRole {
    <#
    .SYNOPSIS
        Returns the catalog role for Service + Poste (case and accent insensitive), or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Config,
        [AllowEmptyString()] [string] $Service,
        [AllowEmptyString()] [string] $Poste
    )

    if ([string]::IsNullOrWhiteSpace($Service) -or [string]::IsNullOrWhiteSpace($Poste)) { return $null }
    $key = Get-ELRoleKey -Service $Service -Poste $Poste
    foreach ($role in $Config.Roles) {
        if ($role.Key -eq $key) { return $role }
    }
    $null
}

function Copy-ELConfigWithDomain {
    <#
    .SYNOPSIS
        Returns a copy of the configuration using another UPN domain (demo tenant).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Config,
        [Parameter(Mandatory)] [string] $Domain
    )

    $copy = $Config.PSObject.Copy()
    $copy.UpnDomain = $Domain.ToLowerInvariant()
    $copy
}
