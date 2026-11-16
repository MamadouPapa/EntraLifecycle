# JSONL audit trail (one JSON object per line, UTF-8 without BOM, append-only). Entries are built
# from a fixed allow-list of fields: no secret, no Graph response and no request body is ever written.

$script:ELAuditFields = @('timestamp', 'runId', 'mode', 'actor', 'event', 'order', 'matricule', 'mouvement', 'action', 'target', 'result', 'error')

function Write-ELAuditRecord {
    <#
    .SYNOPSIS
        Appends one entry. Uses .NET IO so that -WhatIf / -Confirm never apply to the audit trail.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Data
    )

    if (-not $State.WriteAudit) { return }

    $mode = 'live'
    if ($State.IsDemo) { $mode = 'demo' }
    $entry = [ordered]@{}
    foreach ($field in $script:ELAuditFields) { $entry[$field] = $null }
    $entry.timestamp = (Get-Date).ToUniversalTime().ToString('o')
    $entry.runId = $State.RunId
    $entry.mode = $mode
    $entry.actor = $State.Actor
    foreach ($key in $Data.Keys) {
        if ($script:ELAuditFields -notcontains $key) { throw ('Champ d''audit non autorisé : {0}' -f $key) }
        $entry[$key] = $Data[$key]
    }

    $line = (ConvertTo-Json -InputObject $entry -Compress) + "`n"
    $directory = Split-Path -Path $State.AuditLogPath -Parent
    if ($directory) { [void][System.IO.Directory]::CreateDirectory($directory) }
    [System.IO.File]::AppendAllText($State.AuditLogPath, $line, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-ELAuditEntry {
    <#
    .SYNOPSIS
        Audit entry for one action result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [object] $Result
    )

    Write-ELAuditRecord -State $State -Data ([ordered]@{
            event     = 'action'
            order     = $Result.Order
            matricule = $Result.Matricule
            mouvement = $Result.Mouvement
            action    = $Result.Action
            target    = $Result.Target
            result    = $Result.Result
            error     = $Result.Error
        })
}

function Write-ELAuditRunEvent {
    <#
    .SYNOPSIS
        Start / end markers of a run. The start marker is written before any change, so a run that
        cannot write its audit trail stops before touching the tenant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $State,
        [Parameter(Mandatory)] [ValidateSet('start', 'end')] [string] $Kind,
        [AllowEmptyString()] [string] $Detail = ''
    )

    Write-ELAuditRecord -State $State -Data ([ordered]@{ event = $Kind; target = $Detail })
}
