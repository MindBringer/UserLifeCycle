# Greenfield Reset und Seed

## Ziel

Epic 1.2 trennt drei Operationen strikt:

1. **Provisioning** legt fehlende Listen und Felder additiv an.
2. **Reset** entfernt ausschließlich explizit freigegebenen Altbestand.
3. **Seed** führt deklarative Stammdaten idempotent per Upsert ein.

## Reset-Policy

`Provisioning/reset-policy.json` ist die einzige Quelle für destruktive Ziele.

Aktuell vorgesehen:

- alle Listen mit Präfix `BL_`
- `BLC_Employees`, da diese Liste durch `BLC_Persons` und `BLC_Employments` ersetzt wird

Alle übrigen `BLC_*`-Listen sind standardmäßig geschützt. Der Reset ist zusätzlich auf den Site-Pfad `/sites/benutzerlifecycle` begrenzt.

## Reset-Ablauf

```powershell
pwsh ./Provisioning/Invoke-ResetLocal.ps1 -Mode DryRun
```

Der Dry Run erzeugt JSON-, CSV- und HTML-Berichte unter `generated/reset/` und gibt ein Site- und Schema-gebundenes Token aus:

```text
RESET|https://tenant.sharepoint.com/sites/benutzerlifecycle|2.0.0-draft
```

Erst dieses Token erlaubt den Apply-Lauf:

```powershell
pwsh ./Provisioning/Invoke-ResetLocal.ps1 `
  -Mode Apply `
  -ConfirmationToken 'RESET|https://...|2.0.0-draft'
```

## Seed-Modell

`schema/seed/manifest.json` definiert Seed-Sets. Jedes Set verweist auf:

- eine Zielliste
- ein stabiles Schlüsselfeld
- eine JSON-Datei mit Datensätzen

Beispiel:

```json
{
  "name": "organizations",
  "list": "BLC_Organizations",
  "keyField": "TechnicalKey",
  "file": "organizations.json"
}
```

Datendatei:

```json
[
  {
    "values": {
      "Title": "Muster GmbH",
      "TechnicalKey": "MUSTER"
    }
  }
]
```

Der Runner löscht keine Datensätze, die nicht mehr im Manifest stehen.

## Seed-Ablauf

```powershell
pwsh ./Provisioning/Invoke-SeedLocal.ps1 -Mode DryRun
pwsh ./Provisioning/Invoke-SeedLocal.ps1 -Mode Apply
pwsh ./Provisioning/Invoke-SeedLocal.ps1 -Mode Validate
```

Fachliche Seed-Sets werden erst zusammen mit den vollständigen Feldmodellen in Epic 1.3 und 1.4 ergänzt.

## Empfohlene Greenfield-Reihenfolge

```text
Reset Dry Run
→ Reset Apply
→ Provisioning Apply
→ Provisioning Validate
→ Seed Apply
→ Seed Validate
→ Canvas-/Flow-Refactoring
```
