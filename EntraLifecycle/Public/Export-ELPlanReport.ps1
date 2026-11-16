function Export-ELPlanReport {
    <#
    .SYNOPSIS
        Writes a self-contained HTML report of a plan (inline CSS, no script, every value encoded).

    .PARAMETER Plan
        Output of Get-ELPlan.

    .PARAMETER OutputPath
        HTML file to create (parent folders are created when needed).

    .EXAMPLE
        Get-ELPlan -CsvPath .\samples\rh-export-demo.csv -ConfigPath .\config\roles.json -DemoMode |
            Export-ELPlanReport -OutputPath .\docs\plan-demo.html
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [object] $Plan,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    process {
        Assert-ELPlan -Plan $Plan
        $html = ConvertTo-ELPlanHtml -Plan $Plan
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        $directory = Split-Path -Path $fullPath -Parent
        if ($directory) { [void][System.IO.Directory]::CreateDirectory($directory) }
        [System.IO.File]::WriteAllText($fullPath, $html, (New-Object System.Text.UTF8Encoding($false)))
        Get-Item -LiteralPath $fullPath
    }
}
