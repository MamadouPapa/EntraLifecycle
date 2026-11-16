# Demo executor: applies a -DemoMode plan to the fictional tenant without any Graph call, so that
# the whole flow (confirmation, audit trail, TAP handoff) can be shown and tested offline.

$script:ELDemoTapLength = 16

function Invoke-ELDemoAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Action,
        [Parameter(Mandatory)] [object] $State
    )

    if ($Action.Action -eq 'CreateUser') {
        $State.UserIds[$Action.Matricule] = [guid]::NewGuid().ToString()
        return
    }
    if (-not $script:ELActionLabel.Contains([string]$Action.Action)) {
        throw ('Action non prise en charge : {0}' -f $Action.Action)
    }

    $userId = Resolve-ELDemoUserId -Matricule $Action.Matricule -PlannedId ([string]$Action.Parameters.UserId) -State $State
    Write-Verbose ('[démo] {0} -> {1} ({2})' -f $Action.Action, $Action.Target, $userId)
    if ($Action.Action -eq 'SetManager') {
        [void](Resolve-ELDemoUserId -Matricule ([string]$Action.Parameters.ManagerMatricule) -PlannedId ([string]$Action.Parameters.ManagerId) -State $State)
    }
    if ($Action.Action -eq 'IssueTemporaryAccessPass') {
        # Random throw-away value: shows the SecureString handoff without any real credential.
        $secret = ConvertTo-ELSecureString -Value (New-ELRandomPassword -Length $script:ELDemoTapLength)
        New-ELHandoff -Action $Action -Secret $secret
    }
}

function Resolve-ELDemoUserId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Matricule,
        [AllowEmptyString()] [string] $PlannedId = '',
        [Parameter(Mandatory)] [object] $State
    )

    if ($PlannedId) { return $PlannedId }
    if ($Matricule -and $State.UserIds.ContainsKey($Matricule)) { return [string]$State.UserIds[$Matricule] }
    throw ('Compte introuvable pour l''employeeId {0} dans le tenant de démonstration' -f $Matricule)
}
