<#
.SYNOPSIS
  IT Governance Portal 2.0 - Greenfield Provisioning Script

.DESCRIPTION
  Echtes PowerShell/PnP.PowerShell Provisioning-Skript fuer SharePoint Online.
  Erstellt zentrale Site Columns, Content Types, Listen, Bibliotheken, Views und Navigation.

  Voraussetzungen:
  - PowerShell >= 7.4
  - PnP.PowerShell
  - Entra App ClientId fuer Connect-PnPOnline -Interactive
  - ausreichende SharePoint-Rechte, idealerweise Site Collection Admin

.NOTES
  Generated: 2026-06-23
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = "05f890bd-e131-4d1f-ba60-1ffc0298d137",

    [switch]$Interactive,
    [switch]$DryRun,
    [switch]$ProvisionSampleCatalogData,
    [switch]$SkipWritePermissionTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$MinimumPSVersion = [version]"7.4"
$FieldGroup = "Governance Portal 2.0"
$ContentTypeGroup = "Governance Portal 2.0"
$LogFile = Join-Path (Get-Location) ("GovernancePortal20-Provisioning-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Write-GPLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DRYRUN", "FIX")][string]$Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Stop-GPWithFix {
    param(
        [Parameter(Mandatory = $true)][string]$Problem,
        [Parameter(Mandatory = $true)][string]$Fix
    )
    Write-GPLog $Problem "ERROR"
    Write-GPLog "Loesung: $Fix" "FIX"
    throw $Problem
}

function Invoke-GPAction {
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    if ($DryRun) {
        Write-GPLog $Description "DRYRUN"
        return
    }
    Write-GPLog $Description "INFO"
    & $Action
}

function Test-GPPreflight {
    Write-GPLog "Starte Preflight-Pruefungen" "INFO"

    if ($PSVersionTable.PSVersion -lt $MinimumPSVersion -or $PSVersionTable.PSEdition -ne "Core") {
        Stop-GPWithFix `
            -Problem "PowerShell $($PSVersionTable.PSVersion) / $($PSVersionTable.PSEdition) erkannt. Benoetigt wird PowerShell >= 7.4 Core." `
            -Fix "Installiere PowerShell 7.x: winget install Microsoft.PowerShell --source winget ; danach neue Sitzung mit pwsh starten."
    }
    Write-GPLog "PowerShell OK: $($PSVersionTable.PSVersion) / $($PSVersionTable.PSEdition)" "SUCCESS"

    $effectivePolicy = Get-ExecutionPolicy
    $processPolicy = Get-ExecutionPolicy -Scope Process
    Write-GPLog "ExecutionPolicy: Effective=$effectivePolicy; Process=$processPolicy" "INFO"
    if ($effectivePolicy -in @("Restricted", "AllSigned") -and $processPolicy -ne "Bypass") {
        Write-GPLog "ExecutionPolicy kann die Ausfuehrung blockieren." "WARN"
        Write-GPLog "Loesung: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass" "FIX"
    }

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ($scriptPath -and (Test-Path $scriptPath)) {
        try {
            $zone = Get-Item -Path $scriptPath -Stream Zone.Identifier -ErrorAction SilentlyContinue
            if ($null -ne $zone) {
                Write-GPLog "Skript ist als Datei unbekannter Herkunft markiert: $scriptPath" "WARN"
                Write-GPLog "Loesung: Unblock-File -Path '$scriptPath'" "FIX"
            }
        } catch { }
    }

    if ($SiteUrl -match "``") {
        Stop-GPWithFix `
            -Problem "SiteUrl enthaelt ein Backtick. Vermutlich fehlt das schliessende Anfuehrungszeichen im Aufruf." `
            -Fix "Nutze exakt: -SiteUrl \"https://groupsteinicke.sharepoint.com/sites/GovernancePortal\" ``"
    }

    if ($SiteUrl -notmatch "^https://") {
        Stop-GPWithFix `
            -Problem "SiteUrl wirkt ungueltig: $SiteUrl" `
            -Fix "Nutze z.B.: -SiteUrl \"https://groupsteinicke.sharepoint.com/sites/GovernancePortal\""
    }

    $pnp = Get-Module -ListAvailable -Name PnP.PowerShell | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $pnp) {
        Stop-GPWithFix `
            -Problem "PnP.PowerShell Modul wurde nicht gefunden." `
            -Fix "In PowerShell 7.x ausfuehren: Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber ; danach pwsh neu starten."
    }

    try {
        Import-Module PnP.PowerShell -Force -ErrorAction Stop
        Write-GPLog "PnP.PowerShell OK: Version $($pnp.Version)" "SUCCESS"
    } catch {
        Stop-GPWithFix `
            -Problem "PnP.PowerShell konnte nicht importiert werden: $($_.Exception.Message)" `
            -Fix "Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber ; danach pwsh neu starten."
    }
}

function Connect-GPSite {
    Write-GPLog "Verbinde mit SharePoint: $SiteUrl" "INFO"
    try {
        if ($Interactive) {
            if ([string]::IsNullOrWhiteSpace($ClientId)) {
                Connect-PnPOnline -Url $SiteUrl -Interactive -ErrorAction Stop
            } else {
                Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $ClientId -ErrorAction Stop
            }
        } else {
            Connect-PnPOnline -Url $SiteUrl -ErrorAction Stop
        }
        $web = Get-PnPWeb -ErrorAction Stop
        Write-GPLog "Verbindung OK: $($web.Title)" "SUCCESS"
    } catch {
        Stop-GPWithFix `
            -Problem "Connect-PnPOnline fehlgeschlagen: $($_.Exception.Message)" `
            -Fix "Pruefe ClientId, Admin Consent, MFA/Conditional Access und Site-Berechtigungen. Test: Connect-PnPOnline -Url '$SiteUrl' -Interactive -ClientId '$ClientId'"
    }
}

