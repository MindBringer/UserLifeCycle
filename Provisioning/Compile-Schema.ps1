param(
    [string]$OutputDirectory = "./generated/schema"
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Generator = Join-Path $Root "tools/schema/generator.py"
$SchemaDir = Join-Path $Root "schema"
$Output = [System.IO.Path]::GetFullPath((Join-Path $Root $OutputDirectory))

if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
    throw "python3 wurde nicht gefunden."
}
if (-not (Test-Path $Generator)) {
    throw "Schema-Generator fehlt: $Generator"
}

& python3 $Generator --schema-dir $SchemaDir --output-dir $Output
if ($LASTEXITCODE -ne 0) {
    throw "Schema-Compile fehlgeschlagen (Exit $LASTEXITCODE)."
}
