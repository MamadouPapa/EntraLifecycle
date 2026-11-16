BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ELTestModulePath -Force

    $script:Plan = Get-ELPlan -CsvPath $ELTestCsvPath -ConfigPath $ELTestConfigPath -DemoMode -ReferenceDate $ELTestReferenceDate

    function Get-TestPlan {
        param([Parameter(Mandatory)] [string[]] $Rows, [datetime] $ReferenceDate = $ELTestReferenceDate)
        $path = New-ELTestCsv -Path (Join-Path $TestDrive ('hr-{0}.csv' -f [guid]::NewGuid())) -Rows $Rows
        Get-ELPlan -CsvPath $path -ConfigPath $ELTestConfigPath -DemoMode -ReferenceDate $ReferenceDate
    }
}

AfterAll {
    Remove-Module EntraLifecycle -Force -ErrorAction SilentlyContinue
}

Describe 'Get-ELPlan - plan object' {
    It 'is a demo plan with a summary, ordered actions, errors and warnings' {
        $Plan.PSObject.TypeNames | Should -Contain 'EntraLifecycle.Plan'
        $Plan.IsDemo | Should -BeTrue
        $Plan.UpnDomain | Should -Be 'contoso.example'
        $Plan.ReferenceDate | Should -Be $ELTestReferenceDate
        $Plan.RowCount | Should -Be 16
        $Plan.ValidRowCount | Should -Be 13
        @($Plan.Actions).Count | Should -Be $Plan.Summary.TotalActions
        @($Plan.Actions | ForEach-Object { $_.Order }) | Should -Be @(1..@($Plan.Actions).Count)
    }

    It 'creates every account before any other action (managers created by the same plan)' {
        $creates = @($Plan.Actions | Where-Object Action -EQ 'CreateUser')
        $creates.Count | Should -Be 6
        $lastCreate = ($creates | Measure-Object -Property Order -Maximum).Maximum
        $firstOther = (@($Plan.Actions | Where-Object Action -NE 'CreateUser') | Measure-Object -Property Order -Minimum).Minimum
        $lastCreate | Should -BeLessThan $firstOther
    }

    It 'turns invalid rows and impossible movements into plan errors' {
        @($Plan.Errors).Count | Should -Be 4
        @($Plan.Errors | ForEach-Object { $_.Matricule }) | Should -Contain 'E9999'
        ($Plan.Errors | Where-Object Matricule -EQ 'E9999').Message | Should -BeLike '*Mutation impossible*'
        @($Plan.Actions | Where-Object { @('E2008', 'E2009', 'E9999') -contains $_.Matricule }).Count | Should -Be 0
    }

    It 'never plans the deletion of an account' {
        @($Plan.Actions | Where-Object { $_.Action -match 'Delete|Remove(User|Account)' }).Count | Should -Be 0
    }

    It 'never puts a secret in the plan' {
        $json = $Plan | ConvertTo-Json -Depth 8
        $json | Should -Not -Match 'passwordProfile'
        $json | Should -Not -Match '"password"'
    }

    It 'rejects an unknown CSV path' {
        { Get-ELPlan -CsvPath (Join-Path $TestDrive 'nope.csv') -ConfigPath $ELTestConfigPath -DemoMode } | Should -Throw '*introuvable*'
    }
}

