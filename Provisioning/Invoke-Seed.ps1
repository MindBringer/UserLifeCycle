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

    [string]$SeedManifest = './schema/seed/manifest.json',

    [string]$OutputDirectory = './generated/seed'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ManifestPath = [System.IO.Path]::GetFullPath((Join-Path $Root $SeedManifest))
$OutputPath = [System.IO.Path]::GetFullPath((Join-Path $Root $OutputDirectory))

Import-Module PnP.PowerShell -ErrorAction Stop

function Connect-TargetSite {
    if ($AuthenticationMode -eq 'DeviceLogin') {
        return Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -DeviceLogin -ValidateConnection -ReturnConnection
    }
    return Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive -ValidateConnection -ReturnConnection
}

function Get-PropertyValue($Object, [string]$Name, $Default = $null) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Write-SeedReport($Rows, $Manifest) {
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $OutputPath "seed-$($Mode.ToLowerInvariant())-$timestamp.json"
    $csvPath = Join-Path $OutputPath "seed-$($Mode.ToLowerInvariant())-$timestamp.csv"
    $htmlPath = Join-Path $OutputPath "seed-$($Mode.ToLowerInvariant())-$timestamp.html"

    $payload = [ordered]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = $Mode
        siteUrl = $SiteUrl
        seedVersion = $Manifest.seedVersion
        summary = [ordered]@{
            total = @($Rows).Count
            ok = @($Rows | Where-Object Status -eq 'OK').Count
            planned = @($Rows | Where-Object Status -eq 'PLANNED').Count
            differences = @($Rows | Where-Object Status -eq 'DIFFERENCE').Count
            errors = @($Rows | Where-Object Status -eq 'ERROR').Count
        }
        results = @($Rows)
    }

    $payload | ConvertTo-Json -Depth 15 | Set-Content -Path $jsonPath -Encoding UTF8
    $Rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $bodyRows = foreach ($row in $Rows) {
        "<tr><td>$([System.Net.WebUtility]::HtmlEncode($row.Set))</td><td>$([System.Net.WebUtility]::HtmlEncode($row.Key))</td><td>$($row.Action)</td><td>$($row.Status)</td><td>$([System.Net.WebUtility]::HtmlEncode($row.Details))</td></tr>"
    }
    $html = @"
<!doctype html><html lang='de'><head><meta charset='utf-8'><title>UserLifeCycle Seed $Mode</title>
<style>body{font-family:system-ui;margin:24px;color:#172033}table{border-collapse:collapse;width:100%}th,td{border:1px solid #d7deea;padding:7px;text-align:left}th{background:#eef2f7}</style></head><body>
<h1>UserLifeCycle Seed – $Mode</h1><p>Version: $($Manifest.seedVersion) · Site: $([System.Net.WebUtility]::HtmlEncode($SiteUrl))</p>
<table><thead><tr><th>Set</th><th>Schlüssel</th><th>Aktion</th><th>Status</th><th>Details</th></tr></thead><tbody>$($bodyRows -join "`n")</tbody></table></body></html>
"@
    Set-Content -Path $htmlPath -Value $html -Encoding UTF8
    Write-Host "SEED REPORT JSON: $jsonPath"
    Write-Host "SEED REPORT CSV:  $csvPath"
    Write-Host "SEED REPORT HTML: $htmlPath"
}

if (-not (Test-Path $ManifestPath)) { throw "Seed-Manifest fehlt: $ManifestPath" }
$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json -Depth 50
$Connection = Connect-TargetSite
$rows = [System.Collections.Generic.List[object]]::new()