function Test-GPWritePermission {
    if ($DryRun) {
        Write-GPLog "DryRun aktiv: Schreibrechte-Test wird nicht ausgefuehrt." "DRYRUN"
        return
    }
    if ($SkipWritePermissionTest) {
        Write-GPLog "Schreibrechte-Test uebersprungen." "WARN"
        return
    }

    $testField = "GP20PermissionTest"
    try {
        Write-GPLog "Teste Schreibrechte fuer Site Columns" "INFO"
        if (-not (Get-PnPField -Identity $testField -ErrorAction SilentlyContinue)) {
            Add-PnPField -DisplayName "GP20 Permission Test" -InternalName $testField -Type Text -Group $FieldGroup -ErrorAction Stop | Out-Null
        }
        Remove-PnPField -Identity $testField -Force -ErrorAction SilentlyContinue | Out-Null
        Write-GPLog "Schreibrechte-Test erfolgreich" "SUCCESS"
    } catch {
        Stop-GPWithFix `
            -Problem "Keine ausreichenden Rechte fuer Site Columns/List Provisioning: $($_.Exception.Message)" `
            -Fix "User als Site Collection Administrator setzen UND Entra App delegated SharePoint Permission z.B. AllSites.FullControl mit Admin Consent geben. Danach neu anmelden."
    }
}

function Get-GPFieldType {
    param([string]$Type)
    switch ($Type) {
        "Text"        { return "Text" }
        "Note"        { return "Note" }
        "Choice"      { return "Choice" }
        "MultiChoice" { return "MultiChoice" }
        "Number"      { return "Number" }
        "DateTime"    { return "DateTime" }
        "Boolean"     { return "Boolean" }
        "User"        { return "User" }
        "URL"         { return "URL" }
        default        { throw "Unsupported field type: $Type" }
    }
}

function Add-GPFieldSafe {
    param(
        [Parameter(Mandatory = $false)][string]$List,
        [Parameter(Mandatory = $true)][string]$InternalName,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$Type,
        [string[]]$Choices = @(),
        [bool]$Multi = $false
    )

    $fieldType = Get-GPFieldType -Type $Type

    $params = @{
        DisplayName  = $DisplayName
        InternalName = $InternalName
        Type         = $fieldType
        ErrorAction  = "Stop"
    }

    if ([string]::IsNullOrWhiteSpace($List)) {
        $params["Group"] = $FieldGroup
    } else {
        $params["List"] = $List
    }

    if ($Type -in @("Choice", "MultiChoice") -and $Choices.Count -gt 0) {
        $params["Choices"] = $Choices
    }

    Add-PnPField @params | Out-Null

    $field = if ([string]::IsNullOrWhiteSpace($List)) {
        Get-PnPField -Identity $InternalName -ErrorAction Stop
    } else {
        Get-PnPField -List $List -Identity $InternalName -ErrorAction Stop
    }

    $needsUpdate = $false

    if ($Type -eq "DateTime") {
        try { $field.DisplayFormat = 0; $needsUpdate = $true } catch { }
    }

    if ($Type -eq "Note") {
        try { $field.NumberOfLines = 6; $needsUpdate = $true } catch { }
        try { $field.RichText = $false; $needsUpdate = $true } catch { }
    }

    if ($Type -eq "User") {
        try { $field.SelectionMode = 0; $needsUpdate = $true } catch { }
        if ($Multi) {
            try { $field.AllowMultipleValues = $true; $needsUpdate = $true } catch { }
        }
    }

    if ($Type -eq "Boolean") {
        try { $field.DefaultValue = "1"; $needsUpdate = $true } catch { }
    }

    if ($needsUpdate) {
        $field.Update()
        Invoke-PnPQuery
    }
}

function Ensure-GPSiteField {
    param([string]$InternalName, [string]$DisplayName, [string]$Type, [string[]]$Choices = @(), [bool]$Multi = $false)
    if ($DryRun) { Write-GPLog "Site Column sicherstellen: $DisplayName [$InternalName]" "DRYRUN"; return }
    if (Get-PnPField -Identity $InternalName -ErrorAction SilentlyContinue) { Write-GPLog "Site Column vorhanden: $InternalName"; return }
    Add-GPFieldSafe -InternalName $InternalName -DisplayName $DisplayName -Type $Type -Choices $Choices -Multi $Multi
    Write-GPLog "Site Column erstellt: $InternalName" "SUCCESS"
}

function Ensure-GPListField {
    param([string]$List, [string]$InternalName, [string]$DisplayName, [string]$Type, [string[]]$Choices = @(), [bool]$Multi = $false)
    if ($DryRun) { Write-GPLog "Listenfeld sicherstellen: $List.$DisplayName [$InternalName]" "DRYRUN"; return }
    if (Get-PnPField -List $List -Identity $InternalName -ErrorAction SilentlyContinue) { Write-GPLog "Listenfeld vorhanden: $List.$InternalName"; return }
    Add-GPFieldSafe -List $List -InternalName $InternalName -DisplayName $DisplayName -Type $Type -Choices $Choices -Multi $Multi
    Write-GPLog "Listenfeld erstellt: $List.$InternalName" "SUCCESS"
}

