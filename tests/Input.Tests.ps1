BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ELTestModulePath -Force

    function Import-TestCsv {
        param([Parameter(Mandatory)] [string] $Path)
        InModuleScope EntraLifecycle -Parameters @{ Path = $Path; ConfigPath = $ELTestConfigPath } {
            param($Path, $ConfigPath)
            Import-ELHrCsv -Path $Path -Config (Import-ELConfig -Path $ConfigPath)
        }
    }

    function Get-TestErrorText {
        param([Parameter(Mandatory)] [object] $Import)
        (@($Import.Errors) | ForEach-Object { $_.Message }) -join ' | '
    }
}

AfterAll {
    Remove-Module EntraLifecycle -Force -ErrorAction SilentlyContinue
}

Describe 'Import-ELHrCsv - file and column contract' {
    It 'throws a French error when the file does not exist' {
        { Import-TestCsv -Path (Join-Path $TestDrive 'absent.csv') } | Should -Throw 'Export RH introuvable*'
    }

    It 'throws when the file is empty' {
        $path = Join-Path $TestDrive 'empty.csv'
        [System.IO.File]::WriteAllText($path, '   ')
        { Import-TestCsv -Path $path } | Should -Throw 'Export RH vide*'
    }

    It 'throws and lists the missing columns' {
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'columns.csv') -Header 'Matricule;Prenom;Nom' -Rows @('E1;A;B')
        { Import-TestCsv -Path $path } | Should -Throw '*Colonnes manquantes*Service, Poste, Manager, DateEffet, Mouvement*'
    }

    It 'throws on duplicated columns' {
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'dup-columns.csv') -Header ($ELTestHeader + ';Nom') -Rows @()
        { Import-TestCsv -Path $path } | Should -Throw '*Colonnes en double*Nom*'
    }

    It 'accepts a header with an empty trailing column (Excel export)' {
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'trailing.csv') -Header ($ELTestHeader + ';') `
            -Rows @('E2001;Camille;Dubois;Comptabilité;Comptable;E1001;2026-11-16;Arrivee;')
        $import = Import-TestCsv -Path $path
        @($import.Rows).Count | Should -Be 1
    }
}

Describe 'Import-ELHrCsv - delimiters and encodings' {
    It 'detects the comma delimiter' {
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'comma.csv') -Header ($ELTestHeader -replace ';', ',') `
            -Rows @('E2001,Camille,Dubois,Comptabilité,Comptable,E1001,2026-11-16,Arrivee')
        $import = Import-TestCsv -Path $path
        $import.Delimiter | Should -Be ','
        $import.Rows[0].Service | Should -Be 'Comptabilité'
    }

    It 'reads UTF-8 without BOM' {
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'nobom.csv') -Encoding (New-Object System.Text.UTF8Encoding($false)) `
            -Rows @('E2002;Élodie;Gérard;Comptabilité;Comptable;E1001;2026-11-16;Arrivée')
        $import = Import-TestCsv -Path $path
        $import.Rows[0].Prenom | Should -BeExactly 'Élodie'
        $import.Rows[0].Mouvement | Should -Be 'Arrivee'
    }

    It 'falls back to a legacy 8-bit encoding when the file is not valid UTF-8' {
        $latin1 = [System.Text.Encoding]::GetEncoding('iso-8859-1')
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'ansi.csv') -Encoding $latin1 `
            -Rows @('E2002;Élodie;Gérard;Comptabilité;Comptable;E1001;2026-11-16;Arrivee')
        $import = Import-TestCsv -Path $path
        @($import.Errors).Count | Should -Be 0
        $import.Rows[0].Prenom | Should -BeExactly 'Élodie'
        $import.Rows[0].Role.Service | Should -Be 'Comptabilité'
    }

    It 'skips blank lines and keeps the real line numbers' {
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'blank.csv') -Rows @(
            'E2001;Camille;Dubois;Comptabilité;Comptable;E1001;2026-11-16;Arrivee'
            ''
            ';;;;;;;'
            'E2009;Paul;Martin;Comptabilité;Comptable;E1001;16/11/2026;Arrivee'
        )
        $import = Import-TestCsv -Path $path
        $import.RowCount | Should -Be 2
        $import.Errors[0].Ligne | Should -Be 5
        $import.Rows[0].Line | Should -Be 2
    }
}

