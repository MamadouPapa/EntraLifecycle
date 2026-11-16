# Secret handling: random initial password (never stored nor logged) and SecureString wrapping of
# the Temporary Access Pass returned by Graph.

# Unambiguous characters (no 0/O, 1/l/I).
$script:ELPasswordAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#$%*+-=?@'

function New-ELRandomPassword {
    <#
    .SYNOPSIS
        Cryptographically random password meeting Entra ID complexity rules. The user never needs it:
        first sign-in uses the Temporary Access Pass.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [int] $Length = $script:ELGeneratedPasswordLength
    )

    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        do {
            $bytes = New-Object byte[] $Length
            $generator.GetBytes($bytes)
            # The modulo bias over this small alphabet is negligible for a throw-away password.
            $characters = foreach ($byte in $bytes) { $script:ELPasswordAlphabet[$byte % $script:ELPasswordAlphabet.Length] }
            $candidate = -join $characters
        } until (Test-ELPasswordComplexity -Value $candidate)
        $candidate
    }
    finally {
        $generator.Dispose()
    }
}

function Test-ELPasswordComplexity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Value
    )

    ($Value -cmatch '[A-Z]') -and ($Value -cmatch '[a-z]') -and ($Value -match '[0-9]') -and ($Value -match '[^A-Za-z0-9]')
}

function ConvertTo-ELSecureString {
    <#
    .SYNOPSIS
        Copies a secret into a read-only SecureString, character by character.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param(
        [Parameter(Mandatory)] [string] $Value
    )

    $secure = New-Object System.Security.SecureString
    foreach ($character in $Value.ToCharArray()) { $secure.AppendChar($character) }
    $secure.MakeReadOnly()
    $secure
}
