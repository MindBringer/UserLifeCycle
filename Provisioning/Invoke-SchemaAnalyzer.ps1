param(
    [string]$SchemaPath = "./docs/assessment/sharepoint-schema.json",
    [string]$TargetModelPath = "./Provisioning/schema-target.json",
    [string]$OutputDirectory = "./docs/assessment/generated"
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$arguments = @(
    (Join-Path $Root 'tools/schema_analyzer.py'),
    '--schema', (Join-Path $Root $SchemaPath.TrimStart('./')),
    '--target', (Join-Path $Root $TargetModelPath.TrimStart('./')),
    '--canvas', (Join-Path $Root 'powerplatform/canvas-src'),
    '--flows', (Join-Path $Root 'powerplatform/src/BenutzerLifeCycle/Workflows'),
    '--provisioning', (Join-Path $Root 'Provisioning'),
    '--output', (Join-Path $Root $OutputDirectory.TrimStart('./'))
)

& python3 @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Schema Analyzer fehlgeschlagen (Exit $LASTEXITCODE)."
}
