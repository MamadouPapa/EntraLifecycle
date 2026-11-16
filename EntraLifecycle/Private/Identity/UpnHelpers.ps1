# UPN generation: prenom.nom, lowercase ASCII, deterministic collision suffixes (2, 3, ...).

# Straight, typographic and modifier apostrophes, backtick and acute accent (removed: N'Diaye -> ndiaye).
# Built from code points: typographic quotes are string delimiters in PowerShell source.
$script:ELApostrophePattern = '[{0}]' -f (-join @([char]0x0027, [char]0x0060, [char]0x00B4, [char]0x2018, [char]0x2019, [char]0x02BC))

function ConvertTo-ELUpnPart {
    <#
    .SYNOPSIS
        Normalizes a given name or surname for a UPN: "Jean Michel" -> "jean-michel", "N'Diaye" -> "ndiaye".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Text
    )

    $ascii = (ConvertTo-ELAsciiText -Text $Text).ToLowerInvariant()
    $withoutApostrophe = $ascii -replace $script:ELApostrophePattern, ''
    $hyphenated = $withoutApostrophe -replace '[\s_.]+', '-'
    $clean = $hyphenated -replace '[^a-z0-9-]', ''
    ($clean -replace '-{2,}', '-').Trim('-')
}

function Get-ELUpnStem {
    <#
    .SYNOPSIS
        Returns "prenom.nom" truncated so that a collision suffix still fits in 64 characters.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $GivenName,
        [AllowEmptyString()] [string] $Surname
    )

    $first = ConvertTo-ELUpnPart -Text $GivenName
    $last = ConvertTo-ELUpnPart -Text $Surname
    if (-not $first -or -not $last) {
        throw ('Impossible de générer un identifiant pour « {0} {1} » : prénom ou nom sans caractère exploitable' -f $GivenName, $Surname)
    }

    $stem = '{0}.{1}' -f $first, $last
    $maxLength = $script:ELUpnLocalPartMaxLength - $script:ELUpnSuffixReserve
    if ($stem.Length -gt $maxLength) {
        $stem = $stem.Substring(0, $maxLength).TrimEnd('-', '.')
    }
    $stem
}

function New-ELUserPrincipalName {
    <#
    .SYNOPSIS
        First free UPN among prenom.nom@domain, prenom.nom2@domain, ... (TakenUpn is case-insensitive).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $GivenName,
        [AllowEmptyString()] [string] $Surname,
        [Parameter(Mandatory)] [string] $Domain,
        [AllowNull()] [object] $TakenUpn
    )

    $stem = Get-ELUpnStem -GivenName $GivenName -Surname $Surname
    $suffixDomain = $Domain.ToLowerInvariant()
    for ($number = 1; $number -le $script:ELUpnMaxSuffix; $number++) {
        $suffix = ''
        if ($number -gt 1) { $suffix = [string]$number }
        $candidate = '{0}{1}@{2}' -f $stem, $suffix, $suffixDomain
        if ($null -eq $TakenUpn -or -not $TakenUpn.Contains($candidate)) { return $candidate }
    }
    throw ('Aucun UPN libre pour « {0} » après {1} essais' -f $stem, $script:ELUpnMaxSuffix)
}
