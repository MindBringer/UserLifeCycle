param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('DryRun','Apply')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [ValidateSet('Interactive','DeviceLogin')]
    [string]$AuthenticationMode = 'Interactive',

    [string]$ConfirmationToken,

    [string]$OutputDirectory = './generated/reset'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PolicyPath = Join-Path $PSScriptRoot 'reset-policy.json'
$ManifestPath = Join-Path $Root 'schema/manifest.json'
$OutputPath = [System.IO.Path]::GetFullPath((Join-Path $Root $OutputDirectory))

Import-Module PnP.PowerShell -ErrorAction Stop

function Connect-TargetSite {
    if ($AuthenticationMode -eq 'DeviceLogin') {
        return Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -DeviceLogin -ValidateConnection -ReturnConnection
    }
    return Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive -ValidateConnection -ReturnConnection
}

function Get-ExpectedToken([string]$NormalizedSiteUrl, [string]$SchemaVersion) {
    return "RESET|$NormalizedSiteUrl|$SchemaVersion"
}

function Write-ResetReport($Rows, [string]$ExpectedToken) {
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $OutputPath "reset-$($Mode.ToLowerInvariant())-$timestamp.json"
    $csvPath = Join-Path $OutputPath "reset-$($Mode.ToLowerInvariant())-$timestamp.csv"
    $htmlPath = Join-Path $OutputPath "reset-$($Mode.ToLowerInvariant())-$timestamp.html"

    $payload = [ordered]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = $Mode
        siteUrl = $SiteUrl
        expectedConfirmationToken = if ($Mode -eq 'DryRun') { $ExpectedToken } else { $null }
        summary = [ordered]@{
            total = @($Rows).Count
            planned = @($Rows | Where-Object Status -eq 'PLANNED').Count
            deleted = @($Rows | Where-Object Status -eq 'DELETED').Count
            protected = @($Rows | Where-Object Status -eq 'PROTECTED').Count
            errors = @($Rows | Where-Object Status -eq 'ERROR').Count
        }
        results = @($Rows)
    }

    $payload | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
    $Rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    $encodedToken = [System.Net.WebUtility]::HtmlEncode($ExpectedToken)
    $bodyRows = foreach ($row in $Rows) {
        "<tr><td>$([System.Net.WebUtility]::HtmlEncode($row.List))</td><td>$($row.Status)</td><td>$([System.Net.WebUtility]::HtmlEncode($row.Reason))</td></tr>"
    }
    $html = @"
<!doctype html><html lang='de'><head><meta charset='utf-8'><title>UserLifeCycle Reset $Mode</title>
<style>body{font-family:system-ui;margin:24px;color:#172033}table{border-collapse:collapse;width:100%}th,td{border:1px solid #d7deea;padding:7px;text-align:left}th{background:#eef2f7}code{background:#eef2f7;padding:2px 4px}</style></head><body>
<h1>UserLifeCycle Reset – $Mode</h1><p>Site: <code>$([System.Net.WebUtility]::HtmlEncode($SiteUrl))</code></p>
<p>Bestätigungstoken: <code>$encodedToken</code></p>
<table><thead><tr><th>Liste</th><th>Status</th><th>Grund</th></tr></thead><tbody>$($bodyRows -join "`n")</tbody></table></body></html>
"@
    Set-Content -Path $htmlPath -Value $html -Encoding UTF8
    Write-Host "RESET REPORT JSON: $jsonPath"
    Write-Host "RESET REPORT CSV:  $csvPath"
    Write-Host "RESET REPORT HTML: $htmlPath"
}

if (-not (Test-Path $PolicyPath)) { throw "Reset-Policy fehlt: $PolicyPath" }
if (-not (Test-Path $ManifestPath)) { throw "Schema-Manifest fehlt: $ManifestPath" }

$Policy = Get-Content $PolicyPath -Raw | ConvertFrom-Json -Depth 20
$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json -Depth 20
$normalizedSiteUrl = $SiteUrl.TrimEnd('/').ToLowerInvariant()
$siteUri = [uri]$normalizedSiteUrl

if ($siteUri.AbsolutePath.ToLowerInvariant() -ne ([string]$Policy.allowedSitePath).ToLowerInvariant()) {
    throw "Reset ist für diese Site nicht freigegeben: $normalizedSiteUrl"
}

$expectedToken = Get-ExpectedToken -NormalizedSiteUrl $normalizedSiteUrl -SchemaVersion ([string]$Manifest.schemaVersion)
if ($Mode -eq 'Apply' -and $ConfirmationToken -ne $expectedToken) {
    throw "Ungültiges Confirmation Token. Führe zuerst Reset DryRun aus."
}

$Connection = Connect-TargetSite
$token = Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $Connection
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/json;odata=nometadata' }
$listsResponse = Invoke-RestMethod -Uri "$normalizedSiteUrl/_api/web/lists?`$select=Title,Hidden&`$filter=Hidden eq false" -Headers $headers -Method Get -TimeoutSec 30
$rows = [System.Collections.Generic.List[object]]::new()
$targets = [System.Collections.Generic.List[string]]::new()

foreach ($list in @($listsResponse.value)) {
    $title = [string]$list.Title
    $isProtected = @($Policy.protectedExplicit) -contains $title
    if (-not $isProtected) {
        foreach ($prefix in @($Policy.protectedPrefixes)) {
            if ($title.StartsWith([string]$prefix) -and -not (@($Policy.deleteExplicit) -contains $title)) { $isProtected = $true; break }
        }
    }

    $shouldDelete = @($Policy.deleteExplicit) -contains $title
    if (-not $shouldDelete) {
        foreach ($prefix in @($Policy.deletePrefixes)) {
            if ($title.StartsWith([string]$prefix)) { $shouldDelete = $true; break }
        }
    }

    if ($isProtected -and -not (@($Policy.deleteExplicit) -contains $title)) {
        $rows.Add([pscustomobject]@{ List=$title; Status='PROTECTED'; Reason='Durch Reset-Policy geschützt' })
        continue
    }
    if ($shouldDelete) { $targets.Add($title) }
}

foreach ($title in @($targets | Sort-Object)) {
    if ($Mode -eq 'DryRun') {
        $rows.Add([pscustomobject]@{ List=$title; Status='PLANNED'; Reason='Altbestand laut Reset-Policy' })
        continue
    }
    try {
        Remove-PnPList -Identity $title -Force -Connection $Connection
        $rows.Add([pscustomobject]@{ List=$title; Status='DELETED'; Reason='Altbestand entfernt' })
    }
    catch {
        $rows.Add([pscustomobject]@{ List=$title; Status='ERROR'; Reason=$_.Exception.Message })
    }
}

Write-ResetReport -Rows $rows -ExpectedToken $expectedToken
$errors = @($rows | Where-Object Status -eq 'ERROR').Count
Write-Host "RESET $Mode`: $($targets.Count) Zielobjekte · $errors Fehler"
if ($Mode -eq 'DryRun') { Write-Host "CONFIRMATION TOKEN: $expectedToken" }
if ($errors -gt 0) { exit 1 }
exit 0
