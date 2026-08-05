$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$SolutionSource = Join-Path $Root 'powerplatform/src/BenutzerLifeCycle'
$CanvasSource = Join-Path $Root 'powerplatform/canvas-src/gp_blcroleentitlementmanager'
$GeneratedRoot = Join-Path $Root 'powerplatform/generated/build'
$StagingSolution = Join-Path $GeneratedRoot 'BenutzerLifeCycle'
$StagingCanvas = Join-Path $StagingSolution 'CanvasApps/gp_blcroleentitlementmanager_8c1d9_DocumentUri.msapp'

& (Join-Path $PSScriptRoot 'Validate-Solution.ps1')
& python3 (Join-Path $Root 'tools/companion/audit_repo.py')
if ($LASTEXITCODE -ne 0) { throw "Repository-Audit fehlgeschlagen (Exit $LASTEXITCODE)." }

$Version = (Get-Content (Join-Path $Root 'powerplatform/VERSION') -Raw).Trim()
$ExportDir = Join-Path $Root 'export'
$Zip = Join-Path $ExportDir "BenutzerLifeCycle_$Version.zip"

if (Test-Path $GeneratedRoot) { Remove-Item $GeneratedRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StagingSolution | Out-Null
New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null
Copy-Item -Path (Join-Path $SolutionSource '*') -Destination $StagingSolution -Recurse -Force

Write-Host 'CANVAS PACK: SourceCode -> staging .msapp'
& pac canvas pack `
    --sources $CanvasSource `
    --msapp $StagingCanvas `
    --layout SourceCode `
    --overwrite
if ($LASTEXITCODE -ne 0) { throw "pac canvas pack fehlgeschlagen (Exit $LASTEXITCODE)." }
if (-not (Test-Path $StagingCanvas)) { throw "Canvas-Pack hat keine .msapp erzeugt: $StagingCanvas" }

if (Test-Path $Zip) { Remove-Item $Zip -Force }
Write-Host 'SOLUTION PACK: staging Solution -> unmanaged ZIP'
& pac solution pack `
    --zipfile $Zip `
    --folder $StagingSolution `
    --packagetype Unmanaged
if ($LASTEXITCODE -ne 0) { throw "pac solution pack fehlgeschlagen (Exit $LASTEXITCODE)." }
if (-not (Test-Path $Zip)) { throw "Solution-Pack hat kein ZIP erzeugt: $Zip" }

Write-Host "BUILD: OK · Canvas aus SourceCode gepackt · $Zip"