function Ensure-GPLookupField {
    param(
        [string]$List,
        [string]$InternalName,
        [string]$DisplayName,
        [string]$LookupList,
        [bool]$Multi = $false
    )

    if ($DryRun) {
        Write-GPLog "Lookup sicherstellen: $List.$DisplayName -> $LookupList" "DRYRUN"
        return
    }

    if (Get-PnPField -List $List -Identity $InternalName -ErrorAction SilentlyContinue) {
        Write-GPLog "Lookup vorhanden: $List.$InternalName"
        return
    }

    $targetList = Get-PnPList -Identity $LookupList -ErrorAction Stop
    if ($null -eq $targetList) {
        throw "Lookup-Zielliste nicht gefunden: $LookupList"
    }

    $lookupListId = $targetList.Id.ToString("B")
    $fieldType = if ($Multi) { "LookupMulti" } else { "Lookup" }
    $multAttr = if ($Multi) { "TRUE" } else { "FALSE" }

    $fieldXml = "<Field Type='$fieldType' Name='$InternalName' StaticName='$InternalName' DisplayName='$DisplayName' List='$lookupListId' ShowField='Title' Mult='$multAttr' Group='$FieldGroup' />"

    Add-PnPFieldFromXml -List $List -FieldXml $fieldXml -ErrorAction Stop | Out-Null

    Write-GPLog "Lookup erstellt: $List.$InternalName -> $LookupList" "SUCCESS"
}
function Resolve-GPContentType {
    param([Parameter(Mandatory=$true)][string]$Identity)

    # Built-in Item Content Type: use ContentTypeId 0x01 to avoid localization issues, e.g. German "Element".
    if ($Identity -eq "Item" -or $Identity -eq "Element" -or $Identity -eq "0x01") {
        $itemCt = Get-PnPContentType -ErrorAction Stop | Where-Object {
            $_.StringId -eq "0x01" -or $_.Id.StringValue -eq "0x01"
        } | Select-Object -First 1

        if ($null -ne $itemCt) { return $itemCt }
    }

    # First try PnP identity lookup.
    $ct = Get-PnPContentType -Identity $Identity -ErrorAction SilentlyContinue
    if ($null -ne $ct) { return $ct }

    # Fallback: search by Name.
    $ct = Get-PnPContentType -ErrorAction Stop | Where-Object { $_.Name -eq $Identity } | Select-Object -First 1
    if ($null -ne $ct) { return $ct }

    return $null
}

function Ensure-GPContentType {
    param([string]$Name, [string]$Parent = "Item")
    if ($DryRun) { Write-GPLog "Content Type sicherstellen: $Name" "DRYRUN"; return }

    $existing = Resolve-GPContentType -Identity $Name
    if ($null -ne $existing) {
        Write-GPLog "Content Type vorhanden: $Name"
        return
    }

    $parentContentType = Resolve-GPContentType -Identity $Parent
    if ($null -eq $parentContentType) {
        throw "Parent Content Type nicht gefunden: $Parent. Tipp: Auf lokalisierten Sites heisst 'Item' ggf. 'Element'; v4 sucht deshalb auch nach ContentTypeId 0x01. Wenn das weiterhin fehlschlaegt, pruefe: Get-PnPContentType | Select Name,StringId"
    }

    Add-PnPContentType `
        -Name $Name `
        -Group $ContentTypeGroup `
        -ParentContentType $parentContentType `
        -ErrorAction Stop | Out-Null

    Write-GPLog "Content Type erstellt: $Name" "SUCCESS"
}
function Ensure-GPFieldInContentType {
    param([string]$ContentType, [string]$Field)
    if ($DryRun) { Write-GPLog "Feld $Field zu Content Type $ContentType hinzufuegen" "DRYRUN"; return }
    Add-PnPFieldToContentType -Field $Field -ContentType $ContentType -ErrorAction SilentlyContinue | Out-Null
}

function Ensure-GPList {
    param([string]$Title, [ValidateSet("GenericList", "DocumentLibrary")][string]$Template = "GenericList", [string]$ContentType = "")
    if ($DryRun) { Write-GPLog "$Template sicherstellen: $Title; ContentType=$ContentType" "DRYRUN"; return }
    if (-not (Get-PnPList -Identity $Title -ErrorAction SilentlyContinue)) {
        New-PnPList -Title $Title -Template $Template -EnableVersioning:$true -OnQuickLaunch:$true -ErrorAction Stop | Out-Null
        Write-GPLog "$Template erstellt: $Title" "SUCCESS"
    } else {
        Write-GPLog "Liste/Bibliothek vorhanden: $Title"
    }
    Set-PnPList -Identity $Title -EnableVersioning $true | Out-Null
    if ($ContentType) {
        Set-PnPList -Identity $Title -EnableContentTypes $true | Out-Null
        Add-PnPContentTypeToList -List $Title -ContentType $ContentType -DefaultContentType -ErrorAction SilentlyContinue | Out-Null
    }
}

function Ensure-GPView {
    param([string]$List, [string]$Name, [string[]]$Fields, [string]$Query = "")
    if ($DryRun) { Write-GPLog "View sicherstellen: $List/$Name" "DRYRUN"; return }
    if (Get-PnPView -List $List -Identity $Name -ErrorAction SilentlyContinue) { return }
    Add-PnPView -List $List -Title $Name -Fields $Fields -Query $Query -SetAsDefault:$false -ErrorAction Stop | Out-Null
}

