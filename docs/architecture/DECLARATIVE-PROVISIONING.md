# Deklaratives Provisioning 2.0

## Entscheidung

Die Dateien unter `schema/` sind die einzige fachliche Quelle für Listen, Felder, Choices, Lookups, Indizes und Views. Generierte Dateien werden nicht manuell bearbeitet.

## Struktur

```text
schema/
├── manifest.json
└── modules/
    ├── identity.json
    ├── lifecycle.json
    ├── access.json
    └── integration.json
```

Der Compiler erzeugt unter `generated/schema/`:

- `compiled-schema.json`
- `schema-report.html`

## Regeln

- Fachliche Listen verwenden ausschließlich das Präfix `BLC_`.
- Interne Namen sind nach erstmaligem Provisioning unveränderlich.
- Kataloge erhalten einen eindeutigen `TechnicalKey`.
- Kernentitäten erhalten eine stabile fachliche ID.
- UPN, E-Mail und Anzeigename sind keine Primärschlüssel.
- Lookups referenzieren interne Listennamen, nicht Anzeigenamen.
- `BL_*` wird nicht unterstützt und im Greenfield-Reset entfernt.
- Das Zielsystem wird in Modulen beschrieben; die Reihenfolge wird über `order` festgelegt.

## Build-Kette

```text
schema/modules/*.json
        ↓
tools/schema/generator.py
        ↓
generated/schema/compiled-schema.json
        ↓
Provisioning Generator (Epic 1.2, Teil 2)
        ↓
Dry Run / Apply / Validate / Reset / Report
```

## Aktueller Stand

Die Schema Foundation kompiliert und validiert:

- eindeutige Listennamen
- gültiges `BLC_`-Präfix
- vollständige Felddefinitionen
- eindeutige interne Feldnamen je Liste
- deterministische Modulreihenfolge

Die konkreten Felddefinitionen werden in den folgenden Teilpaketen aus der geprüften Referenzmatrix vervollständigt.
