param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('DryRun','Apply','Validate')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [ValidateSet('Interactive','DeviceLogin')]
    [string]$AuthenticationMode = 'Interactive',

    [string]$OutputDirectory = './generated/provisioning',

    [ValidateRange(1,10)]
    [int]$RetryCount = 3,

    [ValidateRange(1,60)]
    [int]$RetryDelaySeconds = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CompileScript = Join-Path $PSScriptRoot 'Compile-Schema.ps1'
$CompiledSchemaPath = Join-Path $Root 'generated/schema/compiled-schema.json'
$OutputPath = [System.IO.Path]::GetFullPath((Join-Path $Root $OutputDirectory))
$RestReadModule = Join-Path $PSScriptRoot 'Provisioning.RestRead.psm1'

Import-Module PnP.PowerShell -ErrorAction Stop
Import-Module $RestReadModule -Force -DisableNameChecking -ErrorAction Stop

function Connect-TargetSite {
    if ($AuthenticationMode -eq 'DeviceLogin') {
        return Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -DeviceLogin -ReturnConnection
    }
    return Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive -ReturnConnection
}

function Invoke-PnPWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            return & $Operation
        }
        catch {
            if ($attempt -ge $RetryCount) { throw }
            Write-Warning "$Description fehlgeschlagen (Versuch $attempt/$RetryCount): $($_.Exception.Message)"
            Start-Sleep -Seconds ($RetryDelaySeconds * $attempt)
        }
    }
}

function Get-TargetList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identity,
        [Parameter(Mandatory = $true)]
        $Connection
    )

    try {
        return Invoke-PnPWithRetry -Description "Liste $Identity laden" -Operation {
            Get-UlcRestList -Identity $Identity -Connection $Connection -ErrorAction Stop
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match 'does not exist|cannot be found|File Not Found|404') { return $null }
        throw
    }
}

function Get-BooleanXmlValue([bool]$Value) {
    if ($Value) { return 'TRUE' }
    return 'FALSE'
}

function Get-ExpectedFieldType([string]$Type) {
    switch ($Type) {
        'Text'        { 'Text' }
        'Note'        { 'Note' }
        'Boolean'     { 'Boolean' }
        'Number'      { 'Number' }
        'Currency'    { 'Currency' }
        'DateTime'    { 'DateTime' }
        'Choice'      { 'Choice' }
        'MultiChoice' { 'MultiChoice' }
        'User'        { 'User' }
        'UserMulti'   { 'UserMulti' }
        'URL'         { 'URL' }
        'Lookup'      { 'Lookup' }
        'LookupMulti' { 'LookupMulti' }
        default       { throw "Nicht unterstützter Feldtyp: $Type" }
    }
}

function New-FieldXml($Field, $LookupListId = $null) {
    $type = Get-ExpectedFieldType $Field.type
    $required = Get-BooleanXmlValue ([bool]($Field.required -eq $true))
    $indexed = Get-BooleanXmlValue ([bool]($Field.indexed -eq $true))
    $unique = Get-BooleanXmlValue ([bool]($Field.unique -eq $true))
    $name = [System.Security.SecurityElement]::Escape([string]$Field.internalName)
    $displayName = [System.Security.SecurityElement]::Escape([string]$Field.displayName)
    $multi = if ($type -in @('LookupMulti','UserMulti')) { 'TRUE' } else { 'FALSE' }

    if ($type -in @('Lookup','LookupMulti')) {
        if (-not $LookupListId) { throw "Lookup-Zielliste fehlt für $name." }
        $lookupField = if ($Field.lookupField) { [string]$Field.lookupField } else { 'Title' }
        return "<Field Type='$type' Name='$name' StaticName='$name' DisplayName='$displayName' Required='$required' Indexed='$indexed' EnforceUniqueValues='$unique' Mult='$multi' List='{$LookupListId}' ShowField='$lookupField' RelationshipDeleteBehavior='Restrict' Group='UserLifeCycle 2.0' />"
    }

    if ($type -in @('User','UserMulti')) {
        return "<Field Type='User' Name='$name' StaticName='$name' DisplayName='$displayName' Required='$required' Indexed='$indexed' EnforceUniqueValues='$unique' Mult='$multi' UserSelectionMode='PeopleOnly' Group='UserLifeCycle 2.0' />"
    }

    if ($type -in @('Choice','MultiChoice')) {
        $choices = @($Field.choices | ForEach-Object { '<CHOICE>' + [System.Security.SecurityElement]::Escape([string]$_) + '</CHOICE>' }) -join ''
        return "<Field Type='$type' Name='$name' StaticName='$name' DisplayName='$displayName' Required='$required' Indexed='$indexed' EnforceUniqueValues='$unique' Group='UserLifeCycle 2.0'><CHOICES>$choices</CHOICES></Field>"
    }

    return "<Field Type='$type' Name='$name' StaticName='$name' DisplayName='$displayName' Required='$required' Indexed='$indexed' EnforceUniqueValues='$unique' Group='UserLifeCycle 2.0' />"
}

