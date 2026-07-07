param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl
)

# ============================================================
# BenutzerLifecycle Operations-Provisioning
# Erstellt:
# - BLC_LifecycleRequests
# - BLC_Employees
# - BLC_LifecycleTasks
# inkl. Lookup-Beziehungen
# ============================================================

$ErrorActionPreference = "Stop"
$LogFile = ".\BenutzerLifecycle-Operations-Provisioning-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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
        Add-FieldToDefaultViewSafe -ListName $TargetListName -FieldInternalName $InternalName
    }

    Write-Log "Lookup-Feld erstellt: $TargetListName.$InternalName" "SUCCESS"
}

# ============================================================
# Voraussetzungen prüfen
# ============================================================

$requiredLists = @(
    "BLC_Entitlements",
    "BLC_RoleProfiles",
    "BLC_RoleEntitlements"
)

foreach ($requiredList in $requiredLists) {
    $list = Get-PnPList -Identity $requiredList -ErrorAction SilentlyContinue

    if (-not $list) {
        Stop-WithHelp `
            "Voraussetzung fehlt: Liste '$requiredList' wurde nicht gefunden." `
            "Führe zuerst die vorherigen Provisioning-Scripte für Entitlements und Rollen aus."
    }
}

# ============================================================
# Listen erstellen
# ============================================================

Ensure-List -Title "BLC_LifecycleRequests" -OnQuickLaunch
Ensure-List -Title "BLC_Employees" -OnQuickLaunch
Ensure-List -Title "BLC_LifecycleTasks" -OnQuickLaunch

# ============================================================
# Choice-Werte
# ============================================================

$requestTypes = @(
    "Onboarding",
    "Mover",
    "Offboarding",
    "AccessRequest",
    "LicenseChange",
    "HardwareChange",
    "RoleChange",
    "Review",
    "Other"
)

$lifecycleStatuses = @(
    "Draft",
    "Submitted",
    "InReview",
    "Approved",
    "Rejected",
    "InProgress",
    "WaitingForInput",
    "Completed",
    "Cancelled",
    "Archived"
)

$approvalStatuses = @(
    "NotRequired",
    "Pending",
    "Approved",
    "Rejected",
    "Delegated",
    "Expired"
)

$priorities = @(
    "Low",
    "Normal",
    "High",
    "Critical"
)

$employmentTypes = @(
    "Employee",
    "Worker",
    "Apprentice",
    "External",
    "Temporary",
    "ServiceAccount",
    "Other"
)

$accountStatuses = @(
    "Planned",
    "Active",
    "Disabled",
    "Blocked",
    "Leaving",
    "Left",
    "Archived"
)

$taskCategories = @(
    "IT",
    "HR",
    "Fachabteilung",
    "Compliance",
    "Datenschutz",
    "Facility",
    "Einkauf",
    "Vorgesetzter",
    "System",
    "Other"
)

$taskOwnerGroups = @(
    "IT",
    "HR",
    "Fachabteilung",
    "Compliance",
    "Datenschutz",
    "Facility",
    "Einkauf",
    "Vorgesetzter"
)

$taskStatuses = @(
    "Open",
    "InProgress",
    "Blocked",
    "Completed",
    "Skipped",
    "Failed",
    "Cancelled"
)

# ============================================================
# BLC_LifecycleRequests Felder
# ============================================================

Write-Log "Provisioniere Felder für BLC_LifecycleRequests ..."

Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Lifecycle ID" -InternalName "LifecycleID" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Request Type" -InternalName "RequestType" -Type Choice -Choices $requestTypes -Required $true -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Target Display Name" -InternalName "TargetDisplayName" -Type Text -Required $true -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Target UPN" -InternalName "TargetUPN" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Employee ID" -InternalName "EmployeeID" -Type Text
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Department" -InternalName "Department" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Location" -InternalName "Location" -Type Text
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Manager" -InternalName "Manager" -Type User -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Requested By" -InternalName "RequestedBy" -Type User
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "HR Responsible" -InternalName "HRResponsible" -Type User
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Start Date" -InternalName "StartDate" -Type DateTime -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Effective Date" -InternalName "EffectiveDate" -Type DateTime
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "End Date" -InternalName "EndDate" -Type DateTime
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Lifecycle Status" -InternalName "LifecycleStatus" -Type Choice -Choices $lifecycleStatuses -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Approval Status" -InternalName "ApprovalStatus" -Type Choice -Choices $approvalStatuses -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Priority" -InternalName "Priority" -Type Choice -Choices $priorities -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Review Cycle Months" -InternalName "ReviewCycleMonths" -Type Number
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Last Review" -InternalName "LastReview" -Type DateTime
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Next Review" -InternalName "NextReview" -Type DateTime
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Employee Created" -InternalName "EmployeeCreated" -Type Boolean
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Tasks Created" -InternalName "TasksCreated" -Type Boolean
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Flow Run URL" -InternalName "FlowRunUrl" -Type URL
Ensure-Field -ListName "BLC_LifecycleRequests" -DisplayName "Comments" -InternalName "Comments" -Type Note

