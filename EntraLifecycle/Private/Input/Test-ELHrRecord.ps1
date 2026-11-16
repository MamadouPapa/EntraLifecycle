# Validation of one HR record. Never throws: every problem is returned as a French message.

function Test-ELHrRecord {
    <#
    .SYNOPSIS
        Returns the normalized row (Mouvement canonical, DateEffet as [datetime], Role from catalog)
        and the list of problems found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Record,
        [Parameter(Mandatory)] [object] $Config,
        [Parameter(Mandatory)] [int] $Line
    )

    $fields = @{}
    foreach ($column in $script:ELRequiredColumns) {
        $fields[$column] = Get-ELRecordField -Record $Record -Name $column
    }
    $movement = ConvertTo-ELMovement -Text $fields.Mouvement
    $date = ConvertTo-ELEffectiveDate -Text $fields.DateEffet
    $role = Find-ELRole -Config $Config -Service $fields.Service -Poste $fields.Poste

    $problems = @(
        Get-ELMandatoryFieldProblem -Fields $fields
        Get-ELFormatProblem -Fields $fields -Movement $movement -Date $date
        Get-ELRoleProblem -Fields $fields -Movement $movement -Role $role
    )

    $row = [pscustomobject]@{
        PSTypeName = 'EntraLifecycle.HrRow'
        Line       = $Line
        Matricule  = $fields.Matricule
        Prenom     = $fields.Prenom
        Nom        = $fields.Nom
        Service    = $fields.Service
        Poste      = $fields.Poste
        Manager    = $fields.Manager
        DateEffet  = $date
        Mouvement  = $movement
        Role       = $role
    }
    [pscustomobject]@{ Row = $row; Problems = $problems }
}

function Get-ELRecordField {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Record,
        [Parameter(Mandatory)] [string] $Name
    )

    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    ([string]$property.Value).Trim()
}

function ConvertTo-ELMovement {
    <#
    .SYNOPSIS
        Maps "Arrivee", "Arrivée", "MUTATION", "Départ"... to the canonical value, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Text
    )

    $value = ConvertTo-ELComparableText -Text $Text
    foreach ($canonical in @($script:ELMovement.Joiner, $script:ELMovement.Mover, $script:ELMovement.Leaver)) {
        if ($value -eq $canonical.ToLowerInvariant()) { return $canonical }
    }
    $null
}

function ConvertTo-ELEffectiveDate {
    <#
    .SYNOPSIS
        Parses a strict yyyy-MM-dd date (invariant culture); returns $null when invalid.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string] $Text
    )

    $parsed = [datetime]::MinValue
    $isValid = [datetime]::TryParseExact(
        $Text,
        $script:ELDateFormat,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
    if ($isValid) { return $parsed.Date }
    $null
}

function Get-ELMandatoryFieldProblem {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [hashtable] $Fields
    )

    foreach ($name in $script:ELMandatoryFields) {
        if (-not $Fields[$name]) { 'Champ obligatoire vide : {0}' -f $name }
    }
}

function Get-ELFormatProblem {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [hashtable] $Fields,
        [AllowEmptyString()] [string] $Movement,
        [AllowNull()] [object] $Date
    )

    $matricule = $Fields.Matricule
    $manager = $Fields.Manager
    if ($matricule -and $matricule -notmatch $script:ELMatriculePattern) {
        'Matricule invalide « {0} » (lettres, chiffres, tiret ou souligné, 32 caractères maximum)' -f $matricule
    }
    if ($manager -and $manager -notmatch $script:ELMatriculePattern) {
        'Matricule du manager invalide « {0} »' -f $manager
    }
    if ($manager -and $manager -eq $matricule) {
        'Un collaborateur ne peut pas être son propre manager'
    }
    foreach ($name in @('Prenom', 'Nom')) {
        $value = $Fields[$name]
        if ($value.Length -gt $script:ELNameMaxLength) {
            '{0} trop long ({1} caractères maximum)' -f $name, $script:ELNameMaxLength
        }
        if ($value -match '[\p{Cc}<>"@;=]') {
            '{0} contient des caractères interdits' -f $name
        }
    }
    if ($Fields.Mouvement -and -not $Movement) {
        'Mouvement inconnu « {0} » (valeurs admises : Arrivee, Mutation, Depart)' -f $Fields.Mouvement
    }
    if ($Fields.DateEffet -and $null -eq $Date) {
        'Date d''effet invalide « {0} » (format attendu : aaaa-MM-jj)' -f $Fields.DateEffet
    }
}

function Get-ELRoleProblem {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [hashtable] $Fields,
        [AllowEmptyString()] [string] $Movement,
        [AllowNull()] [object] $Role
    )

    # Leavers keep whatever role they had: Service/Poste are only required for joiners and movers.
    if (@($script:ELMovement.Joiner, $script:ELMovement.Mover) -notcontains $Movement) { return }
    if (-not $Fields.Service -or -not $Fields.Poste) {
        return 'Service et Poste sont obligatoires pour une arrivée ou une mutation'
    }
    if ($null -eq $Role) {
        'Service/Poste absent du catalogue des rôles : « {0} / {1} »' -f $Fields.Service, $Fields.Poste
    }
}
