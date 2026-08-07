param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('DryRun','Apply','Validate')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$SettingsPath = Join-Path $PSScriptRoot 'settings.local.psd1'
if (-not (Test-Path $SettingsPath)) { throw "Lokale Einstellungen fehlen: $SettingsPath" }
$Settings = Import-PowerShellDataFile $SettingsPath
foreach ($required in @('SiteUrl','ClientId')) {
    if (-not $Settings[$required]) { throw "Einstellung '$required' fehlt in $SettingsPath." }
}
$authenticationMode = if ($Settings.AuthenticationMode) { [string]$Settings.AuthenticationMode } else { 'Interactive' }
& (Join-Path $PSScriptRoot 'Invoke-Seed.ps1') `
    -Mode $Mode `
    -SiteUrl ([string]$Settings.SiteUrl) `
    -ClientId ([string]$Settings.ClientId) `
    -AuthenticationMode $authenticationMode
exit $LASTEXITCODE
