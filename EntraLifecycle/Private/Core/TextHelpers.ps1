# Text helpers shared by UPN generation, role lookup, OData filters and JSON loading.

# Characters that Unicode decomposition does not reduce to ASCII. Written as code points so the
# table does not depend on the file encoding.
$script:ELTransliteration = @(
    @([char]0x0153, 'oe'), @([char]0x0152, 'OE'),
    @([char]0x00E6, 'ae'), @([char]0x00C6, 'AE'),
    @([char]0x00DF, 'ss'),
    @([char]0x00F8, 'o'), @([char]0x00D8, 'O'),
    @([char]0x0142, 'l'), @([char]0x0141, 'L'),
    @([char]0x0111, 'd'), @([char]0x0110, 'D')
)

function ConvertTo-ELAsciiText {
    <#
    .SYNOPSIS
        Removes diacritics ("Élodie Gérard" -> "Elodie Gerard") and transliterates ligatures.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyString()] [string] $Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }

    $value = $Text
    foreach ($pair in $script:ELTransliteration) {
        $value = $value.Replace([string]$pair[0], [string]$pair[1])
    }

    $decomposed = $value.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $decomposed.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    $builder.ToString().Normalize([System.Text.NormalizationForm]::FormC)
}

function ConvertTo-ELComparableText {
    <#
    .SYNOPSIS
        Case-, accent- and whitespace-insensitive form used for catalog keys and enum values.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyString()] [string] $Text
    )

    ((ConvertTo-ELAsciiText -Text $Text).Trim() -replace '\s+', ' ').ToLowerInvariant()
}

function ConvertTo-ELODataLiteral {
    <#
    .SYNOPSIS
        Escapes a value for use inside a single-quoted OData string literal.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Value
    )

    $Value.Replace("'", "''")
}

function Get-ELUniqueList {
    <#
    .SYNOPSIS
        Returns trimmed, non-empty strings without case-insensitive duplicates, keeping first-seen order.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [object[]] $Values
    )

    $seen = New-ELNameSet
    foreach ($value in @($Values)) {
        $text = ([string]$value).Trim()
        if ($text -and $seen.Add($text)) { $text }
    }
}

function New-ELNameSet {
    <#
    .SYNOPSIS
        Case-insensitive string set (UPNs, matricules). Returned with the comma operator so that
        PowerShell does not unroll it.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] [object[]] $Values
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($Values)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) { [void]$set.Add([string]$value) }
    }
    , $set
}

function Read-ELJsonFile {
    <#
    .SYNOPSIS
        Reads a UTF-8 JSON file with French error messages for missing or malformed files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ('{0} introuvable : {1}' -f $Label, $Path)
    }
    $raw = [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    try {
        $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw ('{0} : JSON invalide ({1})' -f $Label, $_.Exception.Message)
    }
}
