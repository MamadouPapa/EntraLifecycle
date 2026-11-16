# HR export loading: encoding and delimiter detection, column contract, per-row validation. Invalid
# rows become plan errors; only a missing/empty file or a broken column contract stops the run.

function Import-ELHrCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [object] $Config
    )

    $content = Read-ELTextFile -Path $Path -Label 'Export RH'
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "Export RH vide : $Path"
    }

    $lines = @($content -split '\r?\n')
    $headerLine = $lines[0]
    $delimiter = Get-ELCsvDelimiter -HeaderLine $headerLine
    $header = @(Get-ELCsvHeader -HeaderLine $headerLine -Delimiter $delimiter)
    Assert-ELCsvColumn -Header $header
    if (($lines.Count - 1) -gt $script:ELMaxCsvRows) {
        throw ('Export RH trop volumineux : {0} lignes au maximum par exécution' -f $script:ELMaxCsvRows)
    }

    $records = @(ConvertFrom-ELCsvLine -Lines $lines -Header $header -Delimiter $delimiter)
    ConvertTo-ELHrRows -Records $records -Config $Config -Delimiter $delimiter
}

function Read-ELTextFile {
    <#
    .SYNOPSIS
        Reads a text file as UTF-8 (BOM optional); falls back to Windows-1252 when the bytes are not
        valid UTF-8 (default "CSV" export of a French Excel).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ('{0} introuvable : {1}' -f $Label, $Path)
    }
    $fullPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $text = $strictUtf8.GetString($bytes)
    }
    catch {
        # Invalid UTF-8 sequence (DecoderFallbackException wrapped by PowerShell).
        Write-Verbose ('{0} : encodage non UTF-8, lecture en Windows-1252' -f $Label)
        $text = (Get-ELLegacyEncoding).GetString($bytes)
    }
    $text.TrimStart([char]0xFEFF)
}

function Get-ELLegacyEncoding {
    [CmdletBinding()]
    param()

    try {
        [System.Text.Encoding]::GetEncoding(1252)
    }
    catch {
        # .NET without code page provider: Latin-1 covers every French letter except oe/OE ligatures.
        [System.Text.Encoding]::GetEncoding('iso-8859-1')
    }
}

function Get-ELCsvDelimiter {
    <#
    .SYNOPSIS
        Picks ',' when the header holds more commas than semicolons, ';' otherwise (French Excel default).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $HeaderLine
    )

    $semicolons = ([regex]::Matches($HeaderLine, ';')).Count
    $commas = ([regex]::Matches($HeaderLine, ',')).Count
    if ($commas -gt $semicolons) { return ',' }
    ';'
}

function Get-ELCsvHeader {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $HeaderLine,
        [Parameter(Mandatory)] [string] $Delimiter
    )

    $names = $HeaderLine.Split([char]$Delimiter)
    for ($index = 0; $index -lt $names.Length; $index++) {
        $name = $names[$index].Trim().Trim('"').Trim()
        # ConvertFrom-Csv refuses empty header names (trailing delimiter in Excel exports).
        if (-not $name) { $name = '_colonne{0}' -f ($index + 1) }
        $name
    }
}

function Assert-ELCsvColumn {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [string[]] $Header = @()
    )

    $missing = @($script:ELRequiredColumns | Where-Object { $Header -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw ('Colonnes manquantes dans l''export RH : {0} (attendues : {1})' -f ($missing -join ', '), ($script:ELRequiredColumns -join ', '))
    }
    $duplicates = @($Header | Where-Object { $_ } | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($duplicates.Count -gt 0) {
        throw ('Colonnes en double dans l''export RH : {0}' -f ($duplicates -join ', '))
    }
}

function ConvertFrom-ELCsvLine {
    <#
    .SYNOPSIS
        Parses data lines one by one so that every record keeps its real line number in the file.
        Blank lines are skipped (but still counted).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowEmptyCollection()] [string[]] $Lines,
        [Parameter(Mandatory)] [string[]] $Header,
        [Parameter(Mandatory)] [string] $Delimiter
    )

    for ($index = 1; $index -lt $Lines.Count; $index++) {
        $text = $Lines[$index]
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $record = @($text | ConvertFrom-Csv -Delimiter $Delimiter -Header $Header) | Select-Object -First 1
        if ($null -eq $record) { continue }
        [pscustomobject]@{ Line = $index + 1; Record = $record }
    }
}

function ConvertTo-ELHrRows {
    <#
    .SYNOPSIS
        Validates parsed CSV records. Returns valid rows, row errors and the number of rows read.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [object[]] $Records = @(),
        [Parameter(Mandatory)] [object] $Config,
        [string] $Delimiter = ';'
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[object]
    $seen = New-ELNameSet
    $count = 0
    foreach ($entry in @($Records | Where-Object { $null -ne $_ })) {
        if (Test-ELBlankRecord -Record $entry.Record) { continue }
        $count++
        $check = Test-ELHrRecord -Record $entry.Record -Config $Config -Line $entry.Line
        $problems = @($check.Problems)
        $matricule = $check.Row.Matricule
        if ($matricule -and -not $seen.Add($matricule)) { $problems += 'Matricule en double dans l''export RH' }

        if ($problems.Count -eq 0) { $rows.Add($check.Row) }
        else { $errors.Add((New-ELPlanIssue -Line $entry.Line -Matricule $matricule -Message ($problems -join ' ; '))) }
    }

    [pscustomobject]@{
        Rows      = $rows.ToArray()
        Errors    = $errors.ToArray()
        RowCount  = $count
        Delimiter = $Delimiter
    }
}

function Test-ELBlankRecord {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [object] $Record
    )

    $filled = @($Record.PSObject.Properties | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Value) })
    $filled.Count -eq 0
}