function Add-Result([System.Collections.Generic.List[object]]$Results, [string]$ObjectType, [string]$ObjectName, [string]$Action, [string]$Status, [string]$Details = '') {
    $Results.Add([pscustomobject]@{
        ObjectType = $ObjectType
        ObjectName = $ObjectName
        Action = $Action
        Status = $Status
        Details = $Details
    })
}

function Write-Reports($Results, $Schema) {
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $OutputPath "provisioning-$($Mode.ToLowerInvariant())-$timestamp.json"
    $csvPath = Join-Path $OutputPath "provisioning-$($Mode.ToLowerInvariant())-$timestamp.csv"
    $htmlPath = Join-Path $OutputPath "provisioning-$($Mode.ToLowerInvariant())-$timestamp.html"

    $payload = [ordered]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = $Mode
        siteUrl = $SiteUrl
        schemaVersion = $Schema.schemaVersion
        summary = [ordered]@{
            total = $Results.Count
            ok = @($Results | Where-Object Status -eq 'OK').Count
            planned = @($Results | Where-Object Status -eq 'PLANNED').Count
            differences = @($Results | Where-Object Status -eq 'DIFFERENCE').Count
            errors = @($Results | Where-Object Status -eq 'ERROR').Count
        }
        results = @($Results)
    }
    $payload | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8
    $Results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    $rows = foreach ($result in $Results) {
        $class = switch ($result.Status) { 'OK' {'ok'} 'PLANNED' {'planned'} 'DIFFERENCE' {'difference'} default {'error'} }
        "<tr class='$class'><td>$([System.Net.WebUtility]::HtmlEncode($result.ObjectType))</td><td>$([System.Net.WebUtility]::HtmlEncode($result.ObjectName))</td><td>$([System.Net.WebUtility]::HtmlEncode($result.Action))</td><td>$([System.Net.WebUtility]::HtmlEncode($result.Status))</td><td>$([System.Net.WebUtility]::HtmlEncode($result.Details))</td></tr>"
    }
    $html = @"
<!doctype html><html lang='de'><head><meta charset='utf-8'><title>UserLifeCycle Provisioning $Mode</title>
<style>body{font-family:system-ui;margin:24px;color:#172033}table{border-collapse:collapse;width:100%}th,td{border:1px solid #d7deea;padding:7px;text-align:left}th{background:#eef2f7}.ok{background:#ecfdf5}.planned{background:#eff6ff}.difference{background:#fff7ed}.error{background:#fef2f2}code{background:#eef2f7;padding:2px 4px}</style></head><body>
<h1>UserLifeCycle Provisioning – $Mode</h1><p>Site: <code>$([System.Net.WebUtility]::HtmlEncode($SiteUrl))</code> · Schema: <code>$($Schema.schemaVersion)</code></p>
<p>OK: $($payload.summary.ok) · geplant: $($payload.summary.planned) · Abweichungen: $($payload.summary.differences) · Fehler: $($payload.summary.errors)</p>
<table><thead><tr><th>Typ</th><th>Objekt</th><th>Aktion</th><th>Status</th><th>Details</th></tr></thead><tbody>$($rows -join "`n")</tbody></table></body></html>
"@
    Set-Content -Path $htmlPath -Value $html -Encoding UTF8
    Write-Host "REPORT JSON: $jsonPath"
    Write-Host "REPORT CSV:  $csvPath"
    Write-Host "REPORT HTML: $htmlPath"
}

& $CompileScript
if ($LASTEXITCODE -ne 0) { throw 'Schema-Kompilierung fehlgeschlagen.' }
if (-not (Test-Path $CompiledSchemaPath)) { throw "Kompiliertes Schema fehlt: $CompiledSchemaPath" }
$Schema = Get-Content $CompiledSchemaPath -Raw | ConvertFrom-Json -Depth 100
$Connection = Connect-TargetSite
$Results = [System.Collections.Generic.List[object]]::new()
$aborted = $false

