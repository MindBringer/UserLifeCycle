$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$Source = Join-Path $Root 'powerplatform/src/BenutzerLifeCycle'
$CanvasSource = Join-Path $Root 'powerplatform/canvas-src/gp_blcroleentitlementmanager'
$CanvasSrcFolder = Join-Path $CanvasSource 'Src'
$VersionFile = Join-Path $Root 'powerplatform/VERSION'

if (-not (Test-Path $VersionFile)) { throw 'powerplatform/VERSION fehlt.' }
if (-not (Test-Path (Join-Path $Source 'Other/Solution.xml'))) { throw 'Other/Solution.xml fehlt.' }
if (-not (Test-Path (Join-Path $Source 'Other/Customizations.xml'))) { throw 'Other/Customizations.xml fehlt.' }

$Apps = @(Get-ChildItem (Join-Path $Source 'CanvasApps') -Filter '*_DocumentUri.msapp' -File -ErrorAction Stop)
if ($Apps.Count -ne 1) { throw "Genau eine Canvas-App in der Solution erwartet, gefunden: $($Apps.Count)." }

if (-not (Test-Path $CanvasSource -PathType Container)) { throw "Kanonischer Canvas-SourceTree fehlt: $CanvasSource" }
if (-not (Test-Path (Join-Path $CanvasSrcFolder 'App.pa.yaml') -PathType Leaf)) { throw 'SourceCode-Layout ungültig: Src/App.pa.yaml fehlt.' }
$CanvasYaml = @(Get-ChildItem $CanvasSrcFolder -Filter '*.pa.yaml' -File -Recurse -ErrorAction Stop)
if ($CanvasYaml.Count -lt 2) { throw "Mindestens App.pa.yaml und ein Screen erwartet, gefunden: $($CanvasYaml.Count) YAML-Dateien." }

$Flows = @(Get-ChildItem (Join-Path $Source 'Workflows') -Filter '*.json' -File -ErrorAction Stop)
if ($Flows.Count -lt 1) { throw 'Keine Power-Automate-Workflows gefunden.' }

$Version = (Get-Content $VersionFile -Raw).Trim()
Write-Host "VALIDIERUNG: OK · Version $Version · 1 Canvas-App · $($CanvasYaml.Count) Canvas-YAML-Dateien · $($Flows.Count) Flows"
