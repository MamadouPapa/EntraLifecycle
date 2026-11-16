BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ELTestModulePath -Force
}

AfterAll {
    Remove-Module EntraLifecycle -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-ELAsciiText' {
    It 'removes French diacritics: <Text> -> <Expected>' -TestCases @(
        @{ Text = 'Élodie Gérard'; Expected = 'Elodie Gerard' }
        @{ Text = 'François Lefèvre'; Expected = 'Francois Lefevre' }
        @{ Text = 'Inès Chloé Noël'; Expected = 'Ines Chloe Noel' }
        @{ Text = 'Ægir Cœur Œdipe Straße'; Expected = 'AEgir Coeur OEdipe Strasse' }
        @{ Text = 'Łukasz Øyvind'; Expected = 'Lukasz Oyvind' }
    ) {
        InModuleScope EntraLifecycle -Parameters @{ Text = $Text } {
            param($Text)
            ConvertTo-ELAsciiText -Text $Text
        } | Should -BeExactly $Expected
    }

    It 'returns an empty string for null or empty input' {
        InModuleScope EntraLifecycle { ConvertTo-ELAsciiText -Text $null } | Should -BeExactly ''
        InModuleScope EntraLifecycle { ConvertTo-ELAsciiText -Text '' } | Should -BeExactly ''
    }
}

Describe 'ConvertTo-ELUpnPart' {
    It 'normalizes <Text> -> <Expected>' -TestCases @(
        @{ Text = 'Jean-François'; Expected = 'jean-francois' }
        @{ Text = 'Jean François'; Expected = 'jean-francois' }
        @{ Text = "N'Diaye"; Expected = 'ndiaye' }
        @{ Text = ('N{0}Diaye' -f [char]0x2019); Expected = 'ndiaye' }
        @{ Text = 'De La Fontaine'; Expected = 'de-la-fontaine' }
        @{ Text = '  Gérard--Lefèvre  '; Expected = 'gerard-lefevre' }
        @{ Text = 'O.Brien_Smith'; Expected = 'o-brien-smith' }
        @{ Text = 'Zoé (2)'; Expected = 'zoe-2' }
    ) {
        InModuleScope EntraLifecycle -Parameters @{ Text = $Text } {
            param($Text)
            ConvertTo-ELUpnPart -Text $Text
        } | Should -BeExactly $Expected
    }
}

Describe 'New-ELUserPrincipalName' {
    It 'builds prenom.nom@domain in lowercase ASCII' {
        InModuleScope EntraLifecycle {
            New-ELUserPrincipalName -GivenName 'Élodie' -Surname 'Gérard-Lefèvre' -Domain 'Contoso.Example' -TakenUpn (New-ELNameSet)
        } | Should -BeExactly 'elodie.gerard-lefevre@contoso.example'
    }

    It 'adds a numeric suffix for homonyms (case-insensitive)' {
        InModuleScope EntraLifecycle {
            $taken = New-ELNameSet -Values @('CAMILLE.DUBOIS@contoso.example')
            New-ELUserPrincipalName -GivenName 'Camille' -Surname 'Dubois' -Domain 'contoso.example' -TakenUpn $taken
        } | Should -BeExactly 'camille.dubois2@contoso.example'
    }

    It 'skips every suffix already taken' {
        InModuleScope EntraLifecycle {
            $taken = New-ELNameSet -Values @('camille.dubois@contoso.example', 'camille.dubois2@contoso.example', 'camille.dubois3@contoso.example')
            New-ELUserPrincipalName -GivenName 'Camille' -Surname 'Dubois' -Domain 'contoso.example' -TakenUpn $taken
        } | Should -BeExactly 'camille.dubois4@contoso.example'
    }

    It 'gives a different UPN to an accented homonym (Hélène vs Helene)' {
        InModuleScope EntraLifecycle {
            $taken = New-ELNameSet -Values @('helene.durand@contoso.example')
            New-ELUserPrincipalName -GivenName 'Hélène' -Surname 'Durand' -Domain 'contoso.example' -TakenUpn $taken
        } | Should -BeExactly 'helene.durand2@contoso.example'
    }

    It 'truncates the local part so that it never exceeds 64 characters, suffix included' {
        $upn = InModuleScope EntraLifecycle {
            $long = 'a' * 50
            $taken = New-ELNameSet -Values @(('{0}.{1}' -f $long, $long).Substring(0, 62) + '@contoso.example')
            New-ELUserPrincipalName -GivenName $long -Surname $long -Domain 'contoso.example' -TakenUpn $taken
        }
        $upn.Split('@')[0].Length | Should -BeLessOrEqual 64
        $upn | Should -Match '2@contoso\.example$'
    }

    It 'throws when a name has no usable character' {
        { InModuleScope EntraLifecycle { New-ELUserPrincipalName -GivenName '???' -Surname 'Martin' -Domain 'contoso.example' -TakenUpn $null } } |
            Should -Throw '*prénom ou nom sans caractère exploitable*'
    }

    It 'throws when every suffix is taken' {
        { InModuleScope EntraLifecycle {
                $values = @('jo.li@contoso.example') + @(2..99 | ForEach-Object { 'jo.li{0}@contoso.example' -f $_ })
                New-ELUserPrincipalName -GivenName 'Jo' -Surname 'Li' -Domain 'contoso.example' -TakenUpn (New-ELNameSet -Values $values)
            } } | Should -Throw '*Aucun UPN libre*'
    }
}

Describe 'New-ELRandomPassword' {
    It 'meets complexity rules and is different every time' {
        $passwords = InModuleScope EntraLifecycle { 1..5 | ForEach-Object { New-ELRandomPassword } }
        foreach ($password in $passwords) {
            $password.Length | Should -Be 32
            $password | Should -MatchExactly '[A-Z]'
            $password | Should -MatchExactly '[a-z]'
            $password | Should -Match '[0-9]'
            $password | Should -Match '[^A-Za-z0-9]'
        }
        @($passwords | Sort-Object -Unique).Count | Should -Be 5
    }
}
