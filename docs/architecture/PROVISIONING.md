# Provisioning 2.0

## Ziel

Das modulare Schema unter `schema/` ist die einzige Quelle der Wahrheit für SharePoint-Listen und Felder. Direkte, dauerhaft gepflegte `Add-PnP*`-Aufrufe werden vermieden.

## Ablauf

```text
schema/modules/*.json
  -> Provisioning/Compile-Schema.ps1
  -> generated/schema/compiled-schema.json
  -> Provisioning/Invoke-Provisioning.ps1
  -> DryRun | Apply | Validate
  -> generated/provisioning/*.json|csv|html
```

## Betriebsmodi

### DryRun

Liest die Zielsite und erzeugt einen Plan. Es werden keine Änderungen geschrieben.

```powershell
pwsh ./Provisioning/Invoke-ProvisioningLocal.ps1 -Mode DryRun
```

### Apply

Legt ausschließlich fehlende Listen und Felder an. Bereits vorhandene Felder mit abweichendem Typ, Index, Unique-Constraint oder Choice-Satz werden nicht automatisch geändert, sondern als `DIFFERENCE` protokolliert.

```powershell
pwsh ./Provisioning/Invoke-ProvisioningLocal.ps1 -Mode Apply
```

### Validate

Prüft die Zielsite gegen das kompilierte Schema. Bei Abweichungen endet das Skript mit Exitcode `2`.

```powershell
pwsh ./Provisioning/Invoke-ProvisioningLocal.ps1 -Mode Validate
```

## Lokale Konfiguration

```powershell
Copy-Item ./Provisioning/settings.example.psd1 ./Provisioning/settings.local.psd1
```

Danach `SiteUrl`, `ClientId` und optional `AuthenticationMode` eintragen. `settings.local.psd1` ist ignoriert und darf nicht committet werden.

## Sicherheitsregeln

- kein Löschen von Listen oder Feldern in Epic 1.2 Teilpaket 2
- keine automatische Typkonvertierung bestehender Felder
- keine automatische Änderung von Lookups
- Apply ist additiv und idempotent
- Reset und Seed folgen in einem separaten Teilpaket mit Confirmation Token
- jeder Lauf erzeugt JSON-, CSV- und HTML-Protokolle

## Reihenfolge

1. alle Listen anlegen
2. Felder anlegen; Lookup-Felder erst, nachdem alle Ziellisten existieren
3. bestehende Felder gegen Typ, Required, Indexed, Unique und Choices vergleichen
4. Abweichungen reporten
5. Validate als Release- und Abnahme-Gate verwenden

## Aktuelle Grenze

Views, Berechtigungen, Seed-Daten, Lösch-/Reset-Operationen und kontrollierte Änderungen bestehender Felder sind noch nicht Bestandteil dieses Teilpakets.
