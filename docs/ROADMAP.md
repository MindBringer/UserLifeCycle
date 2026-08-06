# UserLifeCycle 2.0 Roadmap

Stand: 2026-08-06

## Phase A – Entwicklungsplattform

- [x] Epic 0 – Developer Baseline
- [x] Epic 1.1 – Schema Analyzer und Referenzmatrix
- [ ] Epic 1.2 – Deklaratives Provisioning 2.0
  - [x] Schema Foundation: modulare Schemadateien, Compiler, Report
  - [x] Provisioning Generator: additiver Apply, Dry Run, Validate und Laufberichte
  - [ ] Vollständige Felddefinitionen und kontrollierte Schemaänderungen
  - [ ] Reset und Seed mit Confirmation Token
  - [ ] Migration Assessment und Impact Analyzer

## Phase B – Datenmodell 2.0

- [ ] Epic 1.3 – Personen- und Beschäftigungsmodell
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
2. Das kompilierte Schema ist die einzige Quelle der Wahrheit.
3. Personen und Beschäftigungen sind getrennt modelliert.
4. Provisioning ist idempotent und besitzt Dry Run, Validate und Reset.
5. Canvas und Flows referenzieren ausschließlich das 2.0-Schema.
6. Erst danach erfolgt der initiale Benutzerimport.
