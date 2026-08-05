$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$Source = Join-Path $Root 'powerplatform/src/BenutzerLifeCycle'
$VersionFile = Join-Path $Root 'powerplatform/VERSION'

if (-not (Test-Path $VersionFile)) { throw 'powerplatform/VERSION fehlt.' }
if (-not (Test-Path (Join-Path $Source 'Other/Solution.xml'))) { throw 'Other/Solution.xml fehlt.' }
if (-not (Test-Path (Join-Path $Source 'Other/Customizations.xml'))) { throw 'Other/Customizations.xml fehlt.' }
$Apps = @(Get-ChildItem (Join-Path $Source 'CanvasApps') -Filter '*_DocumentUri.msapp' -File -ErrorAction Stop)
if ($Apps.Count -ne 1) { throw "Genau eine Canvas-App erwartet, gefunden: $($Apps.Count)." }
$Flows = @(Get-ChildItem (Join-Path $Source 'Workflows') -Filter '*.json' -File -ErrorAction Stop)
if ($Flows.Count -lt 1) { throw 'Keine Power-Automate-Workflows gefunden.' }
Write-Host "VALIDIERUNG: OK · Version $((Get-Content $VersionFile -Raw).Trim()) · 1 Canvas-App · $($Flows.Count) Flows"