foreach ($set in @($Manifest.sets)) {
    $setName = [string](Get-PropertyValue $set 'name' '')
    $listName = [string](Get-PropertyValue $set 'list' '')
    $keyField = [string](Get-PropertyValue $set 'keyField' 'Title')
    $dataFile = [string](Get-PropertyValue $set 'file' '')

    if ([string]::IsNullOrWhiteSpace($setName) -or [string]::IsNullOrWhiteSpace($listName) -or [string]::IsNullOrWhiteSpace($dataFile)) {
        $rows.Add([pscustomobject]@{ Set=$setName; Key=''; Action='Validate'; Status='ERROR'; Details='Seed-Set ist unvollständig definiert.' })
        continue
    }

    $dataPath = [System.IO.Path]::GetFullPath((Join-Path (Split-Path $ManifestPath -Parent) $dataFile))
    if (-not (Test-Path $dataPath)) {
        $rows.Add([pscustomobject]@{ Set=$setName; Key=''; Action='Read'; Status='ERROR'; Details="Seed-Datei fehlt: $dataPath" })
        continue
    }

    try { $null = Get-PnPList -Identity $listName -Connection $Connection -ErrorAction Stop }
    catch {
        $rows.Add([pscustomobject]@{ Set=$setName; Key=''; Action='Read'; Status='ERROR'; Details="Zielliste fehlt: $listName" })
        continue
    }

    $items = @(Get-Content $dataPath -Raw | ConvertFrom-Json -Depth 50)
    foreach ($item in $items) {
        $valuesProperty = $item.PSObject.Properties['values']
        if ($null -eq $valuesProperty) {
            $rows.Add([pscustomobject]@{ Set=$setName; Key=''; Action='Validate'; Status='ERROR'; Details='Seed-Element ohne values.' })
            continue
        }
        $values = @{}
        foreach ($property in $valuesProperty.Value.PSObject.Properties) { $values[$property.Name] = $property.Value }
        $key = [string]$values[$keyField]
        if ([string]::IsNullOrWhiteSpace($key)) {
            $rows.Add([pscustomobject]@{ Set=$setName; Key=''; Action='Validate'; Status='ERROR'; Details="Schlüsselfeld $keyField fehlt." })
            continue
        }

        $escapedKey = $key.Replace("'", "''")
        $existing = @(Get-PnPListItem -List $listName -Query "<View><Query><Where><Eq><FieldRef Name='$keyField'/><Value Type='Text'>$escapedKey</Value></Eq></Where></Query><RowLimit>2</RowLimit></View>" -Connection $Connection)
        if ($existing.Count -gt 1) {
            $rows.Add([pscustomobject]@{ Set=$setName; Key=$key; Action='Review'; Status='ERROR'; Details='Mehrere Datensätze mit demselben Schlüssel.' })
            continue
        }

        if ($existing.Count -eq 0) {
            if ($Mode -eq 'Apply') {
                Add-PnPListItem -List $listName -Values $values -Connection $Connection | Out-Null
                $rows.Add([pscustomobject]@{ Set=$setName; Key=$key; Action='Create'; Status='OK'; Details='Seed-Datensatz angelegt.' })
            } else {
                $rows.Add([pscustomobject]@{ Set=$setName; Key=$key; Action='Create'; Status='PLANNED'; Details='Seed-Datensatz fehlt.' })
            }
            continue
        }

        $differences = [System.Collections.Generic.List[string]]::new()
        foreach ($fieldName in $values.Keys) {
            $actual = $existing[0].FieldValues[$fieldName]
            if ([string]$actual -ne [string]$values[$fieldName]) { $differences.Add($fieldName) }
        }

        if ($differences.Count -eq 0) {
            $rows.Add([pscustomobject]@{ Set=$setName; Key=$key; Action='None'; Status='OK'; Details='Seed-Datensatz entspricht dem Manifest.' })
        }
        elseif ($Mode -eq 'Apply') {
            Set-PnPListItem -List $listName -Identity $existing[0].Id -Values $values -Connection $Connection | Out-Null
            $rows.Add([pscustomobject]@{ Set=$setName; Key=$key; Action='Update'; Status='OK'; Details="Aktualisiert: $($differences -join ', ')" })
        }
        else {
            $rows.Add([pscustomobject]@{ Set=$setName; Key=$key; Action='Update'; Status='DIFFERENCE'; Details="Abweichend: $($differences -join ', ')" })
        }
    }
}

if (@($Manifest.sets).Count -eq 0) {
    $rows.Add([pscustomobject]@{ Set='manifest'; Key=''; Action='None'; Status='OK'; Details='Keine fachlichen Seed-Sets definiert; Infrastruktur ist bereit.' })
}

Write-SeedReport -Rows $rows -Manifest $Manifest
$differences = @($rows | Where-Object Status -eq 'DIFFERENCE').Count
$errors = @($rows | Where-Object Status -eq 'ERROR').Count
Write-Host "SEED $Mode`: $($rows.Count) Prüfungen · $differences Abweichungen · $errors Fehler"
if ($errors -gt 0) { exit 1 }
if ($Mode -eq 'Validate' -and $differences -gt 0) { exit 2 }
exit 0
