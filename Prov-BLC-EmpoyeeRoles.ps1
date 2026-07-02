param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl
)

$ErrorActionPreference = "Stop"
$LogFile = ".\BenutzerLifecycle-EmployeeRoles-Provisioning-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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
# Connect
# ============================================================

try {
    Write-Log "Verbinde mit $SiteUrl ..."
    Connect-PnPOnline -Url $SiteUrl -Interactive
    Write-Log "Verbindung hergestellt." "SUCCESS"
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
        [ValidateSet("Text", "Note", "Boolean", "Number", "Choice", "DateTime", "User", "URL")]
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
        $params.Add("AddToDefaultView", $true)
    }

    if ($Type -eq "Choice") {
        $params.Add("Choices", $Choices)
    }

    Add-PnPField @params | Out-Null
    Write-Log "Feld erstellt: $ListName.$InternalName" "SUCCESS"
}

function Add-FieldToDefaultViewSafe {
    param(
        [string]$ListName,
        [string]$FieldInternalName
    )

    try {
        $views = Get-PnPView -List $ListName
        $defaultView = $views | Where-Object { $_.DefaultView -eq $true } | Select-Object -First 1

        if ($null -ne $defaultView) {
            Add-PnPViewField -List $ListName -Identity $defaultView.Id -Fields $FieldInternalName -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "Konnte Feld nicht zur Standardansicht hinzufügen: $ListName.$FieldInternalName - $($_.Exception.Message)" "WARN"
    }
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
    $fieldId = [Guid]::NewGuid().ToString()

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
        Add-FieldToDefaultViewSafe -ListName $TargetListName -FieldInternalName $InternalName
    }

    Write-Log "Lookup-Feld erstellt: $TargetListName.$InternalName" "SUCCESS"
}

# ============================================================
# Voraussetzungen prüfen
# ============================================================

$requiredLists = @(
    "BLC_Employees",
    "BLC_RoleProfiles",
    "BLC_LifecycleRequests"
)

foreach ($requiredList in $requiredLists) {
    $list = Get-PnPList -Identity $requiredList -ErrorAction SilentlyContinue

    if (-not $list) {
        Stop-WithHelp `
            "Voraussetzung fehlt: Liste '$requiredList' wurde nicht gefunden." `
            "Führe zuerst die bisherigen BenutzerLifecycle-Provisioning-Scripte aus."
    }
}

# ============================================================
# Neue Listen erstellen
# ============================================================

Ensure-List -Title "BLC_EmployeeRoles" -OnQuickLaunch
Ensure-List -Title "BLC_EmployeeIdentityChanges" -OnQuickLaunch

# ============================================================
# BLC_Employees erweitern
# ============================================================

Write-Log "Erweitere BLC_Employees ..."

Ensure-Field -ListName "BLC_Employees" -DisplayName "Email" -InternalName "Email" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "First Name" -InternalName "FirstName" -Type Text
Ensure-Field -ListName "BLC_Employees" -DisplayName "Last Name" -InternalName "LastName" -Type Text
Ensure-Field -ListName "BLC_Employees" -DisplayName "Former Display Name" -InternalName "FormerDisplayName" -Type Text
Ensure-Field -ListName "BLC_Employees" -DisplayName "Last Identity Change" -InternalName "LastIdentityChange" -Type DateTime
Ensure-Field -ListName "BLC_Employees" -DisplayName "Last Role Change" -InternalName "LastRoleChange" -Type DateTime

# ============================================================
# BLC_LifecycleRequests erweitern
# ============================================================

Write-Log "Erweitere BLC_LifecycleRequests ..."

Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Requested First Name" -InternalName "RequestedFirstName" -Type Text
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Requested Last Name" -InternalName "RequestedLastName" -Type Text
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Requested Display Name" -InternalName "RequestedDisplayName" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Requested UPN" -InternalName "RequestedUPN" -Type Text
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Requested Email" -InternalName "RequestedEmail" -Type Text
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Requested Phone Number" -InternalName "RequestedPhoneNumber" -Type Text
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Identity Change Required" -InternalName "IdentityChangeRequired" -Type Boolean -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Role Change Required" -InternalName "RoleChangeRequired" -Type Boolean -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Completed Date" -InternalName "CompletedDate" -Type DateTime

Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Identity Change Reason" -InternalName "IdentityChangeReason" -Type Choice -Choices @(
    "Marriage",
    "Divorce",
    "Correction",
    "RoleChange",
    "DepartmentChange",
    "Other"
)

# ============================================================
# BLC_EmployeeRoles Felder
# ============================================================

Write-Log "Provisioniere BLC_EmployeeRoles ..."