Describe 'Joiner planning' {
    It 'creates the account, groups by role, license, manager and a one-time TAP, in this order' {
        $actions = Get-ELTestAction -Plan $Plan -Matricule 'E2003'
        @($actions | ForEach-Object { $_.Action }) | Should -Be @('CreateUser', 'AddGroup', 'AddGroup', 'AssignLicense', 'SetManager', 'IssueTemporaryAccessPass')
        $actions[0].Target | Should -Be 'jean-francois.ndiaye@contoso.example'
        $actions[0].Parameters.Body.employeeId | Should -Be 'E2003'
        $actions[0].Parameters.Body.department | Should -Be 'Ressources humaines'
        @($actions | Where-Object Action -EQ 'AddGroup' | ForEach-Object { $_.Target }) | Should -Be @('GRP-Tous-Collaborateurs', 'GRP-RH')
        ($actions | Where-Object Action -EQ 'SetManager').Target | Should -Be 'sophie.martin@contoso.example'
        $tap = $actions | Where-Object Action -EQ 'IssueTemporaryAccessPass'
        $tap.Parameters.IsUsableOnce | Should -BeTrue
        $tap.Parameters.LifetimeInMinutes | Should -BeGreaterThan 0
    }

    It 'warns when a role group does not exist in the tenant' {
        ($Plan.Warnings | Where-Object Matricule -EQ 'E2003').Message | Should -BeLike '*GRP-App-SIRH*introuvable*'
    }

    It 'generates accent-free UPNs: <Matricule> -> <Upn>' -TestCases @(
        @{ Matricule = 'E2002'; Upn = 'elodie.gerard-lefevre@contoso.example' }
        @{ Matricule = 'E2005'; Upn = 'hugo.lambert@contoso.example' }
        @{ Matricule = 'E2004'; Upn = 'chloe.rousseau@contoso.example' }
    ) {
        (Get-ELTestAction -Plan $Plan -Matricule $Matricule -Action 'CreateUser').Target | Should -Be $Upn
    }

    It 'handles homonyms in the tenant and inside the same export' {
        (Get-ELTestAction -Plan $Plan -Matricule 'E2001' -Action 'CreateUser').Target | Should -Be 'camille.dubois2@contoso.example'
        (Get-ELTestAction -Plan $Plan -Matricule 'E2006' -Action 'CreateUser').Target | Should -Be 'camille.dubois3@contoso.example'
    }

    It 'flags the addition to a privileged group as high risk' {
        $privileged = Get-ELTestAction -Plan $Plan -Matricule 'E2002' -Action 'AddGroup' | Where-Object Target -EQ 'GRP-Intune-Admins'
        $privileged.Risk | Should -Be 'Élevé'
    }

    It 'defers every action of a future arrival and links it to a manager created by the plan' {
        $actions = Get-ELTestAction -Plan $Plan -Matricule 'E2004'
        @($actions | Where-Object Status -NE 'Différé').Count | Should -Be 0
        $manager = $actions | Where-Object Action -EQ 'SetManager'
        $manager.Parameters.ManagerMatricule | Should -Be 'E2005'
        $manager.Detail | Should -BeLike '*créé par ce même plan*'
    }

    It 'only completes missing access for an account that already exists (no new TAP)' {
        $actions = Get-ELTestAction -Plan $Plan -Matricule 'E2007'
        $actions[0].Action | Should -Be 'SkipExisting'
        @($actions | ForEach-Object { $_.Action }) | Should -Not -Contain 'CreateUser'
        @($actions | ForEach-Object { $_.Action }) | Should -Not -Contain 'IssueTemporaryAccessPass'
        @(Get-ELTestAction -Plan $Plan -Matricule 'E2007' -Action 'AddGroup').Count | Should -Be 3
        @(Get-ELTestAction -Plan $Plan -Matricule 'E2007' -Action 'AssignLicense').Count | Should -Be 1
    }

    It 'warns when the manager is unknown' {
        $plan = Get-TestPlan -Rows @('E3001;Zoé;Petit;Comptabilité;Comptable;E7777;2026-11-16;Arrivee')
        @(Get-ELTestAction -Plan $plan -Matricule 'E3001' -Action 'SetManager').Count | Should -Be 0
        ($plan.Warnings | Where-Object Matricule -EQ 'E3001').Message | Should -BeLike '*Manager*E7777*introuvable*'
    }

    It 'reports a name that cannot produce a UPN as an error' {
        $plan = Get-TestPlan -Rows @('E3002;???;Petit;Comptabilité;Comptable;E1001;2026-11-16;Arrivee')
        @($plan.Actions).Count | Should -Be 0
        $plan.Errors[0].Message | Should -BeLike '*Impossible de générer un identifiant*'
    }
}