Describe 'Import-ELHrCsv - row validation' {
    BeforeAll {
        $rows = @(
            'E2001;Camille;Dubois;comptabilite;COMPTABLE;E1001;2026-11-16;ARRIVÉE'
            'E2002;;Dubois;Comptabilité;Comptable;E1001;2026-11-16;Arrivee'
            'E2003;Paul;Martin;Comptabilité;Comptable;E1001;16/11/2026;Arrivee'
            'E2004;Paul;Martin;Comptabilité;Comptable;E1001;2026-02-30;Arrivee'
            'E2005;Paul;Martin;Comptabilité;Comptable;E1001;2026-11-16;Embauche'
            "E2006' or 1 eq 1;Eve;Martin;Comptabilité;Comptable;E1001;2026-11-16;Arrivee"
            'E2007;Paul;Martin;Marketing;Community manager;E1001;2026-11-16;Arrivee'
            'E2008;Paul;Martin;;;E1001;2026-11-16;Mutation'
            'E2009;Paul;Martin;Comptabilité;Comptable;E2009;2026-11-16;Arrivee'
            'E2010;Paul;Martin;Comptabilité;Comptable;bad manager;2026-11-16;Arrivee'
            'E2011;<script>;Martin;Comptabilité;Comptable;E1001;2026-11-16;Arrivee'
            ('E2012;{0};Martin;Comptabilité;Comptable;E1001;2026-11-16;Arrivee' -f ('x' * 65))
            'E2001;Camille;Dubois;Comptabilité;Comptable;E1001;2026-11-16;Arrivee'
            'E1006;Lucas;Girard;;;;2026-11-13;Départ'
        )
        $path = New-ELTestCsv -Path (Join-Path $TestDrive 'rows.csv') -Rows $rows
        $script:Import = Import-TestCsv -Path $path
        $script:ErrorByLine = @{}
        foreach ($issue in $Import.Errors) { $ErrorByLine[[int]$issue.Ligne] = $issue.Message }
    }

    It 'normalizes movement, case and accents of Service/Poste' {
        $row = $Import.Rows | Where-Object Matricule -EQ 'E2001'
        $row.Mouvement | Should -Be 'Arrivee'
        $row.Role.Poste | Should -Be 'Comptable'
        $row.DateEffet | Should -Be ([datetime]'2026-11-16')
    }

    It 'accepts a leaver without Service/Poste' {
        ($Import.Rows | Where-Object Matricule -EQ 'E1006').Mouvement | Should -Be 'Depart'
    }

    It 'only keeps the 2 valid rows' {
        $Import.RowCount | Should -Be 14
        @($Import.Rows).Count | Should -Be 2
        @($Import.Errors).Count | Should -Be 12
    }

    It 'reports <Expected> (line <Line>)' -TestCases @(
        @{ Line = 3; Expected = '*Champ obligatoire vide : Prenom*' }
        @{ Line = 4; Expected = '*Date d''effet invalide*16/11/2026*' }
        @{ Line = 5; Expected = '*Date d''effet invalide*2026-02-30*' }
        @{ Line = 6; Expected = '*Mouvement inconnu*Embauche*' }
        @{ Line = 7; Expected = '*Matricule invalide*' }
        @{ Line = 8; Expected = '*absent du catalogue des rôles*Marketing*' }
        @{ Line = 9; Expected = '*Service et Poste sont obligatoires*' }
        @{ Line = 10; Expected = '*propre manager*' }
        @{ Line = 11; Expected = '*Matricule du manager invalide*' }
        @{ Line = 12; Expected = '*Prenom contient des caractères interdits*' }
        @{ Line = 13; Expected = '*Prenom trop long*' }
        @{ Line = 14; Expected = '*Matricule en double*' }
    ) {
        $ErrorByLine[$Line] | Should -BeLike $Expected
    }
}

