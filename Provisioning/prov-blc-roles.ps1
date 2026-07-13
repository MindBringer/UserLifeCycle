param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl
)

# ============================================================
# BenutzerLifecycle Rollen-Provisioning
# Erstellt:
# - BLC_RoleProfiles
# - BLC_RoleEntitlements
# - Lookup-Verknüpfungen zu BLC_Entitlements und BLC_RoleProfiles
# ============================================================

$ErrorActionPreference = "Stop"
$LogFile = ".\BenutzerLifecycle-Roles-Provisioning-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Stop-WithHelp {
    param(
        [string]$Message,
        [string]$HelpText
    )

    Write-Log $Message "ERROR"
    Write-Host ""
    Write-Host "Hinweis:" -ForegroundColor Yellow
    Write-Host $HelpText -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ============================================================
# Checks
# ============================================================

if ($PSVersionTable.PSVersion.Major -lt 7 -or (
        $PSVersionTable.PSVersion.Major -eq 7 -and
        $PSVersionTable.PSVersion.Minor -lt 4
    )) {
    Stop-WithHelp `
        "PowerShell 7.4 oder höher erforderlich." `
        "Installiere PowerShell 7.4 oder höher und starte das Script erneut."
}

if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Stop-WithHelp `
        "PnP.PowerShell Modul wurde nicht gefunden." `
        "Installiere es mit: Install-Module PnP.PowerShell -Scope CurrentUser"
}

$processPolicy = Get-ExecutionPolicy -Scope Process
if ($processPolicy -ne "Bypass") {
    Write-Log "ExecutionPolicy im aktuellen Prozess ist '$processPolicy'. Falls das Script blockiert wird: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass" "WARN"
}

# ============================================================
# Verbindung
# ============================================================

try {
    Write-Log "Verbinde mit $SiteUrl ..."
    Connect-PnPOnline -Url $SiteUrl -Interactive
    Write-Log "Verbindung hergestellt."
}
catch {
    Stop-WithHelp `
        "Verbindung zu SharePoint fehlgeschlagen: $($_.Exception.Message)" `
        "Prüfe SiteUrl, Berechtigungen und ob der angemeldete Benutzer Besitzer/Administrator der Site ist."
}

# ============================================================
# Helper
# ============================================================

function Ensure-List {
    param(
        [string]$Title,
        [switch]$OnQuickLaunch
    )

    $list = Get-PnPList -Identity $Title -ErrorAction SilentlyContinue

    if (-not $list) {
        Write-Log "Erstelle Liste: $Title"

        if ($OnQuickLaunch) {
            New-PnPList -Title $Title -Template GenericList -EnableVersioning -OnQuickLaunch | Out-Null
        }
        else {
            New-PnPList -Title $Title -Template GenericList -EnableVersioning | Out-Null
        }

        Write-Log "Liste erstellt: $Title" "SUCCESS"
    }
    else {
        Write-Log "Liste existiert bereits: $Title"
    }
}

function Ensure-Field {
    param(
        [string]$ListName,
        [string]$DisplayName,
        [string]$InternalName,
        [ValidateSet("Text", "Note", "Boolean", "Number", "Choice", "DateTime", "User")]
        [string]$Type,
        [string[]]$Choices = @(),
        [bool]$Required = $false,
        [switch]$AddToDefaultView
    )

    $field = Get-PnPField -List $ListName -Identity $InternalName -ErrorAction SilentlyContinue

    if ($field) {
        Write-Log "Feld existiert bereits: $ListName.$InternalName"
        return
    }

    Write-Log "Erstelle Feld: $ListName.$InternalName"

    $params = @{
        List         = $ListName
        DisplayName  = $DisplayName
        InternalName = $InternalName
        Type         = $Type
        Required     = $Required
    }

    if ($AddToDefaultView) {
        $params.AddToDefaultView = $true
    }

    if ($Type -eq "Choice") {
        $params.Choices = $Choices
    }

    Add-PnPField @params | Out-Null

    Write-Log "Feld erstellt: $ListName.$InternalName" "SUCCESS"
}

