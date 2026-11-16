BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ELTestModulePath -Force

    $script:Plan = Get-ELPlan -CsvPath $ELTestCsvPath -ConfigPath $ELTestConfigPath -DemoMode -ReferenceDate $ELTestReferenceDate
}

AfterAll {
    Remove-Module EntraLifecycle -Force -ErrorAction SilentlyContinue
}

Describe 'Export-ELPlanReport' {
    BeforeAll {
        $script:ReportPath = Join-Path $TestDrive 'out/sub/plan.html'
        $script:File = $Plan | Export-ELPlanReport -OutputPath $ReportPath
        $script:Html = [System.IO.File]::ReadAllText($ReportPath, [System.Text.Encoding]::UTF8)
        # Content checks run on the decoded text (accented letters may be emitted as entities).
        $script:Decoded = [System.Net.WebUtility]::HtmlDecode($Html)
    }

    It 'writes a self-contained UTF-8 HTML file, creating parent folders' {
        $File.FullName | Should -Be (Get-Item -LiteralPath $ReportPath).FullName
        $Html | Should -Match '^<!DOCTYPE html>'
        $Html | Should -Match '<meta charset="utf-8">'
        $Html | Should -Match 'Content-Security-Policy'
    }

    It 'contains no script and no external resource' {
        $Html | Should -Not -Match '<script'
        $Html | Should -Not -Match '(src|href)\s*=\s*"https?:'
    }

    It 'shows the demo badge, the summaries, the risks and every action' {
        $Decoded | Should -Match 'MODE DÉMO'
        $Decoded | Should -Match 'Synthèse par mouvement'
        $Decoded | Should -Match 'Points d''attention'
        $Decoded | Should -Match 'camille\.dubois2@contoso\.example'
        $Decoded | Should -Match 'elodie\.gerard-lefevre@contoso\.example'
        ([regex]::Matches($Html, '<tr( class="deferred")?><td class="num">')).Count | Should -BeGreaterOrEqual @($Plan.Actions).Count
    }

    It 'lists validation errors and warnings' {
        $Decoded | Should -Match 'Erreurs de validation'
        $Decoded | Should -Match 'E9999'
        $Decoded | Should -Match 'GRP-App-SIRH'
    }

    It 'states that the report holds no secret' {
        $Decoded | Should -Match 'aucun secret'
        $Html | Should -Not -Match 'passwordProfile'
    }

    It 'renders a plan with no action' {
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'noop.csv') -Rows @('E1010;Marc;Leroy;Commercial;Responsable commercial;E1001;2026-11-16;Mutation')
        $plan = Get-ELPlan -CsvPath $path -ConfigPath $ELTestConfigPath -DemoMode -ReferenceDate $ELTestReferenceDate
        $file = Export-ELPlanReport -Plan $plan -OutputPath (Join-Path $TestDrive 'noop.html')
        [System.Net.WebUtility]::HtmlDecode([System.IO.File]::ReadAllText($file.FullName)) | Should -Match 'déjà conforme'
    }

    It 'refuses an object that is not a plan' {
        { Export-ELPlanReport -Plan 'not a plan' -OutputPath (Join-Path $TestDrive 'x.html') } | Should -Throw '*Objet de plan invalide*'
    }
}

Describe 'HTML encoding of untrusted HR data' {
    It 'encodes markup coming from the HR export' {
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'hostile.csv') -Rows @(
            'E5001;Zoé;Petit;Comptabilité;Comptable;E1001;2026-11-16;<img src=x onerror=alert(1)>'
        )
        $plan = Get-ELPlan -CsvPath $path -ConfigPath $ELTestConfigPath -DemoMode -ReferenceDate $ELTestReferenceDate
        $file = Export-ELPlanReport -Plan $plan -OutputPath (Join-Path $TestDrive 'hostile.html')
        $html = [System.IO.File]::ReadAllText($file.FullName)
        $html | Should -Not -Match '<img'
        $html | Should -Match '&lt;img src=x onerror=alert\(1\)&gt;'
    }

    It 'encodes every special character' {
        InModuleScope EntraLifecycle { ConvertTo-ELHtml -Value '<a href="x">&''</a>' } | Should -BeExactly '&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;'
        InModuleScope EntraLifecycle { ConvertTo-ELHtml -Value $null } | Should -BeExactly ''
    }
}

Describe 'Format-ELPlan' {
    BeforeAll {
        $script:Lines = @($Plan | Format-ELPlan)
        $script:Text = $Lines -join "`n"
    }

    It 'renders a Terraform-like plan with one block per person' {
        $Lines[0] | Should -Match 'MODE DÉMO'
        $Text | Should -Match '# E2001 - Arrivée - camille\.dubois2@contoso\.example'
        $Text | Should -Match '# E1004 - Mutation - karim\.haddad@contoso\.example'
        $Text | Should -Match '# E1007 - Départ - antoine\.lefevre@contoso\.example'
    }

    It 'uses + for grants, - for removals and flags risks and deferrals' {
        $Text | Should -Match '\+ CreateUser\s+camille\.dubois2@contoso\.example'
        $Text | Should -Match '- RemoveGroup\s+GRP-Intune-Admins\s+\(!\)'
        $Text | Should -Match '~ SetManager'
        $Text | Should -Match '\(différé au 2026-12-01\)'
    }

    It 'lists errors and ends with the totals' {
        $Text | Should -Match 'Erreurs \(lignes non traitées\) \(4\)'
        $Lines[-2] | Should -Match '^Plan : \d+ à créer/ajouter, \d+ à modifier, \d+ à retirer/révoquer'
        $Lines[-1] | Should -Match 'Invoke-ELPlan'
    }
}