Describe 'Import-ELConfig' {
    BeforeAll {
        function New-TestCatalog {
            param([hashtable] $Settings = @{ upnDomain = 'contoso.example'; leaverLicenseRetentionDays = 30 }, [object[]] $Roles)
            if ($null -eq $Roles) { $Roles = @(@{ service = 'IT'; poste = 'Dev'; groups = @('GRP-A'); licenses = @('SPE_E3') }) }
            @{ settings = $Settings; roles = $Roles }
        }
        function Import-TestCatalog {
            param([object] $Data)
            $path = New-ELTestConfigFile -Path (Join-Path $TestDrive ('cfg-{0}.json' -f [guid]::NewGuid())) -Data $Data
            InModuleScope EntraLifecycle -Parameters @{ Path = $path } { param($Path) Import-ELConfig -Path $Path }
        }
    }

    It 'loads the sample catalog with managed groups and SKUs' {
        $config = InModuleScope EntraLifecycle -Parameters @{ Path = $ELTestConfigPath } { param($Path) Import-ELConfig -Path $Path }
        $config.UpnDomain | Should -Be 'contoso.example'
        $config.RetentionDays | Should -Be 30
        $config.Roles.Count | Should -Be 8
        $config.ManagedGroups | Should -Contain 'GRP-Intune-Admins'
        $config.ManagedSkus | Should -Contain 'POWER_BI_PRO'
        $config.PrivilegedGroups | Should -Contain 'GRP-IT-Admins-Serveurs'
        @($config.ManagedGroups | Where-Object { $_ -eq 'GRP-Tous-Collaborateurs' }).Count | Should -Be 1
    }

    It 'applies the default usage location and role overrides' {
        $data = New-TestCatalog -Roles @(@{ service = 'IT'; poste = 'Dev'; jobTitle = 'Développeur'; usageLocation = 'be'; groups = @(); licenses = @() })
        $role = (Import-TestCatalog -Data $data).Roles[0]
        $role.JobTitle | Should -Be 'Développeur'
        $role.Department | Should -Be 'IT'
        $role.UsageLocation | Should -Be 'BE'
    }

    It 'throws on malformed JSON' {
        $path = Join-Path $TestDrive 'broken.json'
        [System.IO.File]::WriteAllText($path, '{ "settings": ')
        { InModuleScope EntraLifecycle -Parameters @{ Path = $path } { param($Path) Import-ELConfig -Path $Path } } | Should -Throw '*JSON invalide*'
    }

    It 'throws when the catalog file is missing' {
        { InModuleScope EntraLifecycle { Import-ELConfig -Path 'nope/roles.json' } } | Should -Throw '*introuvable*'
    }

    It 'rejects <Case>' -TestCases @(
        @{ Case = 'a missing settings section'; Data = @{ roles = @() }; Expected = '*settings*absente*' }
        @{ Case = 'an invalid domain'; Data = @{ settings = @{ upnDomain = 'contoso'; leaverLicenseRetentionDays = 30 }; roles = @(@{ service = 'IT'; poste = 'Dev'; groups = @(); licenses = @() }) }; Expected = '*upnDomain*' }
        @{ Case = 'a negative retention'; Data = @{ settings = @{ upnDomain = 'contoso.example'; leaverLicenseRetentionDays = -1 }; roles = @(@{ service = 'IT'; poste = 'Dev'; groups = @(); licenses = @() }) }; Expected = '*leaverLicenseRetentionDays*' }
        @{ Case = 'an excessive retention'; Data = @{ settings = @{ upnDomain = 'contoso.example'; leaverLicenseRetentionDays = 99999 }; roles = @(@{ service = 'IT'; poste = 'Dev'; groups = @(); licenses = @() }) }; Expected = '*leaverLicenseRetentionDays*' }
        @{ Case = 'an empty role list'; Data = @{ settings = @{ upnDomain = 'contoso.example'; leaverLicenseRetentionDays = 30 }; roles = @() }; Expected = '*aucun rôle*' }
        @{ Case = 'a duplicated Service/Poste'; Data = @{ settings = @{ upnDomain = 'contoso.example'; leaverLicenseRetentionDays = 30 }; roles = @(@{ service = 'IT'; poste = 'Dev'; groups = @(); licenses = @() }, @{ service = 'it'; poste = 'DEV'; groups = @(); licenses = @() }) }; Expected = '*en double*' }
        @{ Case = 'a role without groups'; Data = @{ settings = @{ upnDomain = 'contoso.example'; leaverLicenseRetentionDays = 30 }; roles = @(@{ service = 'IT'; poste = 'Dev'; licenses = @() }) }; Expected = '*groups*absente*' }
        @{ Case = 'an empty group name'; Data = @{ settings = @{ upnDomain = 'contoso.example'; leaverLicenseRetentionDays = 30 }; roles = @(@{ service = 'IT'; poste = 'Dev'; groups = @(' '); licenses = @() }) }; Expected = '*noms non vides*' }
        @{ Case = 'an invalid usage location'; Data = @{ settings = @{ upnDomain = 'contoso.example'; leaverLicenseRetentionDays = 30; defaultUsageLocation = 'FRA' }; roles = @(@{ service = 'IT'; poste = 'Dev'; groups = @(); licenses = @() }) }; Expected = '*defaultUsageLocation*' }
    ) {
        { Import-TestCatalog -Data $Data } | Should -Throw $Expected
    }
}