Ensure-Field -ListName "BLC_EmployeeRoles" -DisplayName "Employee Role ID" -InternalName "EmployeeRoleID" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeRoles" -DisplayName "Lifecycle ID" -InternalName "LifecycleID" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeRoles" -DisplayName "Valid From" -InternalName "ValidFrom" -Type DateTime -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeRoles" -DisplayName "Valid To" -InternalName "ValidTo" -Type DateTime -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeRoles" -DisplayName "Active" -InternalName "Active" -Type Boolean -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeRoles" -DisplayName "Is Primary Role" -InternalName "IsPrimaryRole" -Type Boolean -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeRoles" -DisplayName "Created By Flow" -InternalName "CreatedByFlow" -Type Boolean
Ensure-Field -ListName "BLC_EmployeeRoles" -DisplayName "Comment" -InternalName "Comment" -Type Note

Ensure-Field -ListName "BLC_EmployeeRoles" -DisplayName "Assignment Reason" -InternalName "AssignmentReason" -Type Choice -Choices @(
    "Onboarding",
    "Mover",
    "Correction",
    "Temporary",
    "Manual",
    "Offboarding",
    "Other"
) -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_EmployeeRoles" `
    -DisplayName "Employee" `
    -InternalName "Employee" `
    -SourceListName "BLC_Employees" `
    -ShowField "Title" `
    -Required $true `
    -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_EmployeeRoles" `
    -DisplayName "Role Profile" `
    -InternalName "RoleProfile" `
    -SourceListName "BLC_RoleProfiles" `
    -ShowField "Title" `
    -Required $true `
    -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_EmployeeRoles" `
    -DisplayName "Lifecycle Request" `
    -InternalName "LifecycleRequest" `
    -SourceListName "BLC_LifecycleRequests" `
    -ShowField "Title" `
    -Required $false `
    -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_EmployeeRoles" `
    -DisplayName "Previous Employee Role" `
    -InternalName "PreviousEmployeeRole" `
    -SourceListName "BLC_EmployeeRoles" `
    -ShowField "Title" `
    -Required $false

# ============================================================
# BLC_EmployeeIdentityChanges Felder
# ============================================================

Write-Log "Provisioniere BLC_EmployeeIdentityChanges ..."

Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Lifecycle ID" -InternalName "LifecycleID" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Old First Name" -InternalName "OldFirstName" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "New First Name" -InternalName "NewFirstName" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Old Last Name" -InternalName "OldLastName" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "New Last Name" -InternalName "NewLastName" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Old Display Name" -InternalName "OldDisplayName" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "New Display Name" -InternalName "NewDisplayName" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Old UPN" -InternalName "OldUPN" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "New UPN" -InternalName "NewUPN" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Old Email" -InternalName "OldEmail" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "New Email" -InternalName "NewEmail" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Old Phone Number" -InternalName "OldPhoneNumber" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "New Phone Number" -InternalName "NewPhoneNumber" -Type Text
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Effective Date" -InternalName "EffectiveDate" -Type DateTime -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Applied Date" -InternalName "AppliedDate" -Type DateTime -AddToDefaultView
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Applied By Flow" -InternalName "AppliedByFlow" -Type Boolean
Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Comment" -InternalName "Comment" -Type Note

Ensure-Field -ListName "BLC_EmployeeIdentityChanges" -DisplayName "Change Reason" -InternalName "ChangeReason" -Type Choice -Choices @(
    "Marriage",
    "Divorce",
    "Correction",
    "RoleChange",
    "DepartmentChange",
    "Other"
) -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_EmployeeIdentityChanges" `
    -DisplayName "Employee" `
    -InternalName "Employee" `
    -SourceListName "BLC_Employees" `
    -ShowField "Title" `
    -Required $true `
    -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_EmployeeIdentityChanges" `
    -DisplayName "Lifecycle Request" `
    -InternalName "LifecycleRequest" `
    -SourceListName "BLC_LifecycleRequests" `
    -ShowField "Title" `
    -Required $false `
    -AddToDefaultView

# ============================================================
# Abschluss
# ============================================================

Write-Log "EmployeeRoles / IdentityChanges Provisioning erfolgreich abgeschlossen." "SUCCESS"

Write-Host ""
Write-Host "Fertig. Erstellt/aktualisiert:" -ForegroundColor Green
Write-Host "- BLC_EmployeeRoles"
Write-Host "- BLC_EmployeeIdentityChanges"
Write-Host "- BLC_Employees: Identity-Erweiterungen"
Write-Host "- BLC_LifecycleRequests: Requested Identity Fields + Change Flags"
Write-Host ""
Write-Host "Nächster Schritt:" -ForegroundColor Cyan
Write-Host "1. Onboarding-Flow erweitern: initiale EmployeeRole erstellen"
Write-Host "2. Initialisierungsflow für bestehende Employees bauen"
Write-Host "3. Mover-Flow auf EmployeeRoles + IdentityChanges umbauen"