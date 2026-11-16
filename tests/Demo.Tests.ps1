BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ELTestModulePath -Force
}

AfterAll {
    Remove-Module EntraLifecycle -Force -ErrorAction SilentlyContinue
}

Describe 'Module surface' {
    It 'exports exactly the four public commands' {
        $commands = @((Get-Module EntraLifecycle).ExportedFunctions.Keys | Sort-Object)
        $commands | Should -Be @('Export-ELPlanReport', 'Format-ELPlan', 'Get-ELPlan', 'Invoke-ELPlan')
    }

    It 'declares Invoke-ELPlan with a high confirmation impact' {
        $metadata = New-Object System.Management.Automation.CommandMetadata (Get-Command Invoke-ELPlan)
        $metadata.SupportsShouldProcess | Should -BeTrue
        $metadata.ConfirmImpact | Should -Be 'High'
    }

    It 'has a valid manifest compatible with Windows PowerShell 5.1' {
        $manifest = Test-ModuleManifest -Path $ELTestModulePath
        $manifest.PowerShellVersion | Should -Be ([version]'5.1')
        $manifest.CompatiblePSEditions | Should -Contain 'Desktop'
    }
}

Describe 'End-to-end demo (scripts/Invoke-Demo.ps1)' {
    BeforeAll {
        $script:OutDir = Join-Path $TestDrive 'demo'
        $script:Demo = & (Join-Path $ELTestRoot 'scripts/Invoke-Demo.ps1') -OutputDirectory $OutDir 6>$null
        Import-Module $ELTestModulePath -Force
        $script:Taps = @($Demo.Result.Handoffs | ForEach-Object { ConvertFrom-ELTestSecureString -Value $_.TemporaryAccessPass })
    }

    It 'produces the text plan, the HTML report and the audit log' {
        Test-Path -LiteralPath $Demo.PlanTextPath | Should -BeTrue
        Test-Path -LiteralPath $Demo.ReportPath | Should -BeTrue
        Test-Path -LiteralPath $Demo.AuditLogPath | Should -BeTrue
        $Demo.Result.Failed | Should -Be 0
    }

    It 'issues TAPs that appear in none of the generated files' {
        $Taps.Count | Should -Be 5
        foreach ($file in @($Demo.PlanTextPath, $Demo.ReportPath, $Demo.AuditLogPath)) {
            $content = [System.IO.File]::ReadAllText($file)
            foreach ($tap in $Taps) { $content.Contains($tap) | Should -BeFalse }
            foreach ($tap in $Taps) { $content.Contains([System.Net.WebUtility]::HtmlEncode($tap)) | Should -BeFalse }
        }
    }

    It 'logs every planned action exactly once' {
        $entries = @(Get-Content -LiteralPath $Demo.AuditLogPath -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
        $actions = @($entries | Where-Object event -EQ 'action')
        $actions.Count | Should -Be @($Demo.Plan.Actions).Count
        @($actions | ForEach-Object { $_.order } | Sort-Object -Unique).Count | Should -Be $actions.Count
    }

    It 'leaves the plan unchanged by the apply (plan objects are not mutated)' {
        @($Demo.Plan.Actions | Where-Object { $_.Parameters.ContainsKey('Body') -and $_.Parameters.Body.ContainsKey('passwordProfile') }).Count | Should -Be 0
    }
}
