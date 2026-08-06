# UserLifeCycle 2.0 Roadmap

Stand: 2026-08-06

## Phase A – Entwicklungsplattform

- [x] Epic 0 – Developer Baseline
- [x] Epic 1.1 – Schema Analyzer und Referenzmatrix
- [ ] Epic 1.2 – Deklaratives Provisioning 2.0
  - [x] Schema Foundation: modulare Schemadateien, Compiler, Report
  - [x] Provisioning Generator: additiver Apply, Dry Run, Validate und Laufberichte
  - [x] Kontrollierter Greenfield-Reset mit Site-Gate, Policy und Confirmation Token
  - [x] Generische Seed-Infrastruktur mit Dry Run, Apply, Validate und Reports
  - [ ] Migration Assessment und Impact Analyzer
  - [ ] Abschlussdokumentation und Release

## Phase B – Datenmodell 2.0

- [ ] Epic 1.3 – Personen- und Beschäftigungsmodell
  - vollständige Felddefinitionen für Personen, Beschäftigungen und Organisationskataloge
  - initiale Import- und Synchronisationsschlüssel
  - fachliche Seed-Sets für Organisation, Standort, Abteilung und Position
- [ ] Epic 1.4 – Task Templates, Assignment Rules, SLA und Audit
- [ ] Epic 1.5 – Canvas- und Flow-Refactoring

## Phase C – Betriebsfunktionen

- [ ] Epic 2.0 – Initialer Benutzerimport (CSV, danach Entra ID)
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
6. Canvas und Flows referenzieren ausschließlich das 2.0-Schema.
7. Erst danach erfolgt der initiale Benutzerimport.