try {
    $existingLists = @{}

    foreach ($listDefinition in $Schema.lists) {
        $internalName = [string]$listDefinition.internalName
        $displayName = [string]$listDefinition.displayName
        $description = [string]$listDefinition.description
        $existing = Get-TargetList -Identity $internalName -Connection $Connection

        if ($existing) { $existingLists[$internalName] = $existing }

        if (-not $existing) {
            if ($Mode -eq 'Apply') {
                Invoke-PnPWithRetry -Description "Liste $internalName anlegen" -Operation {
                    New-PnPList -Title $internalName -Url "Lists/$internalName" -Template GenericList -EnableVersioning -Connection $Connection | Out-Null
                } | Out-Null
                Invoke-PnPWithRetry -Description "Liste $internalName konfigurieren" -Operation {
                    Set-PnPList -Identity $internalName -Title $internalName -Description $description -EnableVersioning $true -Connection $Connection | Out-Null
                } | Out-Null
                $existing = Get-TargetList -Identity $internalName -Connection $Connection
                $existingLists[$internalName] = $existing
                Add-Result $Results 'List' $internalName 'Create' 'OK' "Anzeigename: $displayName"
            } else {
                Add-Result $Results 'List' $internalName 'Create' 'PLANNED' "Anzeigename: $displayName"
            }
        } else {
            Add-Result $Results 'List' $internalName 'None' 'OK' 'Liste vorhanden'
        }
    }

    foreach ($listDefinition in $Schema.lists) {
        $listName = [string]$listDefinition.internalName
        if (-not $existingLists[$listName] -and $Mode -ne 'Apply') {
            foreach ($field in @($listDefinition.fields)) {
                Add-Result $Results 'Field' "$listName.$($field.internalName)" 'Create' 'PLANNED' "Typ $($field.type)"
            }
            continue
        }

        $existingFields = @{}
        if ($existingLists[$listName]) {
            $fields = Invoke-PnPWithRetry -Description "Felder von $listName laden" -Operation {
                @(Get-UlcRestFields -List $listName -Connection $Connection -ErrorAction Stop)
            }
            foreach ($existingFieldItem in @($fields)) { $existingFields[$existingFieldItem.InternalName] = $existingFieldItem }
        }

        foreach ($field in @($listDefinition.fields)) {
            $fieldName = [string]$field.internalName
            $objectName = "$listName.$fieldName"
            $existingField = $existingFields[$fieldName]
            $expectedType = Get-ExpectedFieldType ([string]$field.type)

            if (-not $existingField) {
                if ($Mode -eq 'Apply') {
                    $lookupListId = $null
                    if ($expectedType -in @('Lookup','LookupMulti')) {
                        $targetName = [string]$field.lookupList
                        $targetList = $existingLists[$targetName]
                        if (-not $targetList) { $targetList = Get-TargetList -Identity $targetName -Connection $Connection }
                        if (-not $targetList) { throw "Lookup-Zielliste $targetName fehlt für $objectName." }
                        $lookupListId = $targetList.Id
                    }
                    $xml = New-FieldXml $field $lookupListId
                    Invoke-PnPWithRetry -Description "Feld $objectName anlegen" -Operation {
                        Add-PnPFieldFromXml -List $listName -FieldXml $xml -Connection $Connection | Out-Null
                    } | Out-Null
                    Add-Result $Results 'Field' $objectName 'Create' 'OK' "Typ $expectedType"
                } else {
                    Add-Result $Results 'Field' $objectName 'Create' 'PLANNED' "Typ $expectedType"
                }
                continue
            }

            $differences = [System.Collections.Generic.List[string]]::new()
            if ([string]$existingField.TypeAsString -ne $expectedType -and -not ($expectedType -eq 'UserMulti' -and $existingField.TypeAsString -eq 'User')) { $differences.Add("Typ Ist=$($existingField.TypeAsString), Soll=$expectedType") }
            if ([bool]$existingField.Required -ne [bool]($field.required -eq $true)) { $differences.Add("Required Ist=$($existingField.Required), Soll=$($field.required -eq $true)") }
            if ([bool]$existingField.Indexed -ne [bool]($field.indexed -eq $true)) { $differences.Add("Indexed Ist=$($existingField.Indexed), Soll=$($field.indexed -eq $true)") }
            if ([bool]$existingField.EnforceUniqueValues -ne [bool]($field.unique -eq $true)) { $differences.Add("Unique Ist=$($existingField.EnforceUniqueValues), Soll=$($field.unique -eq $true)") }
            if ($expectedType -in @('Choice','MultiChoice')) {
                $actual = @($existingField.Choices | Sort-Object)
                $expected = @($field.choices | Sort-Object)
                if (($actual -join '|') -ne ($expected -join '|')) { $differences.Add('Choices abweichend') }
            }

            if ($differences.Count -eq 0) {
                Add-Result $Results 'Field' $objectName 'None' 'OK' 'Feld entspricht dem Schema'
            } else {
                Add-Result $Results 'Field' $objectName 'Review' 'DIFFERENCE' ($differences -join '; ')
            }
        }
    }
}
catch {
    $aborted = $true
    Add-Result $Results 'Provisioning' $Mode 'Abort' 'ERROR' $_.Exception.Message
}
finally {
    Write-Reports $Results $Schema
}

$differences = @($Results | Where-Object Status -eq 'DIFFERENCE').Count
$errors = @($Results | Where-Object Status -eq 'ERROR').Count
Write-Host "PROVISIONING $Mode`: $($Results.Count) Prüfungen · $differences Abweichungen · $errors Fehler"
if ($aborted -or $errors -gt 0) { exit 1 }
if ($Mode -eq 'Validate' -and $differences -gt 0) { exit 2 }
exit 0
