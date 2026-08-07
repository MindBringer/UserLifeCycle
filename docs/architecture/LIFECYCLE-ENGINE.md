# Lifecycle Engine

Stand: 2026-08-07

## Ziel

Die Lifecycle Engine berechnet aus Vorgang, Beschäftigung, Rollen-/Berechtigungskatalog und Assignment Rules einen deterministischen Ausführungsplan. Der Plan ist zunächst bewusst eine reine Berechnung ohne direkte SharePoint-Schreiboperationen. Power Automate bzw. spätere Provider können den Plan materialisieren.

## Eingaben

- Lifecycle Request (`Onboarding`, `Mover`, `Offboarding`)
- Employment mit Organisation, Abteilung, Standort und Position
- aktuelles Berechtigungssoll
- Ziel-Rollenprofil
- genehmigte Ausnahmen
- RoleEntitlements
- AssignmentRules
- TaskTemplates
- SLAProfiles

## Ausgaben

- `EngineRunKey`
- ausgewählte Regeln
- Berechtigungsdelta `grant` / `revoke`
- deterministische Tasks mit `EngineTaskKey`
- Due-/Reminder-Zeitpunkte
- Audit-Korrelation

## Determinismus und Idempotenz

`EngineRunKey` und `EngineTaskKey` werden aus stabilen fachlichen Eingaben per SHA-256 abgeleitet. Wiederholte Verarbeitung desselben Vorgangs erzeugt daher dieselben Schlüssel. Damit kann die Materialisierung in SharePoint vorhandene Tasks erkennen und Updates statt Duplikate ausführen.

## Onboarding

Das Ziel-Rollenprofil wird auf Entitlements aufgelöst. Fehlende Sollberechtigungen werden als `Grant` geplant. Zusätzlich passende AssignmentRules erzeugen Prozessaufgaben.

## Mover

Es wird ausschließlich das Delta zwischen aktuellem Soll und Ziel-Rollenprofil geplant:

- neu erforderlich → `Grant`
- nicht mehr erforderlich → `Revoke`
- genehmigte Ausnahme → kein automatischer Revoke

Damit werden unveränderte Berechtigungen nicht erneut provisioniert.

## Offboarding

Alle aktuellen Sollberechtigungen werden als `Revoke` geplant. Ein Ziel-Rollenprofil ist nicht erforderlich. Später kann die Engine zusätzlich Provider-spezifische Account-/Geräteaktionen erzeugen.

## Assignment Rules

Regeln können auf folgende Beschäftigungsmerkmale filtern:

- Organization
- Department
- Location
- Position
- LifecycleType

Die Auswertung erfolgt deterministisch nach `Priority` absteigend und anschließend `TechnicalKey`. `StopProcessing` beendet die weitere Regelauswertung.

## SLA

Task Templates referenzieren ein SLA-Profil. Unterstützt werden Kalender- und Arbeitstage. Der Simulator berücksichtigt Montag bis Freitag als Arbeitstage; Feiertagskalender folgen in einer späteren Ausbaustufe.

## Materialisierung

PR3 implementiert bewusst zunächst die berechenbare Engine und ihre Datenfelder. Der nächste Integrationsschritt materialisiert den Plan über Flows/Provider in:

- `BLC_LifecycleTasks`
- `BLC_UserRoleAssignments`
- `BLC_UserEntitlementAssignments`
- `BLC_Escalations`
- `BLC_AuditEvents`

Diese Trennung hält Berechnungslogik testbar und verhindert, dass Power-Automate-Ausführungsdetails die fachliche Engine bestimmen.

## Tests

`python3 tools/lifecycle/selftest.py` prüft:

- Onboarding-Grant
- Mover-Deltas
- Mover-Ausnahmen
- vollständigen Offboarding-Revoke
- deterministische Run Keys

Der Selftest ist Bestandteil des Companion-Release-Gates.
