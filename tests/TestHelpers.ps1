# Shared test helpers: paths, Microsoft Graph cmdlet stubs (so that Pester can mock them on machines
# without the Graph SDK) and small factories for HR exports.

$ELTestRoot = Split-Path -Path $PSScriptRoot -Parent
$ELTestModulePath = Join-Path $ELTestRoot 'EntraLifecycle/EntraLifecycle.psd1'
$ELTestConfigPath = Join-Path $ELTestRoot 'config/roles.json'
$ELTestCsvPath = Join-Path $ELTestRoot 'samples/rh-export-demo.csv'
$ELTestReferenceDate = [datetime]::ParseExact('2026-11-16', 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
$ELTestHeader = 'Matricule;Prenom;Nom;Service;Poste;Manager;DateEffet;Mouvement'

# --- Graph cmdlet stubs (never called for real: every test mocks what it uses) ---------------------
function global:Get-MgContext { [CmdletBinding()] param() }
function global:Get-MgUser { [CmdletBinding()] param($Filter, $Property, [switch] $All, $UserId) }
function global:Get-MgGroup { [CmdletBinding()] param($Filter, $Property, [switch] $All) }
function global:Get-MgSubscribedSku { [CmdletBinding()] param([switch] $All) }
function global:Get-MgUserMemberOf { [CmdletBinding()] param($UserId, [switch] $All) }
function global:Get-MgUserLicenseDetail { [CmdletBinding()] param($UserId, [switch] $All) }
function global:Get-MgUserManager { [CmdletBinding()] param($UserId) }
function global:New-MgUser { [CmdletBinding(SupportsShouldProcess)] param($BodyParameter) }
function global:Update-MgUser { [CmdletBinding(SupportsShouldProcess)] param($UserId, $BodyParameter) }
function global:Revoke-MgUserSignInSession { [CmdletBinding(SupportsShouldProcess)] param($UserId) }
function global:New-MgGroupMember { [CmdletBinding(SupportsShouldProcess)] param($GroupId, $DirectoryObjectId) }
function global:Remove-MgGroupMemberByRef { [CmdletBinding(SupportsShouldProcess)] param($GroupId, $DirectoryObjectId) }
function global:Set-MgUserLicense { [CmdletBinding(SupportsShouldProcess)] param($UserId, $AddLicenses, $RemoveLicenses) }
function global:Set-MgUserManagerByRef { [CmdletBinding(SupportsShouldProcess)] param($UserId, $BodyParameter) }
function global:New-MgUserAuthenticationTemporaryAccessPassMethod { [CmdletBinding(SupportsShouldProcess)] param($UserId, $BodyParameter) }

# --- Factories ------------------------------------------------------------------------------------
function global:New-ELTestCsv {
    <#
    .SYNOPSIS
        Writes an HR export (header + rows) and returns its path. UTF-8 with BOM by default.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string[]] $Rows = @(),
        [string] $Header = 'Matricule;Prenom;Nom;Service;Poste;Manager;DateEffet;Mouvement',
        [System.Text.Encoding] $Encoding = (New-Object System.Text.UTF8Encoding($true))
    )

    $text = (@($Header) + $Rows) -join "`r`n"
    [System.IO.File]::WriteAllText($Path, $text + "`r`n", $Encoding)
    $Path
}

function global:New-ELTestConfigFile {
    <#
    .SYNOPSIS
        Writes a role catalog built from a hashtable / object and returns its path.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [object] $Data
    )

    $json = ConvertTo-Json -InputObject $Data -Depth 6
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    $Path
}

function global:ConvertFrom-ELTestSecureString {
    param([Parameter(Mandatory)] [System.Security.SecureString] $Value)
    (New-Object System.Management.Automation.PSCredential('x', $Value)).GetNetworkCredential().Password
}

function global:Get-ELTestAction {
    <#
    .SYNOPSIS
        Actions of a plan for one matricule (optionally one action type).
    #>
    param(
        [Parameter(Mandatory)] [object] $Plan,
        [Parameter(Mandatory)] [string] $Matricule,
        [string] $Action
    )

    @($Plan.Actions | Where-Object { $_.Matricule -eq $Matricule -and (-not $Action -or $_.Action -eq $Action) })
}
