# Shared constants. Identifiers stay in English; every label shown to operators is French.

# Canonical HR movement values (as found in the HR export).
$script:ELMovement = [pscustomobject]@{
    Joiner = 'Arrivee'
    Mover  = 'Mutation'
    Leaver = 'Depart'
}

$script:ELMovementLabel = @{
    Arrivee  = 'Arrivée'
    Mutation = 'Mutation'
    Depart   = 'Départ'
}

$script:ELRisk = [pscustomobject]@{
    Low    = 'Faible'
    Medium = 'Moyen'
    High   = 'Élevé'
}

$script:ELStatus = [pscustomobject]@{
    Ready    = 'À appliquer'
    Deferred = 'Différé'
}

$script:ELResult = [pscustomobject]@{
    Success    = 'Succès'
    Failure    = 'Échec'
    Cancelled  = 'Annulé'
    Deferred   = 'Différé'
    Scheduled  = 'Planifié'
    Skipped    = 'Ignoré'
    NotApplied = 'Non appliqué'
}

# Action catalog, in the order used by reports.
$script:ELActionLabel = [ordered]@{
    CreateUser               = 'Création du compte'
    SkipExisting             = 'Compte déjà existant'
    UpdateAttributes         = 'Mise à jour des attributs'
    DisableAccount           = 'Désactivation du compte'
    RevokeSessions           = 'Révocation des sessions'
    RemoveGroup              = 'Retrait d''un groupe'
    AddGroup                 = 'Ajout à un groupe'
    AssignLicense            = 'Attribution de licence'
    RemoveLicense            = 'Retrait de licence'
    ScheduleLicenseRemoval   = 'Retrait de licence planifié'
    SetManager               = 'Rattachement au manager'
    IssueTemporaryAccessPass = 'Émission d''un Temporary Access Pass'
}

# Terraform-like symbols used by Format-ELPlan: + grant/create, ~ change, - revoke/remove, . informational.
$script:ELActionSymbol = @{
    CreateUser               = '+'
    AddGroup                 = '+'
    AssignLicense            = '+'
    IssueTemporaryAccessPass = '+'
    UpdateAttributes         = '~'
    SetManager               = '~'
    DisableAccount           = '-'
    RevokeSessions           = '-'
    RemoveGroup              = '-'
    RemoveLicense            = '-'
    SkipExisting             = '.'
    ScheduleLicenseRemoval   = '.'
}

# HR export contract.
$script:ELRequiredColumns = @('Matricule', 'Prenom', 'Nom', 'Service', 'Poste', 'Manager', 'DateEffet', 'Mouvement')
$script:ELMandatoryFields = @('Matricule', 'Prenom', 'Nom', 'DateEffet', 'Mouvement')
$script:ELDateFormat = 'yyyy-MM-dd'
$script:ELMaxCsvRows = 5000
$script:ELNameMaxLength = 64
$script:ELMaxRetentionDays = 3650
# Matricules are also used inside OData filters: keep them to a strict, quote-free alphabet.
$script:ELMatriculePattern = '^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$'
$script:ELDomainPattern = '^(?=.{4,253}$)([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$'
$script:ELUsageLocationPattern = '^[A-Za-z]{2}$'
$script:ELDefaultUsageLocation = 'FR'

# UPN generation.
$script:ELUpnLocalPartMaxLength = 64
$script:ELUpnSuffixReserve = 2
$script:ELUpnMaxSuffix = 99

# Credentials.
$script:ELTapLifetimeMinutes = 480
$script:ELTapIsUsableOnce = $true
$script:ELGeneratedPasswordLength = 32
$script:ELMinutesPerHour = 60

# Apply safety.
$script:ELPlanMaxAgeHours = 24

# Microsoft Graph.
$script:ELGraphUserRefBase = 'https://graph.microsoft.com/v1.0/users/'
$script:ELUserProperties = @('id', 'displayName', 'userPrincipalName', 'employeeId', 'department', 'jobTitle', 'usageLocation', 'accountEnabled')
$script:ELODataGroupType = '#microsoft.graph.group'
$script:ELODataRoleType = '#microsoft.graph.directoryRole'
