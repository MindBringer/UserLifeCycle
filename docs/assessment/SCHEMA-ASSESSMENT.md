# BenutzerLifeCycle 2.0 – Schema Assessment

Stand: 2026-08-05

## Bewertungsgrundlage

Für die weitere Architektur und Entwicklung gelten ausschließlich:

- die aktuellen Listen mit Präfix `BLC_`
- die aktuelle Canvas-App im `SourceCode`-Layout
- die aktuellen Power-Automate-Flows
- das definierte Zielbild für BenutzerLifeCycle 2.0

Alle Listen mit Präfix `BL_` sind Altbestand. Sie werden nicht migriert, nicht weiterverwendet und nicht als Kompatibilitätsanforderung berücksichtigt. Da keine Echtdaten vorhanden sind, können sie im kontrollierten Reset entfernt werden.

## Aktueller fachlicher Ausgangsstand

- `BLC_EmployeeIdentityChanges`
- `BLC_EmployeeRoles`
- `BLC_Employees`
- `BLC_Entitlements`
- `BLC_LifecycleRequests`
- `BLC_LifecycleTasks`
- `BLC_RoleEntitlements`
- `BLC_RoleProfiles`

## Wesentliche Befunde im aktuellen BLC-Modell

### 1. Personenmodell

`BLC_Employees` bildet Person, Beschäftigung und Konto in einem Datensatz ab. Das ist für die aktuelle App ausreichend, aber für das Zielbild zu eng.

Nicht sauber unterstützt werden:

- Wiedereintritt
- mehrere Beschäftigungsverhältnisse
- Gesellschafts- oder Standortwechsel mit Historie
- externe Personen
- mehrere Benutzerkonten
- stabile Identität bei Änderung von UPN oder E-Mail

Empfohlenes Zielmodell:

- `BLC_Persons`
- `BLC_Employments`
- perspektivisch `BLC_Accounts`

Lifecycle-Vorgänge referenzieren das Beschäftigungsverhältnis. UPN und E-Mail bleiben veränderliche Attribute und keine Primärschlüssel.

### 2. Entitlement-Modell

`BLC_Entitlements` enthält derzeit mehrere Verantwortlichkeiten gleichzeitig:

- Berechtigungskatalog
- technische Systemreferenz
- Joiner-/Mover-/Leaver-Relevanz
- Aufgabentitel und -beschreibung
- Fälligkeits-Offsets
- Zuweisungslogik
- Owner-Gruppe
- Nachweisanforderungen

Diese Struktur funktioniert für den aktuellen Entwicklungsstand, wird aber mit zusätzlichen Prozessvarianten und Zielsystemen schwer wartbar.

Empfohlene Trennung:

- `BLC_Entitlements` – fachlicher Berechtigungs- und Leistungskatalog
- `BLC_TaskTemplates` – Aufgabenvorlagen je Vorgangsart
- `BLC_AssignmentRules` – Zuständigkeitsauflösung
- `BLC_SLAProfiles` – Fristen, Erinnerungen und Eskalationen

### 3. Rollenmodell

Die vorhandenen Listen bleiben konzeptionell Bestandteil des Zielbilds:

- `BLC_RoleProfiles`
- `BLC_RoleEntitlements`
- `BLC_EmployeeRoles`

Vor Produktivstart sind jedoch stabile technische Schlüssel und klare Gültigkeiten erforderlich. Empfohlen sind:

- `RoleProfileKey`
- `EntitlementKey`
- `ValidFrom`
- `ValidTo`
- `AssignmentStatus`
- `Source`

`BLC_EmployeeRoles` sollte perspektivisch auf `BLC_Employments` referenzieren und in `BLC_UserRoleAssignments` überführt werden.

### 4. Lifecycle-Modell

`BLC_LifecycleRequests` und `BLC_LifecycleTasks` sind die richtige fachliche Basis und bleiben erhalten.

Vor Produktivstart sollten ergänzt beziehungsweise vereinheitlicht werden:

- stabiler Vorgangsschlüssel
- Referenz auf `EmploymentID`
- konsistentes Statusmodell
- Priorität und Kritikalität
- Fälligkeit, SLA und Eskalation
- Korrelations-ID für Flow-Läufe
- Abschlussgrund und Abbruchgrund
- Snapshot-Felder für historische Nachvollziehbarkeit

