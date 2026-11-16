# HTML primitives. Every value coming from the HR export or the tenant MUST go through ConvertTo-ELHtml.
# CSS class names are only ever chosen from fixed internal values, never from data.

function ConvertTo-ELHtml {
    <#
    .SYNOPSIS
        HTML-encodes any value (neutralizes markup injected through HR data or directory names).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)] [AllowNull()] [object] $Value
    )

    if ($null -eq $Value) { return '' }
    [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-ELRiskClass {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Risk
    )

    if ($Risk -eq $script:ELRisk.High) { return 'risk-high' }
    if ($Risk -eq $script:ELRisk.Medium) { return 'risk-medium' }
    'risk-low'
}

function ConvertTo-ELHtmlCell {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [object] $Value,
        [switch] $Numeric
    )

    $classAttribute = ''
    if ($Numeric) { $classAttribute = ' class="num"' }
    '<td' + $classAttribute + '>' + (ConvertTo-ELHtml -Value $Value) + '</td>'
}

function ConvertTo-ELRiskCell {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Risk
    )

    '<td><span class="risk ' + (Get-ELRiskClass -Risk $Risk) + '">' + (ConvertTo-ELHtml -Value $Risk) + '</span></td>'
}

function ConvertTo-ELHtmlTable {
    <#
    .SYNOPSIS
        Wraps pre-built (already encoded) <tr> rows in a table, or shows an encoded empty message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string[]] $Header,
        [AllowEmptyCollection()] [string[]] $Rows = @(),
        [Parameter(Mandatory)] [string] $EmptyText
    )

    if (@($Rows).Count -eq 0) { return '<p class="empty">' + (ConvertTo-ELHtml -Value $EmptyText) + '</p>' }
    $headCells = ($Header | ForEach-Object { '<th>' + (ConvertTo-ELHtml -Value $_) + '</th>' }) -join ''
    '<div class="table-wrap"><table><thead><tr>' + $headCells + '</tr></thead><tbody>' + ($Rows -join '') + '</tbody></table></div>'
}

function ConvertTo-ELHtmlSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Body
    )

    '<section><h2>' + (ConvertTo-ELHtml -Value $Title) + '</h2>' + $Body + '</section>'
}
