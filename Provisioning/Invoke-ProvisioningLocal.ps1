param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('DryRun','Apply','Validate')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$SettingsPath = Join-Path $PSScriptRoot 'settings.local.psd1'
if (-not (Test-Path $SettingsPath)) {
    throw "Lokale Einstellungen fehlen. Kopiere Provisioning/settings.example.psd1 nach Provisioning/settings.local.psd1 und trage SiteUrl sowie ClientId ein."
}

$Settings = Import-PowerShellDataFile $SettingsPath
foreach ($required in @('SiteUrl','ClientId')) {
    if (-not $Settings[$required]) { throw "Einstellung '$required' fehlt in $SettingsPath." }
}

Import-Module (Join-Path $PSScriptRoot 'Provisioning.RestRead.psm1') -Force -DisableNameChecking

$authenticationMode = if ($Settings.AuthenticationMode) { [string]$Settings.AuthenticationMode } else { 'Interactive' }
& (Join-Path $PSScriptRoot 'Invoke-Provisioning.ps1') `
    -Mode $Mode `
    -SiteUrl ([string]$Settings.SiteUrl) `
    -ClientId ([string]$Settings.ClientId) `
    -AuthenticationMode $authenticationMode
exit $LASTEXITCODE