function Ensure-GPNavigationNode {
    param([string]$Title, [string]$Url)
    if ($DryRun) { Write-GPLog "Navigation sicherstellen: $Title -> $Url" "DRYRUN"; return }
    Add-PnPNavigationNode -Title $Title -Url $Url -Location QuickLaunch -External -ErrorAction SilentlyContinue | Out-Null
}
# --------------------------------------------------------------------------------------
# Definitions
# --------------------------------------------------------------------------------------
$coreStatus = @("Draft", "Open", "In Progress", "Waiting", "Resolved", "Closed", "Cancelled")
$riskStatus = @("Draft", "Open", "Accepted", "Mitigated", "Transferred", "Closed")
$controlStatus = @("Draft", "Implemented", "Partially Implemented", "Not Implemented", "Ineffective", "Retired")
$criticality = @("Low", "Medium", "High", "Critical")
$scope = @("NIS2", "ISO27001", "BSI-Grundschutz", "DSGVO", "Internal")
$dataClass = @("Public", "Internal", "Confidential", "Strictly Confidential")
$lifecycle = @("Planned", "Active", "In Review", "Retired", "Archived")
$priority = @("Low", "Medium", "High", "Critical")

$siteFields = @(
    @{InternalName="GovernanceID"; DisplayName="Governance-ID"; Type="Text"},
    @{InternalName="GovernanceStatus"; DisplayName="Status"; Type="Choice"; Choices=$coreStatus},
    @{InternalName="Description"; DisplayName="Beschreibung"; Type="Note"},
    @{InternalName="Owner"; DisplayName="Verantwortlicher"; Type="User"},
    @{InternalName="DeputyOwner"; DisplayName="Stellvertretung"; Type="User"},
    @{InternalName="Criticality"; DisplayName="Kritikalitaet"; Type="Choice"; Choices=$criticality},
    @{InternalName="ComplianceScope"; DisplayName="Compliance Scope"; Type="MultiChoice"; Choices=$scope},
    @{InternalName="LastReviewDate"; DisplayName="Letzter Review"; Type="DateTime"},
    @{InternalName="NextReviewDate"; DisplayName="Naechster Review"; Type="DateTime"},
    @{InternalName="ReviewCycleMonths"; DisplayName="Review-Zyklus Monate"; Type="Number"},
    @{InternalName="IsActive"; DisplayName="Aktiv"; Type="Boolean"},
    @{InternalName="DataClassification"; DisplayName="Datenklassifizierung"; Type="Choice"; Choices=$dataClass},
    @{InternalName="LifecycleStatus"; DisplayName="Lebenszyklusstatus"; Type="Choice"; Choices=$lifecycle}
)

$coreFields = @("GovernanceID", "GovernanceStatus", "Description", "Owner", "DeputyOwner", "Criticality", "ComplianceScope", "LastReviewDate", "NextReviewDate", "ReviewCycleMonths", "IsActive")
$contentTypes = @("Governance Asset", "Governance System", "Governance Risk", "Governance Control", "Governance Measure", "Governance Change", "Governance Incident", "Governance Problem", "Governance Evidence", "Governance Review", "Governance Contact", "Governance Knowledge", "Governance Catalog Item", "Governance Setting")
$lists = @(
    @{Title="Assets"; CT="Governance Asset"},
    @{Title="Systems"; CT="Governance System"},
    @{Title="Risks"; CT="Governance Risk"},
    @{Title="Controls"; CT="Governance Control"},
    @{Title="Measures"; CT="Governance Measure"},
    @{Title="Changes"; CT="Governance Change"},
    @{Title="Incidents"; CT="Governance Incident"},
    @{Title="Problems"; CT="Governance Problem"},
    @{Title="EvidenceRegister"; CT="Governance Evidence"},
    @{Title="Reviews"; CT="Governance Review"},
    @{Title="Contacts"; CT="Governance Contact"},
    @{Title="Knowledge"; CT="Governance Knowledge"},
    @{Title="AssetTypes"; CT="Governance Catalog Item"},
    @{Title="RiskCatalog"; CT="Governance Catalog Item"},
    @{Title="ControlCatalog"; CT="Governance Catalog Item"},
    @{Title="MeasureTemplates"; CT="Governance Catalog Item"},
    @{Title="ReviewTemplates"; CT="Governance Catalog Item"},
    @{Title="RoleCatalog"; CT="Governance Catalog Item"},
    @{Title="StatusCatalog"; CT="Governance Catalog Item"},
    @{Title="ComplianceMappings"; CT="Governance Catalog Item"},
    @{Title="GovernanceSettings"; CT="Governance Setting"}
)
$libraries = @("Evidence", "Policies", "Runbooks", "Procedures", "Architecture", "Network", "Audit")

