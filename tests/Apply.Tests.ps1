BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ELTestModulePath -Force

    function Get-TestLivePlan {
        <#
        .SYNOPSIS
            A demo plan relabelled as a live plan, so that Invoke-ELPlan goes through the (mocked)
            Microsoft Graph code path.
        #>
        param([string[]] $Rows)
        $path = New-ELTestCsv -Path (Join-Path $TestDrive ('live-{0}.csv' -f [guid]::NewGuid())) -Rows $Rows
        $plan = Get-ELPlan -CsvPath $path -ConfigPath $ELTestConfigPath -DemoMode -ReferenceDate $ELTestReferenceDate
        $plan.IsDemo = $false
        $plan
    }

    function Read-TestAudit {
        param([Parameter(Mandatory)] [string] $Path)
        @(Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
    }
}

AfterAll {
    Remove-Module EntraLifecycle -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-ELPlan on the demo tenant' {
    BeforeAll {
        $script:Plan = Get-ELPlan -CsvPath $ELTestCsvPath -ConfigPath $ELTestConfigPath -DemoMode -ReferenceDate $ELTestReferenceDate
        $script:AuditPath = Join-Path $TestDrive 'audit/demo.jsonl'
        $script:Result = Invoke-ELPlan -Plan $Plan -AuditLogPath $AuditPath -Confirm:$false
        $script:Audit = Read-TestAudit -Path $AuditPath
        $script:AuditText = [System.IO.File]::ReadAllText($AuditPath)
        $script:Taps = @($Result.Handoffs | ForEach-Object { ConvertFrom-ELTestSecureString -Value $_.TemporaryAccessPass })
    }

    It 'applies every ready action without any Graph session' {
        $Result.IsDemo | Should -BeTrue
        $Result.Failed | Should -Be 0
        $Result.Succeeded | Should -BeGreaterThan 0
        @($Result.Results).Count | Should -Be @($Plan.Actions).Count
    }

    It 'never applies deferred or informational actions' {
        foreach ($item in $Result.Results) {
            $action = $Plan.Actions | Where-Object Order -EQ $item.Order
            if ($action.Status -eq 'Différé') { $item.Result | Should -Be 'Différé' }
        }
        ($Result.Results | Where-Object Action -EQ 'ScheduleLicenseRemoval' | Select-Object -First 1).Result | Should -Be 'Planifié'
        ($Result.Results | Where-Object Action -EQ 'SkipExisting').Result | Should -Be 'Ignoré'
    }

    It 'returns one TAP handoff per ready joiner, as a read-only SecureString' {
        @($Result.Handoffs).Count | Should -Be 5
        foreach ($handoff in $Result.Handoffs) {
            $handoff.TemporaryAccessPass | Should -BeOfType [System.Security.SecureString]
            $handoff.TemporaryAccessPass.IsReadOnly() | Should -BeTrue
            $handoff.IsUsableOnce | Should -BeTrue
        }
        @($Result.Handoffs | ForEach-Object { $_.Matricule }) | Should -Not -Contain 'E2004'
        $Taps | ForEach-Object { $_.Length | Should -BeGreaterThan 8 }
    }

    It 'writes a JSONL audit entry for every action, framed by start and end markers' {
        $Audit[0].event | Should -Be 'start'
        $Audit[-1].event | Should -Be 'end'
        @($Audit | Where-Object event -EQ 'action').Count | Should -Be @($Plan.Actions).Count
        @($Audit | ForEach-Object { $_.runId } | Sort-Object -Unique) | Should -Be @($Result.RunId)
        $Audit[1].mode | Should -Be 'demo'
        $Audit[1].actor | Should -Not -BeNullOrEmpty
        $Audit[1].timestamp | Should -Not -BeNullOrEmpty
    }

    It 'NEVER records a Temporary Access Pass in the audit log' {
        $Taps.Count | Should -Be 5
        foreach ($tap in $Taps) { $AuditText.Contains($tap) | Should -BeFalse }
        $AuditText | Should -Not -Match 'temporaryAccessPass"\s*:'
        $AuditText | Should -Not -Match 'password'
    }

    It 'only uses allow-listed audit fields' {
        $allowed = @('timestamp', 'runId', 'mode', 'actor', 'event', 'order', 'matricule', 'mouvement', 'action', 'target', 'result', 'error')
        foreach ($entry in $Audit) {
            foreach ($name in $entry.PSObject.Properties.Name) { $allowed | Should -Contain $name }
        }
    }

    It 'appends to an existing audit file' {
        $path = Join-Path $TestDrive 'audit/append.jsonl'
        $null = Invoke-ELPlan -Plan $Plan -AuditLogPath $path -Confirm:$false
        $first = @(Read-TestAudit -Path $path).Count
        $null = Invoke-ELPlan -Plan $Plan -AuditLogPath $path -Confirm:$false
        @(Read-TestAudit -Path $path).Count | Should -Be ($first * 2)
    }
}

