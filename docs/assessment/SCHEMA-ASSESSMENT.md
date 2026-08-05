# BenutzerLifeCycle 2.0 – Schema Assessment

Stand: 2026-08-05

## Kurzfazit

Die SharePoint-Site enthält zwei parallel entstandene Datenmodelle:

- ältere Listen mit Präfix `BL_`
- neuere Listen mit Präfix `BLC_`

Da noch keine Echtdaten vorhanden sind, wird ein kontrollierter Greenfield-Neuaufbau empfohlen. Die parallelen Modelle sollten nicht weitergeführt oder miteinander verbunden werden.

## Aktuell gefundene Fachlisten

### Ältere Generation

- `BL_Assets`
- `BL_Aufgaben`
- `BL_Aufgabenkatalog`
- `BL_Rollenprofil_Aufgaben`
- `BL_Rollenprofile`
- `BL_TaskAreaOwners`
- `BL_Vorgaenge`

### Neuere Generation

- `BLC_EmployeeIdentityChanges`
- `BLC_EmployeeRoles`
- `BLC_Employees`
- `BLC_Entitlements`
- `BLC_LifecycleRequests`
- `BLC_LifecycleTasks`
- `BLC_RoleEntitlements`
- `BLC_RoleProfiles`

## Wesentliche Befunde

1. **Doppeltes Prozessmodell**
   - `BL_Vorgaenge` / `BL_Aufgaben`
   - `BLC_LifecycleRequests` / `BLC_LifecycleTasks`

2. **Doppeltes Rollenmodell**
   - `BL_Rollenprofile` / `BL_Rollenprofil_Aufgaben`
   - `BLC_RoleProfiles` / `BLC_RoleEntitlements`

3. **Gemischte Verantwortlichkeiten**
   - `BLC_Entitlements` enthält gleichzeitig Katalogdaten, Task-Vorlagen, Fälligkeiten, Zuweisungslogik und Nachweisanforderungen.
   - Diese Bereiche sollten im Zielmodell getrennt werden.

4. **Personenmodell zu flach**
   - `BLC_Employees` ist nicht ausreichend für Wiedereintritt, mehrere Beschäftigungen, Gesellschaftswechsel, externe Personen oder mehrere Konten.
   - Zielmodell: `BLC_Persons` + `BLC_Employments`.

5. **Fehlende technische Stabilität**
   - viele fachliche Schlüsselfelder sind weder indiziert noch eindeutig.
   - UPN/E-Mail dürfen nicht alleinige Primärschlüssel sein.
   - benötigt werden stabile IDs wie `PersonID`, `EmploymentID`, `EntraObjectID`, `ExternalSourceID`.

6. **Asset-Liste aktuell ohne Nutzdaten**
   - `BL_Assets` enthält keine fachlich belastbare Asset-Struktur.
   - Assets/Geräte sollten perspektivisch aus dem GovernancePortal synchronisiert werden.

## Zielmodell vor Produktivstart

### Personen und Organisation

- `BLC_Persons`
- `BLC_Employments`
- `BLC_Organizations`
- `BLC_Departments`
- `BLC_Locations`
- `BLC_Positions`

### Lifecycle

- `BLC_LifecycleRequests`
- `BLC_LifecycleTasks`
- `BLC_TaskTemplates`
- `BLC_AssignmentRules`
- `BLC_SLAProfiles`
- `BLC_Escalations`
- `BLC_AuditEvents`

### Rollen und Berechtigungen

- `BLC_RoleProfiles`
- `BLC_Entitlements`
- `BLC_RoleEntitlements`
- `BLC_UserRoleAssignments`
- `BLC_UserEntitlementAssignments`
- `BLC_ObservedEntitlements`
- `BLC_EntitlementExceptions`

### Import und Synchronisation

- `BLC_ImportRuns`
- `BLC_ImportErrors`
- `BLC_SyncRuns`
- `BLC_SyncErrors`

### Externe Kataloge

- `BLC_ExternalSystems`
- `BLC_ExternalAssets`
- `BLC_ExternalDevices`
- `BLC_ExternalLicenses`

Diese Listen enthalten synchronisierte Snapshots aus GovernancePortal, Microsoft Graph oder Intune. Sie sind nicht führend.

## GovernancePortal-Abgrenzung

### GovernancePortal führt

- Systeme und Anwendungen
- Services
- Assets und Geräte
- Hersteller und Modelle
- technische Owner
- Kritikalität, Risiken und Controls

### BenutzerLifeCycle führt

- Personen und Beschäftigungen
- Lifecycle-Vorgänge
- Rollenprofile
- Berechtigungssoll
- Aufgaben und Nachweise
- Benutzerbezogene Asset-Zuordnungen

Keine direkten Cross-Site-Lookups. Austausch über stabile technische IDs und synchronisierte lokale Kataloge.

## Empfohlene Umsetzung

1. Provisioning 2.0 deklarativ neu erstellen.
2. Bestehende `BL_*`-Listen als veraltet markieren und anschließend entfernen.
3. Bestehende `BLC_*`-Listen nur dort weiterverwenden, wo interne Namen und Semantik bereits zum Zielmodell passen.
4. `BLC_Employees` vor Produktivstart durch `BLC_Persons` und `BLC_Employments` ersetzen.
5. Katalog, Task-Vorlage, Zuweisungsregel und SLA aus `BLC_Entitlements` herauslösen.
6. technische IDs, Indizes und eindeutige Constraints definieren.
7. Canvas App und Flows auf das neue Schema umstellen.
8. erst danach initialen Benutzerimport ausführen.

## Nächste Arbeitspakete

- detaillierte Feldmatrix `Keep / Rename / Replace / Remove`
- deklarative Schema-Datei für Provisioning 2.0
- idempotente Apply-, Validate-, DryRun- und Reset-Skripte
- kontrollierter Greenfield-Reset
- Initialimport der vorhandenen Benutzer
