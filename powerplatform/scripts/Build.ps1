$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
& (Join-Path $PSScriptRoot 'Validate-Solution.ps1')
& python3 (Join-Path $Root 'tools/companion/audit_repo.py')
$Version = (Get-Content (Join-Path $Root 'powerplatform/VERSION') -Raw).Trim()
$ExportDir = Join-Path $Root 'export'
New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null
$Zip = Join-Path $ExportDir "BenutzerLifeCycle_$Version.zip"
if (Test-Path $Zip) { Remove-Item $Zip -Force }
& pac solution pack --zipfile $Zip --folder (Join-Path $Root 'powerplatform/src/BenutzerLifeCycle') --packagetype Unmanaged
if ($LASTEXITCODE -ne 0) { throw "pac solution pack fehlgeschlagen (Exit $LASTEXITCODE)." }
Write-Host "BUILD: OK · $Zip"