function Ensure-LookupField {
    param(
        [string]$TargetListName,
        [string]$DisplayName,
        [string]$InternalName,
        [string]$SourceListName,
        [string]$ShowField = "Title",
        [bool]$Required = $false,
        [switch]$AddToDefaultView
    )

    $existing = Get-PnPField -List $TargetListName -Identity $InternalName -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Log "Lookup-Feld existiert bereits: $TargetListName.$InternalName"
        return
    }

    $sourceList = Get-PnPList -Identity $SourceListName -ErrorAction SilentlyContinue

    if (-not $sourceList) {
        throw "Quellliste '$SourceListName' nicht gefunden. Lookup-Feld '$InternalName' kann nicht erstellt werden."
    }

    $requiredValue = if ($Required) { "TRUE" } else { "FALSE" }
    $fieldId = [guid]::NewGuid().ToString()

    $fieldXml = @"
<Field Type="Lookup"
       DisplayName="$DisplayName"
       StaticName="$InternalName"
       Name="$InternalName"
       ID="{$fieldId}"
       Required="$requiredValue"
       List="{$($sourceList.Id)}"
       ShowField="$ShowField"
       RelationshipDeleteBehavior="None"
       Group="BenutzerLifecycle" />
"@

    Write-Log "Erstelle Lookup-Feld: $TargetListName.$InternalName -> $SourceListName.$ShowField"

    Add-PnPFieldFromXml -List $TargetListName -FieldXml $fieldXml | Out-Null

    if ($AddToDefaultView) {
        try {
            Add-PnPViewField -List $TargetListName -Identity "All Items" -Fields $InternalName -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Konnte Lookup-Feld nicht zur Standardansicht hinzufügen: $InternalName" "WARN"
        }
    }

    Write-Log "Lookup-Feld erstellt: $TargetListName.$InternalName" "SUCCESS"
}

function Ensure-ItemByTitle {
    param(
        [string]$ListName,
        [string]$Title,
        [hashtable]$Values
    )

    $escapedTitle = $Title.Replace("'", "''")
    $existing = Get-PnPListItem -List $ListName -Query "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$escapedTitle</Value></Eq></Where></Query></View>" -ErrorAction SilentlyContinue

    if ($existing.Count -gt 0) {
        Write-Log "Beispieleintrag existiert bereits: $ListName / $Title"
        return
    }

    $Values["Title"] = $Title
    Add-PnPListItem -List $ListName -Values $Values | Out-Null
    Write-Log "Beispieleintrag erstellt: $ListName / $Title" "SUCCESS"
}

# ============================================================
# Voraussetzungen
# ============================================================

$entitlementsList = Get-PnPList -Identity "BLC_Entitlements" -ErrorAction SilentlyContinue

if (-not $entitlementsList) {
    Stop-WithHelp `
        "Die Liste BLC_Entitlements wurde nicht gefunden." `
        "Führe zuerst das Entitlements-Provisioning aus oder lege die Liste BLC_Entitlements an."
}

# ============================================================
# Listen erstellen
# ============================================================

Ensure-List -Title "BLC_RoleProfiles" -OnQuickLaunch
Ensure-List -Title "BLC_RoleEntitlements" -OnQuickLaunch

# ============================================================
# BLC_RoleProfiles Felder
# ============================================================

Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Role Profile ID" -InternalName "RoleProfileID" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Role Name" -InternalName "RoleName" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Department" -InternalName "Department" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Location" -InternalName "Location" -Type Text
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Employment Type" -InternalName "EmploymentType" -Type Choice -Choices @(
    "Employee",
    "Worker",
    "Apprentice",
    "External",
    "Temporary",
    "ServiceAccount",
    "Other"
) -AddToDefaultView

Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Description" -InternalName "Description" -Type Note
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Business Owner" -InternalName "BusinessOwner" -Type User
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "IT Owner" -InternalName "ITOwner" -Type User
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "HR Responsible" -InternalName "HRResponsible" -Type User

Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Risk Level" -InternalName "RiskLevel" -Type Choice -Choices @(
    "Low",
    "Medium",
    "High",
    "Critical"
) -AddToDefaultView

Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Review Cycle Months" -InternalName "ReviewCycleMonths" -Type Number
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Active" -InternalName "Active" -Type Boolean -AddToDefaultView
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Valid From" -InternalName "ValidFrom" -Type DateTime
Ensure-Field -ListName "BLC_RoleProfiles" -DisplayName "Valid To" -InternalName "ValidTo" -Type DateTime

# ============================================================
# BLC_RoleEntitlements Felder
# ============================================================

