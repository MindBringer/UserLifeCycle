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

# PnP zuerst laden; danach überschreibt das lokale Modul nur die langsamen
# Lese-Cmdlets mit schlanken SharePoint-REST-Implementierungen.
Import-Module PnP.PowerShell -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Provisioning.RestRead.psm1') -Force -DisableNameChecking

$authenticationMode = if ($Settings.AuthenticationMode) { [string]$Settings.AuthenticationMode } else { 'Interactive' }
& (Join-Path $PSScriptRoot 'Invoke-Provisioning.ps1') `
    -Mode $Mode `
    -SiteUrl ([string]$Settings.SiteUrl) `
    -ClientId ([string]$Settings.ClientId) `
    -AuthenticationMode $authenticationMode

$provisioningExitCode = $LASTEXITCODE
if ($provisioningExitCode -ne 0) {
    exit $provisioningExitCode
}

# Apply darf bestehende Felder nur über explizit freigegebene, nicht-destruktive
# Änderungen angleichen. Aktuell: fehlende Indizes auf bestehenden Feldern.
if ($Mode -eq 'Apply') {
    & (Join-Path $PSScriptRoot 'Invoke-SafeFieldUpdates.ps1') `
        -SiteUrl ([string]$Settings.SiteUrl) `
        -ClientId ([string]$Settings.ClientId) `
        -AuthenticationMode $authenticationMode

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

exit 0
