<#
.SYNOPSIS
    Full demo on the fictional tenant (contoso.example), without any Microsoft Graph connection:
    plan -> text plan -> HTML report -> apply -> JSONL audit log.

.PARAMETER OutputDirectory
    Folder receiving demo-plan.txt, demo-report.html and demo-audit.jsonl. Default: ./docs

.PARAMETER ReferenceDate
    Reference date of the plan (default 2026-11-16, the date the sample HR export was built for).

.EXAMPLE
    pwsh ./scripts/Invoke-Demo.ps1
#>
[CmdletBinding()]
param(
    [string] $OutputDirectory,
    [string] $ReferenceDate = '2026-11-16'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'docs' }
$referenceDay = [datetime]::ParseExact($ReferenceDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
[void][System.IO.Directory]::CreateDirectory($OutputDirectory)

Import-Module (Join-Path $root 'EntraLifecycle/EntraLifecycle.psd1') -Force

$plan = Get-ELPlan -CsvPath (Join-Path $root 'samples/rh-export-demo.csv') -ConfigPath (Join-Path $root 'config/roles.json') `
    -DemoMode -ReferenceDate $referenceDay

$textPath = Join-Path $OutputDirectory 'demo-plan.txt'
$lines = @($plan | Format-ELPlan)
[System.IO.File]::WriteAllText($textPath, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
$lines | ForEach-Object { Write-Host $_ }

$report = $plan | Export-ELPlanReport -OutputPath (Join-Path $OutputDirectory 'demo-report.html')

$auditPath = Join-Path $OutputDirectory 'demo-audit.jsonl'
if (Test-Path -LiteralPath $auditPath) { Remove-Item -LiteralPath $auditPath -Force }
$result = Invoke-ELPlan -Plan $plan -AuditLogPath $auditPath -Confirm:$false

Write-Host ''
Write-Host ('Rapport HTML : {0}' -f $report.FullName)
Write-Host ('Journal d''audit : {0} ({1} succès, {2} échec(s))' -f $result.AuditLogPath, $result.Succeeded, $result.Failed)
Write-Host ('Temporary Access Pass remis : {0} (SecureString, jamais journalisés)' -f @($result.Handoffs).Count)

[pscustomobject]@{
    PlanTextPath = $textPath
    ReportPath   = $report.FullName
    AuditLogPath = $result.AuditLogPath
    Plan         = $plan
    Result       = $result
}
