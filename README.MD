# BenutzerLifeCycle

Enterprise-Lösung für das Benutzer-Lifecycle-Management auf Basis von Microsoft 365, SharePoint Online, Power Apps und Power Automate.

---

# Übersicht

**BenutzerLifeCycle** unterstützt die vollständige Verwaltung des Benutzerlebenszyklus innerhalb der Steinicke Gruppe:

- Eintritt (Joiner)
- Wechsel (Mover)
- Austritt (Leaver)

Die Lösung kombiniert:

- Power Apps Canvas App
- Power Automate Workflows
- SharePoint Online als Datenplattform
- Rollen- und Berechtigungsmanagement
- Automatische Aufgabensteuerung
- Nachweis- und Compliance-Dokumentation

Der Fokus liegt auf:

- Governance
- Nachvollziehbarkeit
- Auditierbarkeit
- NIS2-Konformität
- Standardisierung von Benutzerprozessen

---

# Funktionsumfang

## Benutzer-Vorgänge

Verwaltung von:

- Eintritt
- Wechsel
- Austritt

Mögliche Vorgangsstatus:

```text
Draft
Submitted
InReview
Approved
Rejected
InProgress
WaitingForInput
Completed
Cancelled
Archived
```

---

## Mitarbeiterverwaltung

Liste:

```text
BLC_Employees
```

Enthält unter anderem:

- Anzeigename
- UPN
- E-Mail
- Abteilung
- Vorgesetzter
- Rollenprofil
- Beschäftigungsstatus

---

## Rollenmanagement

Liste:

```text
BLC_RoleProfiles
```

Beispiele:

```text
Vertrieb Innendienst
Produktion Seerau
Qualitätsmanagement
IT Administrator
```

Felder:

```text
Role Profile ID
Role Name
Description
Department
Active
```

---

## Berechtigungsmanagement

Liste:

```text
BLC_Entitlements
```

Kategorien:

```text
M365
Identity
Security
Network
Hardware
Workplace
Telephony
HR
Application
Compliance
Other
```

In der App werden die Kategorien deutsch dargestellt.

Beispiel:

```text
Microsoft 365  → M365
Identität      → Identity
Telefonie      → Telephony
Anwendung      → Application
```

---

## Rollen-Berechtigungs-Mapping

Liste:

```text
BLC_RoleEntitlements
```

Beispiel:

```text
Rolle:
Produktion Standard

Berechtigungen:
- Microsoft 365 E3
- Apollo ERP
- Produktionsdrucker
```

---

## Automatische Aufgabenerstellung

Tasks werden automatisch erzeugt auf Basis von:

```text
Vorgang
+
Rollenprofil
+
zugeordnete Berechtigungen
```

Status:

```text
Open
InProgress
WaitingForInput
Completed
Skipped
Cancelled
```

---

## Nachweise und Dokumentation

Tasks können Nachweise verlangen.

Unterstützte Felder:

```text
Requires Evidence
Evidence Description
Evidence Link
Comment
Completed By
Completed Date
```

---

# Architektur

```text
Lifecycle Request
        │
        ▼
Role Profile
        │
        ▼
Entitlements
        │
        ▼
Lifecycle Tasks
        │
        ▼
Task Completion Rollup
        │
        ▼
Request abgeschlossen
```

---

# Power App Screens

## Startseite

Zentraler Einstiegspunkt.

---

## Vorgangsübersicht

```text
scrLifecycleRequestOverview
```

Funktionen:

- Vorgänge anzeigen
- Nach Status filtern
- Aktive Vorgänge anzeigen
- Neue Vorgänge anlegen
- Aufgaben anzeigen

---

## Neuer Vorgang

```text
scrRequestNew
```

Unterstützt:

```text
Eintritt
Wechsel
Austritt
```

Dynamische Formulare und Validierung je Vorgangsart.

---

## Aufgaben-Details

```text
scrTaskDetail
```

Funktionen:

- Aufgabendetails anzeigen
- Kommentar erfassen
- Nachweis-Link erfassen
- In Arbeit setzen
- Wartet auf Eingabe
- Aufgabe abschließen
- Aufgabe überspringen

---

## Rollen- und Rechteverwaltung

```text
scrRoleEntitlementManager
```

Funktionen:

- Rollen anzeigen
- Berechtigungen anzeigen
- Zuordnungen verwalten
- Filterung nach Kategorien

---

## Stammdaten erfassen

```text
scrMasterDataEdit
```

Erstellung von:

```text
Rollenprofilen
Berechtigungen
```

---

# Power Automate Flows

## AssignLifecycleID

Vergibt eindeutige Lifecycle-IDs.

Beispiele:

```text
BLC-ONB-2026-000001
BLC-MOV-2026-000034
BLC-OFB-2026-000010
```

---

## Onboarding-CreateEmployeeAndTasks

Erzeugt:

- Mitarbeiterdatensatz
- Rollenprofil-Zuordnung
- Onboarding-Aufgaben

---

## Mover-CreateChangeTasks

Erzeugt Aufgaben für Rollen- oder Abteilungswechsel.

---

## Leaver-CreateOffboardingTasks

Erzeugt Offboarding-Aufgaben.

---

## TaskCompletionRollup

Überwacht den Status aller Aufgaben.

Ein Request gilt als abgeschlossen, wenn alle Tasks den Status besitzen:

```text
Completed
Skipped
Cancelled
```

---

# Datenmodell

## Hauptlisten

```text
BLC_LifecycleRequests
BLC_Employees
BLC_RoleProfiles
BLC_Entitlements
BLC_RoleEntitlements
BLC_LifecycleTasks
```

---

# Repository-Struktur

```text
UserLifeCycle
│
├─ src
│  └─ BenutzerLifeCycle
│      ├─ CanvasApps
│      ├─ Workflows
│      ├─ Other
│      └─ Solution.xml
│
├─ provisioning
│
├─ docs
│
├─ export
│
└─ README.md
```

---

# Export der Solution

Anmeldung:

```powershell
pac auth create
```

Umgebung auswählen:

```powershell
pac org select
```

Solution exportieren:

```powershell
pac solution export `
  --name BenutzerLifeCycle `
  --path export/BenutzerLifeCycle.zip `
  --managed false
```

---

# Solution entpacken

```powershell
pac solution unpack `
  --zipfile export/BenutzerLifeCycle.zip `
  --folder src/BenutzerLifeCycle `
  --packagetype Unmanaged
```

---

# GitHub-Workflow

Änderungen prüfen:

```powershell
git status
```

Dateien übernehmen:

```powershell
git add .
```

Commit erstellen:

```powershell
git commit -m "BenutzerLifeCycle Update"
```

Push nach GitHub:

```powershell
git push origin main
```

---

# Roadmap

Geplante Erweiterungen:

- Dokumentbibliothek für Nachweise
- Genehmigungsworkflows
- Benachrichtigungen
- Manager Self-Service
- KPI-Dashboard
- Reporting
- Audit-Auswertungen
- NIS2-Dokumentation
- KI-gestützte Prozessanalyse

---

# Version

```text
BenutzerLifeCycle
Version 1.0.0.6
```

---

# Autor

```text
Steinicke Gruppe
IT & Digitalisierung
```

Microsoft Power Platform basierte Lösung für das Benutzer-Lifecycle-Management.