Ensure-LookupField `
    -TargetListName "BLC_RoleEntitlements" `
    -DisplayName "Role Profile" `
    -InternalName "RoleProfile" `
    -SourceListName "BLC_RoleProfiles" `
    -ShowField "Title" `
    -Required $true `
    -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_RoleEntitlements" `
    -DisplayName "Entitlement" `
    -InternalName "Entitlement" `
    -SourceListName "BLC_Entitlements" `
    -ShowField "Title" `
    -Required $true `
    -AddToDefaultView

Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Required For Joiner" -InternalName "RequiredForJoiner" -Type Boolean -AddToDefaultView
Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Required For Mover" -InternalName "RequiredForMover" -Type Boolean
Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Required For Leaver" -InternalName "RequiredForLeaver" -Type Boolean

Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Mandatory" -InternalName "IsMandatory" -Type Boolean
Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Can Be Deselected" -InternalName "CanBeDeselected" -Type Boolean
Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Active" -InternalName "Active" -Type Boolean -AddToDefaultView

Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Task Owner Group Override" -InternalName "TaskOwnerGroupOverride" -Type Choice -Choices @(
    "IT",
    "HR",
    "Fachabteilung",
    "Compliance",
    "Datenschutz",
    "Facility",
    "Einkauf",
    "Vorgesetzter"
)

Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Assigned To Override" -InternalName "AssignedToOverride" -Type User
Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Due Offset Days Override" -InternalName "DueOffsetDaysOverride" -Type Number
Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Requires Approval Override" -InternalName "RequiresApprovalOverride" -Type Boolean

Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Task Title Override Joiner" -InternalName "TaskTitleOverride_Joiner" -Type Text
Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Task Description Override Joiner" -InternalName "TaskDescriptionOverride_Joiner" -Type Note

Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Task Title Override Mover" -InternalName "TaskTitleOverride_Mover" -Type Text
Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Task Description Override Mover" -InternalName "TaskDescriptionOverride_Mover" -Type Note

Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Task Title Override Leaver" -InternalName "TaskTitleOverride_Leaver" -Type Text
Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Task Description Override Leaver" -InternalName "TaskDescriptionOverride_Leaver" -Type Note

Ensure-Field -ListName "BLC_RoleEntitlements" -DisplayName "Comment" -InternalName "Comment" -Type Note

# ============================================================
# Beispiel-Rollen
# ============================================================

Write-Log "Erstelle Beispiel-Rollenprofile..."

Ensure-ItemByTitle -ListName "BLC_RoleProfiles" -Title "Verwaltung Standard" -Values @{
    RoleProfileID     = "ROLE-VERW-STD"
    RoleName          = "Verwaltung Standard"
    Department        = "Verwaltung"
    EmploymentType    = "Employee"
    RiskLevel         = "Medium"
    ReviewCycleMonths = 12
    Active            = $true
    Description       = "Standardrolle für Mitarbeitende in der Verwaltung."
}

Ensure-ItemByTitle -ListName "BLC_RoleProfiles" -Title "Produktion Standard" -Values @{
    RoleProfileID     = "ROLE-PROD-STD"
    RoleName          = "Produktion Standard"
    Department        = "Produktion"
    EmploymentType    = "Employee"
    RiskLevel         = "Medium"
    ReviewCycleMonths = 12
    Active            = $true
    Description       = "Standardrolle für Mitarbeitende in der Produktion."
}

Ensure-ItemByTitle -ListName "BLC_RoleProfiles" -Title "IT Standard" -Values @{
    RoleProfileID     = "ROLE-IT-STD"
    RoleName          = "IT Standard"
    Department        = "IT"
    EmploymentType    = "Employee"
    RiskLevel         = "High"
    ReviewCycleMonths = 6
    Active            = $true
    Description       = "Standardrolle für IT-Mitarbeitende ohne privilegierte Adminrolle."
}

Ensure-ItemByTitle -ListName "BLC_RoleProfiles" -Title "IT Admin" -Values @{
    RoleProfileID     = "ROLE-IT-ADMIN"
    RoleName          = "IT Admin"
    Department        = "IT"
    EmploymentType    = "Employee"
    RiskLevel         = "Critical"
    ReviewCycleMonths = 3
    Active            = $true
    Description       = "Privilegierte Rolle für administrative IT-Aufgaben. Muss regelmäßig geprüft werden."
}

Write-Log "Rollen-Provisioning erfolgreich abgeschlossen." "SUCCESS"
Write-Host ""
Write-Host "Fertig. Erstellt/aktualisiert:" -ForegroundColor Green
Write-Host "- BLC_RoleProfiles"
Write-Host "- BLC_RoleEntitlements"
Write-Host ""
Write-Host "Nächster Schritt: Power-App / Rollenmaske oder LifecycleRequests + Employees + Tasks." -ForegroundColor Cyan