Describe 'Mover planning (least privilege)' {
    It 'adds the new role groups AND removes the groups no longer needed' {
        $added = @(Get-ELTestAction -Plan $Plan -Matricule 'E1004' -Action 'AddGroup' | ForEach-Object { $_.Target })
        $removed = @(Get-ELTestAction -Plan $Plan -Matricule 'E1004' -Action 'RemoveGroup' | ForEach-Object { $_.Target })
        $added | Should -Be @('GRP-Ventes', 'GRP-App-CRM')
        $removed | Should -Be @('GRP-IT-Support', 'GRP-Intune-Admins')
        $removed | Should -Not -Contain 'GRP-Tous-Collaborateurs'
    }

    It 'removes privileged access with a high risk level, before granting the new rights' {
        $actions = Get-ELTestAction -Plan $Plan -Matricule 'E1004'
        ($actions | Where-Object Target -EQ 'GRP-Intune-Admins').Risk | Should -Be 'Élevé'
        $lastRemoval = (@($actions | Where-Object Action -EQ 'RemoveGroup') | Measure-Object -Property Order -Maximum).Maximum
        $firstAddition = (@($actions | Where-Object Action -EQ 'AddGroup') | Measure-Object -Property Order -Minimum).Minimum
        $lastRemoval | Should -BeLessThan $firstAddition
    }

    It 'swaps licenses, updates attributes and the manager' {
        (Get-ELTestAction -Plan $Plan -Matricule 'E1004' -Action 'AssignLicense').Target | Should -Be 'SPE_F1'
        (Get-ELTestAction -Plan $Plan -Matricule 'E1004' -Action 'RemoveLicense').Target | Should -Be 'SPE_E3'
        (Get-ELTestAction -Plan $Plan -Matricule 'E1004' -Action 'UpdateAttributes').Parameters.Body.department | Should -Be 'Commercial'
        (Get-ELTestAction -Plan $Plan -Matricule 'E1004' -Action 'SetManager').Target | Should -Be 'marc.leroy@contoso.example'
    }

    It 'keeps shared groups and licenses when the new role still needs them' {
        @(Get-ELTestAction -Plan $Plan -Matricule 'E1003' -Action 'RemoveGroup' | ForEach-Object { $_.Target }) | Should -Be @('GRP-App-Sage')
        @(Get-ELTestAction -Plan $Plan -Matricule 'E1003' -Action 'AddGroup' | ForEach-Object { $_.Target }) | Should -Be @('GRP-Finance-Controle', 'GRP-App-PowerBI')
        @(Get-ELTestAction -Plan $Plan -Matricule 'E1003' -Action 'RemoveLicense').Count | Should -Be 0
        @(Get-ELTestAction -Plan $Plan -Matricule 'E1003' -Action 'SetManager').Count | Should -Be 0
    }

    It 'plans nothing when the account already matches the role' {
        $plan = Get-TestPlan -Rows @('E1010;Marc;Leroy;Commercial;Responsable commercial;E1001;2026-11-16;Mutation')
        @($plan.Actions).Count | Should -Be 0
        @($plan.Errors).Count | Should -Be 0
    }
}

Describe 'Leaver planning' {
    It 'disables, revokes sessions and removes managed groups, in this order' {
        $actions = Get-ELTestAction -Plan $Plan -Matricule 'E1006'
        @($actions | ForEach-Object { $_.Action }) | Should -Be @('DisableAccount', 'RevokeSessions', 'RemoveGroup', 'RemoveGroup', 'RemoveGroup', 'ScheduleLicenseRemoval')
        $actions[0].Detail | Should -BeLike '*jamais supprimé*'
    }

    It 'keeps the license during the retention period and schedules its removal' {
        $schedule = Get-ELTestAction -Plan $Plan -Matricule 'E1006' -Action 'ScheduleLicenseRemoval'
        $schedule.Parameters.RemovalDate | Should -Be '2026-12-13'
        $schedule.Target | Should -Be 'SPE_F1'
        @(Get-ELTestAction -Plan $Plan -Matricule 'E1006' -Action 'RemoveLicense').Count | Should -Be 0
    }

    It 'removes the license once the retention period is over (account already disabled)' {
        $actions = Get-ELTestAction -Plan $Plan -Matricule 'E1005'
        @($actions | ForEach-Object { $_.Action }) | Should -Be @('RemoveLicense')
        $actions[0].Target | Should -Be 'SPE_E3'
    }

    It 'flags a leaver holding an administration role as high risk' {
        $disable = Get-ELTestAction -Plan $Plan -Matricule 'E1007' -Action 'DisableAccount'
        $disable.Risk | Should -Be 'Élevé'
        $disable.Detail | Should -BeLike '*User Administrator*'
    }

    It 'warns about memberships outside the catalog instead of removing them' {
        @(Get-ELTestAction -Plan $Plan -Matricule 'E1006' -Action 'RemoveGroup' | ForEach-Object { $_.Target }) | Should -Not -Contain 'GRP-Projet-Salon2026'
        ($Plan.Warnings | Where-Object Matricule -EQ 'E1006').Message | Should -BeLike '*1 appartenance(s) hors catalogue*'
    }

    It 'only warns when no account carries the matricule' {
        $plan = Get-TestPlan -Rows @('E4040;Paul;Absent;;;;2026-11-16;Depart')
        @($plan.Actions).Count | Should -Be 0
        $plan.Warnings[0].Message | Should -BeLike '*aucun compte*E4040*'
    }

    It 'defers a future departure' {
        $plan = Get-TestPlan -Rows @('E1010;Marc;Leroy;;;;2026-12-31;Depart')
        @($plan.Actions | Where-Object Status -NE 'Différé').Count | Should -Be 0
        $plan.Summary.DeferredActions | Should -Be @($plan.Actions).Count
    }
}

Describe 'Plan summary' {
    It 'counts people and actions per movement' {
        $byMovement = @{}
        foreach ($item in $Plan.Summary.ByMovement) { $byMovement[$item.Mouvement] = $item }
        $byMovement['Arrivee'].Personnes | Should -Be 7
        $byMovement['Mutation'].Personnes | Should -Be 2
        $byMovement['Depart'].Personnes | Should -Be 3
        $Plan.Summary.HighRiskActions | Should -BeGreaterOrEqual 4
    }
}