try {
    Write-GPLog "Starting Governance Portal 2.0 provisioning for $SiteUrl"
    Test-GPPreflight
    Connect-GPSite
    Test-GPWritePermission

    foreach ($field in $siteFields) { Ensure-GPSiteField @field }

    Ensure-GPContentType -Name "Governance Item"
    foreach ($fieldName in $coreFields) { Ensure-GPFieldInContentType -ContentType "Governance Item" -Field $fieldName }
    foreach ($ct in $contentTypes) { Ensure-GPContentType -Name $ct -Parent "Governance Item" }
    foreach ($ct in @("Governance Asset", "Governance System")) {
        Ensure-GPFieldInContentType -ContentType $ct -Field "DataClassification"
        Ensure-GPFieldInContentType -ContentType $ct -Field "LifecycleStatus"
    }

    foreach ($list in $lists) { Ensure-GPList -Title $list.Title -Template GenericList -ContentType $list.CT }
    foreach ($lib in $libraries) { Ensure-GPList -Title $lib -Template DocumentLibrary }

    # Assets
    Ensure-GPListField -List "Assets" -InternalName "AssetType" -DisplayName "Asset-Typ" -Type Text
    Ensure-GPListField -List "Assets" -InternalName "BusinessOwner" -DisplayName "Fachlicher Verantwortlicher" -Type User
    Ensure-GPListField -List "Assets" -InternalName "TechnicalOwner" -DisplayName "Technischer Verantwortlicher" -Type User
    Ensure-GPListField -List "Assets" -InternalName "Confidentiality" -DisplayName "Vertraulichkeit" -Type Choice -Choices $criticality
    Ensure-GPListField -List "Assets" -InternalName "Integrity" -DisplayName "Integritaet" -Type Choice -Choices $criticality
    Ensure-GPListField -List "Assets" -InternalName "Availability" -DisplayName "Verfuegbarkeit" -Type Choice -Choices $criticality

    # Systems
    Ensure-GPLookupField -List "Systems" -InternalName "LinkedAsset" -DisplayName "Verknuepftes Asset" -LookupList "Assets"
    Ensure-GPListField -List "Systems" -InternalName "SystemType" -DisplayName "Systemtyp" -Type Choice -Choices @("Application", "Server", "Cloud Service", "Network", "Database", "Endpoint", "OT System", "Other")
    Ensure-GPListField -List "Systems" -InternalName "Environment" -DisplayName "Umgebung" -Type Choice -Choices @("Production", "Test", "Development", "Management", "OT", "Other")
    Ensure-GPListField -List "Systems" -InternalName "Manufacturer" -DisplayName "Hersteller" -Type Text
    Ensure-GPListField -List "Systems" -InternalName "SystemVersion" -DisplayName "Version" -Type Text
    Ensure-GPListField -List "Systems" -InternalName "HostingType" -DisplayName "Hosting-Typ" -Type Choice -Choices @("On-Premises", "Cloud", "Hybrid", "SaaS", "IaaS", "PaaS", "Other")
    Ensure-GPListField -List "Systems" -InternalName "NetworkZone" -DisplayName "Netzwerkzone" -Type Text

    # Risks
    Ensure-GPLookupField -List "Risks" -InternalName "LinkedAssets" -DisplayName "Verknuepfte Assets" -LookupList "Assets" -Multi $true
    Ensure-GPLookupField -List "Risks" -InternalName "LinkedSystems" -DisplayName "Verknuepfte Systeme" -LookupList "Systems" -Multi $true
    Ensure-GPListField -List "Risks" -InternalName "RiskStatus" -DisplayName "Risiko-Status" -Type Choice -Choices $riskStatus
    Ensure-GPListField -List "Risks" -InternalName "RiskCategory" -DisplayName "Risikokategorie" -Type Choice -Choices @("Security", "Availability", "Compliance", "Data Protection", "Operational", "Provider", "Financial", "Other")
    Ensure-GPListField -List "Risks" -InternalName "Threat" -DisplayName "Bedrohung" -Type Note
    Ensure-GPListField -List "Risks" -InternalName "Vulnerability" -DisplayName "Schwachstelle" -Type Note
    Ensure-GPListField -List "Risks" -InternalName "ImpactDescription" -DisplayName "Auswirkungsbeschreibung" -Type Note
    Ensure-GPListField -List "Risks" -InternalName "Likelihood" -DisplayName "Eintrittswahrscheinlichkeit" -Type Choice -Choices @("1 Very Low", "2 Low", "3 Medium", "4 High", "5 Very High")
    Ensure-GPListField -List "Risks" -InternalName "Impact" -DisplayName "Auswirkung" -Type Choice -Choices @("1 Very Low", "2 Low", "3 Medium", "4 High", "5 Very High")
    Ensure-GPListField -List "Risks" -InternalName "RiskScore" -DisplayName "Risiko-Score" -Type Number
    Ensure-GPListField -List "Risks" -InternalName "RiskTreatment" -DisplayName "Risikobehandlung" -Type Choice -Choices @("Avoid", "Mitigate", "Transfer", "Accept")

    # Controls
    Ensure-GPLookupField -List "Controls" -InternalName "LinkedAssets" -DisplayName "Verknuepfte Assets" -LookupList "Assets" -Multi $true
    Ensure-GPLookupField -List "Controls" -InternalName "LinkedSystems" -DisplayName "Verknuepfte Systeme" -LookupList "Systems" -Multi $true
    Ensure-GPLookupField -List "Controls" -InternalName "LinkedRisks" -DisplayName "Verknuepfte Risiken" -LookupList "Risks" -Multi $true
    Ensure-GPListField -List "Controls" -InternalName "ControlStatus" -DisplayName "Control-Status" -Type Choice -Choices $controlStatus
    Ensure-GPListField -List "Controls" -InternalName "ControlType" -DisplayName "Control-Typ" -Type Choice -Choices @("Preventive", "Detective", "Corrective", "Directive", "Compensating")
    Ensure-GPListField -List "Controls" -InternalName "ControlObjective" -DisplayName "Control-Ziel" -Type Note
    Ensure-GPListField -List "Controls" -InternalName "ImplementationStatus" -DisplayName "Implementierungsstatus" -Type Choice -Choices $controlStatus
    Ensure-GPListField -List "Controls" -InternalName "Effectiveness" -DisplayName "Wirksamkeit" -Type Choice -Choices @("Not assessed", "Effective", "Partially effective", "Ineffective")
    Ensure-GPListField -List "Controls" -InternalName "EvidenceRequired" -DisplayName "Nachweis erforderlich" -Type Boolean

    # Measures
    Ensure-GPLookupField -List "Measures" -InternalName "LinkedRisks" -DisplayName "Verknuepfte Risiken" -LookupList "Risks" -Multi $true
    Ensure-GPLookupField -List "Measures" -InternalName "LinkedControls" -DisplayName "Verknuepfte Controls" -LookupList "Controls" -Multi $true
    Ensure-GPLookupField -List "Measures" -InternalName "LinkedAssets" -DisplayName "Verknuepfte Assets" -LookupList "Assets" -Multi $true
    Ensure-GPListField -List "Measures" -InternalName "Priority" -DisplayName "Prioritaet" -Type Choice -Choices $priority
    Ensure-GPListField -List "Measures" -InternalName "DueDate" -DisplayName "Faellig am" -Type DateTime
    Ensure-GPListField -List "Measures" -InternalName "CompletionDate" -DisplayName "Abschlussdatum" -Type DateTime
    Ensure-GPListField -List "Measures" -InternalName "EffectivenessCheckRequired" -DisplayName "Wirksamkeitspruefung erforderlich" -Type Boolean

    # Changes / Incidents common
    foreach ($listName in @("Changes", "Incidents")) {
        Ensure-GPLookupField -List $listName -InternalName "LinkedAssets" -DisplayName "Verknuepfte Assets" -LookupList "Assets" -Multi $true
        Ensure-GPLookupField -List $listName -InternalName "LinkedSystems" -DisplayName "Verknuepfte Systeme" -LookupList "Systems" -Multi $true
        Ensure-GPListField -List $listName -InternalName "EvidenceRequired" -DisplayName "Nachweis erforderlich" -Type Boolean
    }

    # Changes
    Ensure-GPListField -List "Changes" -InternalName "ChangeType" -DisplayName "Change-Typ" -Type Choice -Choices @("Standard", "Normal", "Emergency", "Security", "Infrastructure", "Application", "Other")
    Ensure-GPListField -List "Changes" -InternalName "RiskAssessment" -DisplayName "Risikobewertung" -Type Note
    Ensure-GPListField -List "Changes" -InternalName "RollbackPlan" -DisplayName "Rollback-Plan" -Type Note
    Ensure-GPListField -List "Changes" -InternalName "ApprovalStatus" -DisplayName "Freigabestatus" -Type Choice -Choices @("Not required", "Requested", "Approved", "Rejected", "Cancelled")
    Ensure-GPListField -List "Changes" -InternalName "ImplementationDate" -DisplayName "Umsetzungsdatum" -Type DateTime

    # Incidents
    Ensure-GPListField -List "Incidents" -InternalName "IncidentCategory" -DisplayName "Incident-Kategorie" -Type Choice -Choices @("Security", "Availability", "Performance", "Data Protection", "Operations", "Provider", "Other")
    Ensure-GPListField -List "Incidents" -InternalName "Severity" -DisplayName "Schweregrad" -Type Choice -Choices @("Low", "Medium", "High", "Critical")
    Ensure-GPListField -List "Incidents" -InternalName "DetectionDate" -DisplayName "Erkannt am" -Type DateTime
    Ensure-GPListField -List "Incidents" -InternalName "ResolutionDate" -DisplayName "Geloest am" -Type DateTime
    Ensure-GPListField -List "Incidents" -InternalName "RootCause" -DisplayName "Ursache" -Type Note
    Ensure-GPLookupField -List "Incidents" -InternalName "LinkedProblem" -DisplayName "Verknuepftes Problem" -LookupList "Problems"

    # Problems
    Ensure-GPLookupField -List "Problems" -InternalName "LinkedIncidents" -DisplayName "Verknuepfte Incidents" -LookupList "Incidents" -Multi $true
    Ensure-GPLookupField -List "Problems" -InternalName "LinkedAssets" -DisplayName "Verknuepfte Assets" -LookupList "Assets" -Multi $true
    Ensure-GPListField -List "Problems" -InternalName "RootCause" -DisplayName "Root Cause" -Type Note
    Ensure-GPListField -List "Problems" -InternalName "KnownError" -DisplayName "Known Error" -Type Note
    Ensure-GPListField -List "Problems" -InternalName "Workaround" -DisplayName "Workaround" -Type Note
    Ensure-GPListField -List "Problems" -InternalName "PermanentSolution" -DisplayName "Dauerhafte Loesung" -Type Note
    Ensure-GPLookupField -List "Problems" -InternalName "LinkedMeasures" -DisplayName "Verknuepfte Massnahmen" -LookupList "Measures" -Multi $true

    # EvidenceRegister
    Ensure-GPListField -List "EvidenceRegister" -InternalName "EvidenceType" -DisplayName "Nachweistyp" -Type Choice -Choices @("Screenshot", "Export", "Report", "Protocol", "Policy", "Configuration", "Audit Evidence", "Other")
    foreach ($pair in @(@("LinkedAsset", "Asset", "Assets"), @("LinkedSystem", "System", "Systems"), @("LinkedRisk", "Risiko", "Risks"), @("LinkedControl", "Control", "Controls"), @("LinkedMeasure", "Massnahme", "Measures"), @("LinkedChange", "Change", "Changes"))) {
        Ensure-GPLookupField -List "EvidenceRegister" -InternalName $pair[0] -DisplayName "Verknuepftes $($pair[1])" -LookupList $pair[2]
    }
    Ensure-GPListField -List "EvidenceRegister" -InternalName "EvidenceDocument" -DisplayName "Nachweisdokument" -Type URL
    Ensure-GPListField -List "EvidenceRegister" -InternalName "ValidFrom" -DisplayName "Gueltig ab" -Type DateTime
    Ensure-GPListField -List "EvidenceRegister" -InternalName "ValidUntil" -DisplayName "Gueltig bis" -Type DateTime
    Ensure-GPListField -List "EvidenceRegister" -InternalName "EvidenceStatus" -DisplayName "Nachweisstatus" -Type Choice -Choices @("Missing", "Submitted", "Valid", "Expired", "Rejected")

    # Reviews
    Ensure-GPListField -List "Reviews" -InternalName "ReviewedObjectType" -DisplayName "Review-Objekttyp" -Type Choice -Choices @("Asset", "System", "Risk", "Control", "Measure", "Change", "Incident", "Problem", "Evidence", "Policy", "Runbook")
    foreach ($pair in @(@("LinkedAsset", "Asset", "Assets"), @("LinkedRisk", "Risiko", "Risks"), @("LinkedControl", "Control", "Controls"), @("LinkedMeasure", "Massnahme", "Measures"))) {
        Ensure-GPLookupField -List "Reviews" -InternalName $pair[0] -DisplayName "Verknuepftes $($pair[1])" -LookupList $pair[2]
    }
    Ensure-GPListField -List "Reviews" -InternalName "ReviewDate" -DisplayName "Review-Datum" -Type DateTime
    Ensure-GPListField -List "Reviews" -InternalName "Reviewer" -DisplayName "Reviewer" -Type User
    Ensure-GPListField -List "Reviews" -InternalName "ReviewResult" -DisplayName "Review-Ergebnis" -Type Choice -Choices @("No findings", "Findings", "Follow-up required", "Not applicable")
    Ensure-GPListField -List "Reviews" -InternalName "Findings" -DisplayName "Feststellungen" -Type Note
    Ensure-GPListField -List "Reviews" -InternalName "FollowUpRequired" -DisplayName "Follow-up erforderlich" -Type Boolean
    Ensure-GPLookupField -List "Reviews" -InternalName "LinkedFollowUpMeasure" -DisplayName "Follow-up Massnahme" -LookupList "Measures"

    # Contacts / Knowledge
    Ensure-GPListField -List "Contacts" -InternalName "ContactRole" -DisplayName "Kontaktrolle" -Type Text
    Ensure-GPListField -List "Contacts" -InternalName "Organization" -DisplayName "Organisation" -Type Text
    Ensure-GPListField -List "Contacts" -InternalName "Email" -DisplayName "E-Mail" -Type Text
    Ensure-GPListField -List "Contacts" -InternalName "Phone" -DisplayName "Telefon" -Type Text
    Ensure-GPListField -List "Knowledge" -InternalName "KnowledgeCategory" -DisplayName "Kategorie" -Type Choice -Choices @("HowTo", "Troubleshooting", "Decision", "FAQ", "Known Error", "Other")
    Ensure-GPListField -List "Knowledge" -InternalName "ArticleBody" -DisplayName "Artikelinhalt" -Type Note
    Ensure-GPLookupField -List "Knowledge" -InternalName "LinkedAssets" -DisplayName "Verknuepfte Assets" -LookupList "Assets" -Multi $true
    Ensure-GPLookupField -List "Knowledge" -InternalName "LinkedSystems" -DisplayName "Verknuepfte Systeme" -LookupList "Systems" -Multi $true

    # Catalogs
    Ensure-GPListField -List "AssetTypes" -InternalName "DefaultCriticality" -DisplayName "Standard-Kritikalitaet" -Type Choice -Choices $criticality
    Ensure-GPListField -List "AssetTypes" -InternalName "DefaultReviewCycleMonths" -DisplayName "Standard-Review-Zyklus Monate" -Type Number
    Ensure-GPListField -List "RiskCatalog" -InternalName "AppliesToAssetType" -DisplayName "Gilt fuer Asset-Typ" -Type Text
    Ensure-GPListField -List "RiskCatalog" -InternalName "DefaultLikelihood" -DisplayName "Standard-Eintrittswahrscheinlichkeit" -Type Choice -Choices @("1 Very Low", "2 Low", "3 Medium", "4 High", "5 Very High")
    Ensure-GPListField -List "RiskCatalog" -InternalName "DefaultImpact" -DisplayName "Standard-Auswirkung" -Type Choice -Choices @("1 Very Low", "2 Low", "3 Medium", "4 High", "5 Very High")
    Ensure-GPListField -List "ControlCatalog" -InternalName "AppliesToAssetType" -DisplayName "Gilt fuer Asset-Typ" -Type Text
    Ensure-GPListField -List "ControlCatalog" -InternalName "DefaultControlType" -DisplayName "Standard-Control-Typ" -Type Choice -Choices @("Preventive", "Detective", "Corrective", "Directive", "Compensating")
    Ensure-GPListField -List "MeasureTemplates" -InternalName "TemplatePriority" -DisplayName "Vorlagen-Prioritaet" -Type Choice -Choices $priority
    Ensure-GPListField -List "MeasureTemplates" -InternalName "DefaultDueDays" -DisplayName "Standardfaelligkeit Tage" -Type Number
    Ensure-GPListField -List "ReviewTemplates" -InternalName "ObjectType" -DisplayName "Objekttyp" -Type Choice -Choices @("Asset", "System", "Risk", "Control", "Measure", "Change", "Incident", "Problem", "Evidence")
    Ensure-GPListField -List "ReviewTemplates" -InternalName "ReviewCycleMonthsTemplate" -DisplayName "Review-Zyklus Monate" -Type Number
    Ensure-GPListField -List "RoleCatalog" -InternalName "RoleType" -DisplayName "Rollentyp" -Type Choice -Choices @("Reader", "Contributor", "Governance Owner", "Governance Manager", "Portal Administrator", "Power Platform Admin", "Service Account")
    Ensure-GPListField -List "ComplianceMappings" -InternalName "Framework" -DisplayName "Framework" -Type Choice -Choices $scope
    Ensure-GPListField -List "ComplianceMappings" -InternalName "RequirementID" -DisplayName "Anforderungs-ID" -Type Text
    Ensure-GPListField -List "ComplianceMappings" -InternalName "RequirementText" -DisplayName "Anforderung" -Type Note
    Ensure-GPListField -List "GovernanceSettings" -InternalName "SettingKey" -DisplayName "Einstellungsschluessel" -Type Text
    Ensure-GPListField -List "GovernanceSettings" -InternalName "SettingValue" -DisplayName "Einstellungswert" -Type Note

    # Views
    $defaultFields = @("LinkTitle", "GovernanceID", "GovernanceStatus", "Owner", "Criticality", "NextReviewDate", "IsActive")
    foreach ($list in $lists.Title) {
        Ensure-GPView -List $list -Name "Aktive Eintraege" -Fields $defaultFields -Query "<Where><Eq><FieldRef Name='IsActive'/><Value Type='Boolean'>1</Value></Eq></Where>"
        Ensure-GPView -List $list -Name "Ueberfaellige Reviews" -Fields $defaultFields -Query "<Where><And><Eq><FieldRef Name='IsActive'/><Value Type='Boolean'>1</Value></Eq><Lt><FieldRef Name='NextReviewDate'/><Value Type='DateTime'><Today /></Value></Lt></And></Where>"
        Ensure-GPView -List $list -Name "Ohne Owner" -Fields $defaultFields -Query "<Where><IsNull><FieldRef Name='Owner'/></IsNull></Where>"
        Ensure-GPView -List $list -Name "Offen und in Bearbeitung" -Fields $defaultFields -Query "<Where><Or><Eq><FieldRef Name='GovernanceStatus'/><Value Type='Choice'>Open</Value></Eq><Eq><FieldRef Name='GovernanceStatus'/><Value Type='Choice'>In Progress</Value></Eq></Or></Where>"
    }

    Ensure-GPView -List "Risks" -Name "Nach Risiko-Score" -Fields @("LinkTitle", "GovernanceID", "RiskStatus", "RiskScore", "RiskTreatment", "Owner", "NextReviewDate") -Query "<OrderBy><FieldRef Name='RiskScore' Ascending='FALSE'/></OrderBy>"
    Ensure-GPView -List "Controls" -Name "Controls ohne Evidence" -Fields @("LinkTitle", "GovernanceID", "ControlStatus", "EvidenceRequired", "Effectiveness", "Owner", "NextReviewDate") -Query "<Where><Eq><FieldRef Name='EvidenceRequired'/><Value Type='Boolean'>1</Value></Eq></Where>"

    # Navigation
    Ensure-GPNavigationNode -Title "Dashboard" -Url "$SiteUrl/SitePages/Home.aspx"
    foreach ($nav in @("Assets", "Systems", "Risks", "Controls", "Measures", "Changes", "Incidents", "Problems", "Reviews")) {
        Ensure-GPNavigationNode -Title $nav -Url "$SiteUrl/Lists/$nav/AllItems.aspx"
    }
    Ensure-GPNavigationNode -Title "Evidence" -Url "$SiteUrl/Evidence"
    Ensure-GPNavigationNode -Title "Administration" -Url "$SiteUrl/Lists/GovernanceSettings/AllItems.aspx"

    if ($ProvisionSampleCatalogData -and -not $DryRun) {
        Write-GPLog "Fuege Beispiel-Katalogdaten hinzu" "INFO"
        Add-PnPListItem -List "AssetTypes" -Values @{Title="Cloud-Dienst"; GovernanceID="ATY-000001"; GovernanceStatus="Open"; Description="SaaS-/Cloud-basierter Dienst"; DefaultCriticality="High"; DefaultReviewCycleMonths=12; IsActive=$true} | Out-Null
        Add-PnPListItem -List "RiskCatalog" -Values @{Title="Kontoübernahme"; GovernanceID="RCG-000001"; GovernanceStatus="Open"; Description="Missbrauch kompromittierter Benutzerkonten"; AppliesToAssetType="Cloud-Dienst"; DefaultLikelihood="3 Medium"; DefaultImpact="4 High"; IsActive=$true} | Out-Null
        Add-PnPListItem -List "ControlCatalog" -Values @{Title="MFA aktiviert"; GovernanceID="CCG-000001"; GovernanceStatus="Open"; Description="Mehrfaktor-Authentifizierung ist aktiviert"; AppliesToAssetType="Cloud-Dienst"; DefaultControlType="Preventive"; IsActive=$true} | Out-Null
        Add-PnPListItem -List "ControlCatalog" -Values @{Title="Conditional Access"; GovernanceID="CCG-000002"; GovernanceStatus="Open"; Description="Risikobasierte Zugriffskontrolle ist eingerichtet"; AppliesToAssetType="Cloud-Dienst"; DefaultControlType="Preventive"; IsActive=$true} | Out-Null
    }

    Write-GPLog "Provisioning abgeschlossen. Logfile: $LogFile" "SUCCESS"
}
catch {
    Write-GPLog "Abbruch: $($_.Exception.Message)" "ERROR"
    Write-GPLog "Logfile: $LogFile" "INFO"
    throw
}