Ensure-LookupField `
    -TargetListName "BLC_LifecycleRequests" `
    -DisplayName "Role Profile" `
    -InternalName "RoleProfile" `
    -SourceListName "BLC_RoleProfiles" `
    -ShowField "Title" `
    -Required $false `
    -AddToDefaultView

# ============================================================
# BLC_Employees Felder
# ============================================================

Write-Log "Provisioniere Felder für BLC_Employees ..."

Ensure-Field -ListName "BLC_Employees" -DisplayName "Employee Lifecycle ID" -InternalName "EmployeeLifecycleID" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "Employee ID" -InternalName "EmployeeID" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "Display Name" -InternalName "DisplayName" -Type Text -Required $true -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "UPN" -InternalName "UPN" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "Department" -InternalName "Department" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "Location" -InternalName "Location" -Type Text
Ensure-Field -ListName "BLC_Employees" -DisplayName "Manager" -InternalName "Manager" -Type User -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "Employment Type" -InternalName "EmploymentType" -Type Choice -Choices $employmentTypes
Ensure-Field -ListName "BLC_Employees" -DisplayName "Start Date" -InternalName "StartDate" -Type DateTime -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "End Date" -InternalName "EndDate" -Type DateTime
Ensure-Field -ListName "BLC_Employees" -DisplayName "Account Status" -InternalName "AccountStatus" -Type Choice -Choices $accountStatuses -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "Primary Device" -InternalName "PrimaryDevice" -Type Text
Ensure-Field -ListName "BLC_Employees" -DisplayName "Mobile Device" -InternalName "MobileDevice" -Type Text
Ensure-Field -ListName "BLC_Employees" -DisplayName "Phone Number" -InternalName "PhoneNumber" -Type Text
Ensure-Field -ListName "BLC_Employees" -DisplayName "Last Access Review" -InternalName "LastAccessReview" -Type DateTime
Ensure-Field -ListName "BLC_Employees" -DisplayName "Next Access Review" -InternalName "NextAccessReview" -Type DateTime
Ensure-Field -ListName "BLC_Employees" -DisplayName "Active" -InternalName "Active" -Type Boolean -AddToDefaultView
Ensure-Field -ListName "BLC_Employees" -DisplayName "Notes" -InternalName "Notes" -Type Note

Ensure-LookupField `
    -TargetListName "BLC_Employees" `
    -DisplayName "Role Profile" `
    -InternalName "RoleProfile" `
    -SourceListName "BLC_RoleProfiles" `
    -ShowField "Title" `
    -Required $false `
    -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_Employees" `
    -DisplayName "Source Lifecycle Request" `
    -InternalName "SourceLifecycleRequest" `
    -SourceListName "BLC_LifecycleRequests" `
    -ShowField "Title" `
    -Required $false

# Jetzt kann der Request optional auch auf den erzeugten Employee zeigen
Ensure-LookupField `
    -TargetListName "BLC_LifecycleRequests" `
    -DisplayName "Related Employee" `
    -InternalName "RelatedEmployee" `
    -SourceListName "BLC_Employees" `
    -ShowField "Title" `
    -Required $false

# ============================================================
# BLC_LifecycleTasks Felder
# ============================================================

Write-Log "Provisioniere Felder für BLC_LifecycleTasks ..."

Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Task ID" -InternalName "TaskID" -Type Text -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Task Title" -InternalName "TaskTitle" -Type Text -Required $true -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Task Description" -InternalName "TaskDescription" -Type Note
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Task Category" -InternalName "TaskCategory" -Type Choice -Choices $taskCategories -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Task Owner Group" -InternalName "TaskOwnerGroup" -Type Choice -Choices $taskOwnerGroups -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Assigned To" -InternalName "AssignedTo" -Type User -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Due Date" -InternalName "DueDate" -Type DateTime -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Task Status" -InternalName "TaskStatus" -Type Choice -Choices $taskStatuses -AddToDefaultView
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Priority" -InternalName "Priority" -Type Choice -Choices $priorities
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Requires Evidence" -InternalName "RequiresEvidence" -Type Boolean
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Evidence Description" -InternalName "EvidenceDescription" -Type Note
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Evidence Link" -InternalName "EvidenceLink" -Type URL
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Completed By" -InternalName "CompletedBy" -Type User
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Completed Date" -InternalName "CompletedDate" -Type DateTime
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Automation State" -InternalName "AutomationState" -Type Choice -Choices @(
    "Manual",
    "Pending",
    "Automated",
    "Failed",
    "Skipped"
)
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Automation Error" -InternalName "AutomationError" -Type Note
Ensure-Field -ListName "BLC_LifecycleTasks" -DisplayName "Comment" -InternalName "Comment" -Type Note

Ensure-LookupField `
    -TargetListName "BLC_LifecycleTasks" `
    -DisplayName "Related Lifecycle Request" `
    -InternalName "RelatedLifecycleRequest" `
    -SourceListName "BLC_LifecycleRequests" `
    -ShowField "Title" `
    -Required $true `
    -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_LifecycleTasks" `
    -DisplayName "Related Employee" `
    -InternalName "RelatedEmployee" `
    -SourceListName "BLC_Employees" `
    -ShowField "Title" `
    -Required $false `
    -AddToDefaultView

Ensure-LookupField `
    -TargetListName "BLC_LifecycleTasks" `
    -DisplayName "Related Entitlement" `
    -InternalName "RelatedEntitlement" `
    -SourceListName "BLC_Entitlements" `
    -ShowField "Title" `
    -Required $false `
    -AddToDefaultView

# ============================================================
# Abschluss
# ============================================================

Write-Log "Operations-Provisioning erfolgreich abgeschlossen." "SUCCESS"

Write-Host ""
Write-Host "Fertig. Erstellt/aktualisiert:" -ForegroundColor Green
Write-Host "- BLC_LifecycleRequests"
Write-Host "- BLC_Employees"
Write-Host "- BLC_LifecycleTasks"
Write-Host ""
Write-Host "Nächster Schritt: Flow 'BLC - Onboarding - Create Employee And Tasks'." -ForegroundColor Cyan