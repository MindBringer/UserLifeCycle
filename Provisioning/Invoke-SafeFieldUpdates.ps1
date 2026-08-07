param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [ValidateSet('Interactive','DeviceLogin')]
    [string]$AuthenticationMode = 'Interactive'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CompiledSchemaPath = Join-Path $Root 'generated/schema/compiled-schema.json'
$RestReadModule = Join-Path $PSScriptRoot 'Provisioning.RestRead.psm1'

if (-not (Test-Path $CompiledSchemaPath)) {
    throw "Kompiliertes Schema fehlt: $CompiledSchemaPath"
}

Import-Module PnP.PowerShell -ErrorAction Stop
Import-Module $RestReadModule -Force -DisableNameChecking -ErrorAction Stop

$connection = if ($AuthenticationMode -eq 'DeviceLogin') {
    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -DeviceLogin -ValidateConnection -ReturnConnection
}
else {
    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive -ValidateConnection -ReturnConnection
}

$schema = Get-Content $CompiledSchemaPath -Raw | ConvertFrom-Json -Depth 100
$updated = 0

foreach ($listDefinition in @($schema.lists)) {
    $listName = [string]$listDefinition.internalName
    $schemaFields = @($listDefinition.fields)
    if ($schemaFields.Count -eq 0) { continue }

    try {
        $existingFields = @{}
        foreach ($field in @(Get-UlcRestFields -List $listName -Connection $connection -ErrorAction Stop)) {
            $existingFields[[string]$field.InternalName] = $field
        }
    }
    catch {
        Write-Warning "Felder von $listName konnten nicht gelesen werden: $($_.Exception.Message)"
        continue
    }

    foreach ($fieldDefinition in $schemaFields) {
        $fieldName = [string]$fieldDefinition.internalName
        $existing = $existingFields[$fieldName]
        if (-not $existing) { continue }

        $shouldBeIndexed = [bool]$fieldDefinition.indexed
        $isIndexed = [bool]$existing.Indexed

        if ($shouldBeIndexed -and -not $isIndexed) {
            Write-Host "SAFE UPDATE: $listName.$fieldName -> Indexed=True"
            Set-PnPField `
                -List $listName `
                -Identity $fieldName `
                -Values @{ Indexed = $true } `
                -Connection $connection | Out-Null
            $updated++
        }
    }
}

Write-Host "SAFE FIELD UPDATE: $updated Feld(er) aktualisiert."
exit 0
