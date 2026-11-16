# EntraLifecycle root module: loads private helpers first, then public entry points.

$script:ELModuleRoot = $PSScriptRoot
$script:ELVersion = (Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'EntraLifecycle.psd1')).ModuleVersion
$script:ELDemoFixturePath = Join-Path $PSScriptRoot 'Data/demo-tenant.json'

$privateFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -Recurse)
$publicFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -Recurse)

foreach ($file in ($privateFiles + $publicFiles)) {
    try {
        . $file.FullName
    }
    catch {
        throw "EntraLifecycle: unable to load '$($file.FullName)': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function ($publicFiles | ForEach-Object { $_.BaseName })
