# UserLifeCycle 2.0 Roadmap

Stand: 2026-08-07

## Phase A – Entwicklungsplattform

- [x] Epic 0 – Developer Baseline
- [x] Epic 1.1 – Schema Analyzer und Referenzmatrix
- [x] Epic 1.2 – Deklaratives Provisioning 2.0
  - [x] Schema Foundation: modulare Schemadateien, Compiler und Report
  - [x] Provisioning Generator: additiver Apply, Dry Run, Validate und Laufberichte
  - [x] Kontrollierter Greenfield-Reset mit Site-Gate, Policy und Confirmation Token
  - [x] Generische Seed-Infrastruktur mit Dry Run, Apply, Validate und Reports
  - [x] Compiler-Gates als Basis für fachliche Schema-Invarianten

## Phase B – Datenmodell 2.0

- [ ] Epic 1.3 – Domain Model Foundation
  - [x] PR1 – Domain Schema
  - [x] PR2 – Role Engine
  - [x] PR3 – Lifecycle Engine
    - deterministische EngineRun-/EngineTask-Keys
    - Joiner-/Mover-/Leaver-Planung
    - Mover-Differenzberechnung und Ausnahmebehandlung
    - Offboarding-Entzug aller Sollberechtigungen
    - Task Templates, Assignment Rules und SLA-Fälligkeiten
    - Eskalations- und Auditfelder
    - lokale Engine-Simulation und Selftests
  - [ ] **PR4 – Canvas Foundation**
    - reproduzierbarer Canvas-Impact-Report
    - vollständige Ermittlung aller `BLC_Employees`-Referenzen
    - Zielzugriff auf `BLC_Persons` und `BLC_Employments`
    - Mover/Offboarding wählen künftig Beschäftigungen
    - kontrollierte Entfernung der `BLC_Employees`-Abhängigkeiten
- [ ] Epic 1.4 – Prozess- und Rollenmodell vervollständigen
- [ ] Epic 1.5 – Canvas-/Flow-Refactoring und Materialisierung der Lifecycle Engine

## Phase C – Betriebsfunktionen

- [ ] Epic 2.0 – Initialer Benutzerimport
  - CSV als erster Provider
  - danach Microsoft Graph / Entra ID
  - später HR-Provider
- [ ] Epic 2.1 – Dashboard und Aufgaben-Cockpit
- [ ] Epic 2.2 – Microsoft-365- und Intune-Synchronisation
- [ ] Epic 2.3 – GovernancePortal-Integration für Systeme, Assets und Geräte

## Phase D – Reifegrad

- [ ] Epic 3.0 – Soll-/Ist-Abgleich und Offboarding Assurance
- [ ] Epic 3.1 – Genehmigungen und Self Service
- [ ] Epic 3.2 – Reporting, Rezertifizierung und Compliance

## Release-Gates vor Produktivstart

1. Kein fachlicher Altbestand `BL_*` mehr.
2. `BLC_Employees` ist durch `BLC_Persons` und `BLC_Employments` ersetzt.
3. Das kompilierte Schema ist die einzige Quelle der Wahrheit.
4. Provisioning ist idempotent und besitzt Dry Run, Apply, Validate, Reset und Seed.
5. Personen und Beschäftigungen sind getrennt modelliert.
6. Organisationsstammdaten besitzen stabile technische Schlüssel.
7. Rollenprofile und Berechtigungen sind katalog- und regelbasiert modelliert.
8. Lifecycle-Pläne sind deterministisch und wiederholbar.
9. Canvas und Flows referenzieren ausschließlich das 2.0-Schema.
10. Erst danach erfolgt der initiale Benutzerimport.