Describe 'Invoke-ELPlan safety' {
    It '-WhatIf applies nothing and writes no audit file' {
        $plan = Get-ELPlan -CsvPath $ELTestCsvPath -ConfigPath $ELTestConfigPath -DemoMode -ReferenceDate $ELTestReferenceDate
        $path = Join-Path $TestDrive 'whatif.jsonl'
        $result = Invoke-ELPlan -Plan $plan -AuditLogPath $path -WhatIf
        Test-Path -LiteralPath $path | Should -BeFalse
        $result.Succeeded | Should -Be 0
        @($result.Handoffs).Count | Should -Be 0
        @($result.Results | Where-Object Result -EQ 'Non appliqué').Count | Should -BeGreaterThan 0
    }

    It 'refuses an object that is not a plan' {
        { Invoke-ELPlan -Plan ([pscustomobject]@{ Foo = 1 }) -Confirm:$false } | Should -Throw '*Objet de plan invalide*'
    }

    It 'refuses a live plan without a Microsoft Graph session' {
        $plan = Get-TestLivePlan -Rows @('E1010;Marc;Leroy;;;;2026-11-16;Depart')
        Mock -ModuleName EntraLifecycle Get-MgContext { $null }
        { Invoke-ELPlan -Plan $plan -AuditLogPath (Join-Path $TestDrive 'nosession.jsonl') -Confirm:$false } | Should -Throw '*Connect-MgGraph*'
    }

    It 'warns when the plan is older than 24 hours' {
        $plan = Get-ELPlan -CsvPath $ELTestCsvPath -ConfigPath $ELTestConfigPath -DemoMode -ReferenceDate $ELTestReferenceDate
        $plan.GeneratedAt = (Get-Date).AddDays(-2)
        $null = Invoke-ELPlan -Plan $plan -AuditLogPath (Join-Path $TestDrive 'old.jsonl') -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
        ($warnings -join ' ') | Should -BeLike '*régénérez-le*'
    }
}