Empfohlenes Vorgangsstatusmodell:

- `Draft`
- `Submitted`
- `Approved`
- `InProgress`
- `WaitingForInput`
- `Blocked`
- `Completed`
- `Cancelled`
- `Archived`

Empfohlenes Aufgabenstatusmodell:

- `Open`
- `Assigned`
- `InProgress`
- `WaitingForInput`
- `Blocked`
- `Completed`
- `Skipped`
- `Cancelled`
- `Failed`

### 5. Technische Schlüssel und Indizes

Vor Import und Produktivbetrieb müssen eindeutige technische Schlüssel definiert und indiziert werden.

Mindestens erforderlich:

- `PersonID`
- `EmploymentID`
- `LifecycleRequestID`
- `LifecycleTaskID`
- `RoleProfileKey`
- `EntitlementKey`
- `EntraObjectID`
- `EmployeeNumber`
- `ExternalSourceID`

UPN, E-Mail und Anzeigename dürfen nicht als dauerhafte Identität verwendet werden.

### 6. Audit

SharePoint-Versionierung bleibt aktiviert, reicht aber für fachliche Prüfungen nicht aus.

Empfohlen:

- `BLC_AuditEvents`

Felder:

- `EventID`
- `EntityType`
- `EntityID`
- `EventType`
- `Timestamp`
- `Actor`
- `Source`
- `CorrelationID`
- `OldValue`
- `NewValue`

### 7. Import und Synchronisation

Der initiale Benutzerimport erfolgt erst nach dem Zielschema.

Erforderliche Listen:

- `BLC_ImportRuns`
- `BLC_ImportErrors`
- später `BLC_SyncRuns`
- später `BLC_SyncErrors`

Der Import muss als wiederholbarer Upsert arbeiten und mindestens anhand von `EntraObjectID`, `EmployeeNumber` und `ExternalSourceID` abgleichen können.

## Zielmodell vor Produktivstart

### Personen und Organisation

- `BLC_Persons`
- `BLC_Employments`
- optional später `BLC_Accounts`
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
- später `BLC_ObservedEntitlements`
- später `BLC_EntitlementExceptions`

### Import und Synchronisation

- `BLC_ImportRuns`
- `BLC_ImportErrors`
- später `BLC_SyncRuns`
- später `BLC_SyncErrors`

### Externe Kataloge

- `BLC_ExternalSystems`
- `BLC_ExternalAssets`
- `BLC_ExternalDevices`
- `BLC_ExternalLicenses`

Diese Listen enthalten synchronisierte Snapshots aus GovernancePortal, Microsoft Graph oder Intune und sind im BenutzerLifeCycle nicht führend.

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
- benutzerbezogene Asset-Zuordnungen

Keine direkten Cross-Site-Lookups. Der Austausch erfolgt über stabile technische IDs und synchronisierte lokale Kataloge.

## Bereinigungsstrategie

Da keine Echtdaten vorhanden sind:

1. Alle `BL_*`-Listen im Reset explizit als Altbestand erkennen und entfernen.
2. Das aktuelle `BLC_*`-Schema gegen Canvas-App und Flows referenzieren.
3. Das Zielmodell deklarativ provisionieren.
4. Nicht mehr benötigte `BLC_*`-Felder erst nach erfolgreicher Umstellung von Canvas und Flows entfernen.
5. Canvas-App und Flows auf das neue Schema anpassen.
6. Schema validieren.
7. Erst danach initialen Benutzerimport durchführen.

## Nächste Arbeitspakete

1. Feldmatrix für alle aktuellen `BLC_*`-Listen: `Keep / Extend / Replace / Remove`.
2. Referenzmatrix aus Canvas-App und Flows.
3. Deklarative Schema-Datei für Provisioning 2.0.
4. Idempotente Skripte für `DryRun`, `Apply`, `Validate` und `Reset`.
5. Kontrollierter Greenfield-Reset einschließlich Entfernung aller `BL_*`-Listen.
6. Anpassung von Canvas-App und Flows.
7. Initialer Benutzerimport.
