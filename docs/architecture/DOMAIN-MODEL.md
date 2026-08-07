# Domain Model 2.0

Stand: 2026-08-07

## Ziel

UserLifeCycle trennt dauerhaftes Personenobjekt, Beschäftigungsverhältnis und organisatorische Stammdaten. Lifecycle-Vorgänge referenzieren künftig ein Beschäftigungsverhältnis statt einer flachen Mitarbeiterzeile.

## Kernmodell

```text
BLC_Persons
    1
    |
    n
BLC_Employments
    |-- Organization -> BLC_Organizations
    |-- Department   -> BLC_Departments
    |-- Location     -> BLC_Locations
    |-- CostCenter   -> BLC_CostCenters
    |-- Position     -> BLC_Positions
    `-- RoleProfile  -> BLC_RoleProfiles
```

## Personen

`BLC_Persons` beschreibt eine Person unabhängig von einem einzelnen Arbeitsverhältnis.

Stabiler Schlüssel: `PersonID`.

Externe Identitäten wie Personalnummer, Entra Object ID, UPN oder E-Mail sind Attribute und dürfen nicht als alleiniger Primärschlüssel verwendet werden. Sie können sich ändern oder zeitweise fehlen.

Das Modell unterstützt damit unter anderem:

- Wiedereintritt derselben Person,
- mehrere Beschäftigungsverhältnisse,
- externe Personen und Dienstleister,
- spätere Verknüpfung mehrerer technischer Accounts,
- Import aus CSV, Entra ID oder HR-Systemen.

## Beschäftigungen

`BLC_Employments` enthält den zeitlich veränderlichen organisatorischen Kontext einer Person.

Stabiler Schlüssel: `EmploymentID`.

Eine Beschäftigung enthält insbesondere Arbeitgeber/Organisation, Abteilung, Standort, Kostenstelle, Position, Rollenprofil, Manager, Beschäftigungsart, Start-/Enddatum und Status.

Lifecycle-Vorgänge werden nach dem Canvas-/Flow-Refactoring auf `EmploymentID` bzw. den Lookup `Employment` ausgerichtet.

## Organisationskataloge

Die folgenden Listen sind versionierbare Stammdatenkataloge:

- `BLC_Organizations`
- `BLC_Departments`
- `BLC_Locations`
- `BLC_CostCenters`
- `BLC_Positions`

Jeder Katalog besitzt einen verpflichtenden, eindeutigen und indizierten `TechnicalKey`. Anzeigenamen sind nicht identitätsstiftend und dürfen geändert werden.

`BLC_Organizations` ist bewusst die einzige Arbeitgeber-/Gesellschaftsebene. Eine zusätzliche `Companies`-Liste wird nicht eingeführt, da sie dieselbe fachliche Entität duplizieren würde.

## Datenhoheit

UserLifeCycle ist führend für:

- Personen,
- Beschäftigungsverhältnisse,
- Rollen- und Berechtigungssoll,
- Lifecycle-Vorgänge und Aufgaben.

GovernancePortal bleibt perspektivisch führend für Systeme und Assets. Geräte oder andere Assets werden daher nicht in diesem Domain-Schema als eigenes Inventar dupliziert.

Organisations- und Personendaten können später von externen Providern synchronisiert werden. `SourceSystem`, `ExternalSourceID`, `SourceModifiedAt` und `LastImportDate` schaffen dafür die technische Grundlage.

## Importregeln

Der erste Benutzerimport erfolgt erst nach dem Canvas-/Flow-Refactoring. Provider schreiben in das gleiche kanonische Modell:

```text
CSV / HR / Entra ID
        |
        v
Mapping + Upsert
        |
        +--> BLC_Persons
        `--> BLC_Employments
```

Eine Quelle darf Personen nicht allein anhand von UPN oder E-Mail dauerhaft identifizieren. Matching- und Konfliktregeln werden in Epic 2.0 definiert.

## Schema-Invarianten

Der Schema-Compiler erzwingt ab PR1:

- Kataloge besitzen `TechnicalKey` mit `required=true`, `indexed=true`, `unique=true`.
- Entitäten besitzen ein deklaratives `stableIdField`, ebenfalls required/indexed/unique.
- Lookup-Ziellisten existieren im kompilierten Schema.
- Lookup-Zielfelder existieren oder sind eingebaute SharePoint-Felder wie `Title`.
- `BL_*` ist weiterhin unzulässig.

Diese Prüfungen laufen vor Provisioning und Build und verhindern strukturell inkonsistente Schemaänderungen.

## Noch nicht Bestandteil von PR1

- Migration oder Refactoring der aktuellen Canvas-App,
- Änderung bestehender Lifecycle-Flows,
- konkrete Organisations-Seed-Daten,
- Rollen-/Entitlement-Regelwerk,
- Benutzerimport,
- Microsoft Graph oder Intune.

Diese Punkte folgen in den nächsten PRs der Roadmap.