Describe 'Invoke-ELPlan against Microsoft Graph (mocked)' {
    BeforeEach {
        Mock -ModuleName EntraLifecycle Get-MgContext { [pscustomobject]@{ Account = 'admin@contoso.example'; AppName = $null } }
        Mock -ModuleName EntraLifecycle New-MgUser { [pscustomobject]@{ Id = 'new-' + $BodyParameter.employeeId } }
        Mock -ModuleName EntraLifecycle Update-MgUser { }
        Mock -ModuleName EntraLifecycle Revoke-MgUserSignInSession { }
        Mock -ModuleName EntraLifecycle New-MgGroupMember { }
        Mock -ModuleName EntraLifecycle Remove-MgGroupMemberByRef { }
        Mock -ModuleName EntraLifecycle Set-MgUserLicense { }
        Mock -ModuleName EntraLifecycle Set-MgUserManagerByRef { }
        Mock -ModuleName EntraLifecycle New-MgUserAuthenticationTemporaryAccessPassMethod { [pscustomobject]@{ TemporaryAccessPass = 'TAP-SECRET-12345' } }
        Mock -ModuleName EntraLifecycle Get-MgUser { @() }
    }

    It 'creates the joiner with a random password that is forced to change, then wires everything to the new id' {
        $plan = Get-TestLivePlan -Rows @('E3001;Zoé;Petit;Comptabilité;Comptable;E1001;2026-11-16;Arrivee')
        $result = Invoke-ELPlan -Plan $plan -AuditLogPath (Join-Path $TestDrive 'joiner.jsonl') -Confirm:$false

        $result.Failed | Should -Be 0
        Should -Invoke -ModuleName EntraLifecycle New-MgUser -Times 1 -Exactly -ParameterFilter {
            $BodyParameter.userPrincipalName -eq 'zoe.petit@contoso.example' -and
            $BodyParameter.passwordProfile.forceChangePasswordNextSignIn -eq $true -and
            $BodyParameter.passwordProfile.password.Length -ge 32
        }
        Should -Invoke -ModuleName EntraLifecycle New-MgGroupMember -Times 3 -Exactly -ParameterFilter { $DirectoryObjectId -eq 'new-E3001' }
        Should -Invoke -ModuleName EntraLifecycle Set-MgUserLicense -Times 1 -Exactly -ParameterFilter { $UserId -eq 'new-E3001' }
        Should -Invoke -ModuleName EntraLifecycle Set-MgUserManagerByRef -Times 1 -Exactly -ParameterFilter {
            $UserId -eq 'new-E3001' -and $BodyParameter['@odata.id'] -like '*/users/a0d1e000-0000-4000-8000-000000001001'
        }
        Should -Invoke -ModuleName EntraLifecycle New-MgUserAuthenticationTemporaryAccessPassMethod -Times 1 -Exactly -ParameterFilter {
            $BodyParameter.isUsableOnce -eq $true
        }
    }

    It 'returns the Graph TAP only as a SecureString and keeps it out of the audit log and the results' {
        $plan = Get-TestLivePlan -Rows @('E3001;Zoé;Petit;Comptabilité;Comptable;E1001;2026-11-16;Arrivee')
        $path = Join-Path $TestDrive 'tap.jsonl'
        $result = Invoke-ELPlan -Plan $plan -AuditLogPath $path -Confirm:$false

        ConvertFrom-ELTestSecureString -Value $result.Handoffs[0].TemporaryAccessPass | Should -BeExactly 'TAP-SECRET-12345'
        [System.IO.File]::ReadAllText($path) | Should -Not -Match 'TAP-SECRET'
        ($result.Results | ConvertTo-Json -Depth 5) | Should -Not -Match 'TAP-SECRET'
        ($result.Handoffs | Out-String) | Should -Not -Match 'TAP-SECRET'
        (Read-TestAudit -Path $path)[1].actor | Should -Be 'admin@contoso.example'
    }

    It 'disables, revokes and removes groups for a leaver, and never deletes the account' {
        $plan = Get-TestLivePlan -Rows @('E1006;Lucas;Girard;;;;2026-11-13;Depart')
        $result = Invoke-ELPlan -Plan $plan -AuditLogPath (Join-Path $TestDrive 'leaver.jsonl') -Confirm:$false

        $result.Failed | Should -Be 0
        Should -Invoke -ModuleName EntraLifecycle Update-MgUser -Times 1 -Exactly -ParameterFilter { $BodyParameter.accountEnabled -eq $false }
        Should -Invoke -ModuleName EntraLifecycle Revoke-MgUserSignInSession -Times 1 -Exactly
        Should -Invoke -ModuleName EntraLifecycle Remove-MgGroupMemberByRef -Times 3 -Exactly
        Should -Invoke -ModuleName EntraLifecycle Set-MgUserLicense -Times 0 -Exactly
    }

    It 'isolates a failure, records it and continues' {
        Mock -ModuleName EntraLifecycle Remove-MgGroupMemberByRef { throw 'Graph 403 Forbidden' }
        $plan = Get-TestLivePlan -Rows @('E1006;Lucas;Girard;;;;2026-11-13;Depart')
        $path = Join-Path $TestDrive 'failure.jsonl'
        $result = Invoke-ELPlan -Plan $plan -AuditLogPath $path -Confirm:$false

        $result.Failed | Should -Be 3
        ($result.Results | Where-Object Action -EQ 'DisableAccount').Result | Should -Be 'Succès'
        @($result.Results | Where-Object Result -EQ 'Échec' | ForEach-Object { $_.Error }) | Should -Be @('Graph 403 Forbidden', 'Graph 403 Forbidden', 'Graph 403 Forbidden')
        @(Read-TestAudit -Path $path | Where-Object result -EQ 'Échec').Count | Should -Be 3
    }

    It 'cancels the remaining actions of a joiner whose creation failed' {
        Mock -ModuleName EntraLifecycle New-MgUser { throw 'UPN conflict' }
        $plan = Get-TestLivePlan -Rows @(
            'E3005;Hugo;Blanc;Commercial;Responsable commercial;E1001;2026-11-16;Arrivee'
            'E3006;Lina;Roux;Commercial;Commercial terrain;E3005;2026-11-16;Arrivee'
        )
        Mock -ModuleName EntraLifecycle New-MgUser { throw 'UPN conflict' } -ParameterFilter { $BodyParameter.employeeId -eq 'E3005' }
        Mock -ModuleName EntraLifecycle New-MgUser { [pscustomobject]@{ Id = 'new-E3006' } } -ParameterFilter { $BodyParameter.employeeId -eq 'E3006' }
        $result = Invoke-ELPlan -Plan $plan -AuditLogPath (Join-Path $TestDrive 'cancel.jsonl') -Confirm:$false

        @($result.Results | Where-Object { $_.Matricule -eq 'E3005' -and $_.Action -ne 'CreateUser' } | ForEach-Object { $_.Result } | Sort-Object -Unique) | Should -Be @('Annulé')
        ($result.Results | Where-Object { $_.Matricule -eq 'E3006' -and $_.Action -eq 'SetManager' }).Result | Should -Be 'Annulé'
        ($result.Results | Where-Object { $_.Matricule -eq 'E3006' -and $_.Action -eq 'AssignLicense' }).Result | Should -Be 'Succès'
        Should -Invoke -ModuleName EntraLifecycle New-MgUserAuthenticationTemporaryAccessPassMethod -Times 1 -Exactly
    }

    It 'stops before any change when the audit log cannot be written' {
        $plan = Get-TestLivePlan -Rows @('E1006;Lucas;Girard;;;;2026-11-13;Depart')
        $blocker = Join-Path $TestDrive 'blocker'
        [System.IO.File]::WriteAllText($blocker, 'not a folder')
        { Invoke-ELPlan -Plan $plan -AuditLogPath (Join-Path $blocker 'audit.jsonl') -Confirm:$false } | Should -Throw '*Journal d''audit inaccessible*'
        Should -Invoke -ModuleName EntraLifecycle Update-MgUser -Times 0 -Exactly
    }
}
