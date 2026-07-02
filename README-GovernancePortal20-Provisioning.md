# IT Governance Portal 2.0 – Greenfield Provisioning

Dieses Paket erstellt das neue SharePoint-basierte **IT Governance Portal 2.0** als Greenfield-Aufbau.

## Enthalten

- `Provision-GovernancePortal20.ps1`
  - Site Columns für gemeinsame Governance-Standardfelder
  - Content Types für Governance-Objekte
  - neue Kernlisten
  - neue Kataloglisten
  - Dokumentbibliotheken
  - Standard-Views
  - QuickLaunch-Navigation
  - optional Beispiel-Katalogdaten

## Architekturprinzipien

- `Title` ist die fachliche Bezeichnung.
- Keine zusätzlichen Namensdubletten wie `AssetName`, `RiskName`, `ControlName`.
- `GovernanceID` ist die eindeutige Fach-ID.
- Gemeinsame Felder werden über Site Columns und Content Types wiederverwendet.
- Fachspezifische Felder werden nur in den jeweils passenden Listen erstellt.
- Reviews bestehen aus Review-Feldern am Objekt plus Historienliste `Reviews`.

## Ausführung

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser

.\Provision-GovernancePortal20.ps1 `
  -SiteUrl "https://groupsteinicke.sharepoint.com/sites/GovernancePortal" `
  -Interactive
```

## Dry-Run

```powershell
.\Provision-GovernancePortal20.ps1 `
  -SiteUrl "https://groupsteinicke.sharepoint.com/sites/GovernancePortal" `
  -Interactive `
  -DryRun
```

## Mit Beispiel-Katalogdaten

```powershell
.\Provision-GovernancePortal20.ps1 `
  -SiteUrl "https://groupsteinicke.sharepoint.com/sites/GovernancePortal" `
  -Interactive `
  -ProvisionSampleCatalogData
```

## Nacharbeiten

1. Skript zuerst mit `-DryRun` prüfen.
2. Danach ohne `-DryRun` ausführen.
3. In SharePoint prüfen:
   - Listen vorhanden
   - Content Types aktiv
   - Views vorhanden
   - Navigation plausibel
4. Danach Power-Automate-Flows für Governance-ID-Vergabe und Reviews erstellen.
5. Danach Power Apps auf die Listen setzen.

## Hinweis

Das Skript ist idempotent gedacht und prüft vorhandene Felder, Listen und Views. Dennoch sollte es zunächst auf der frischen Zielseite oder in einer Testseite ausgeführt werden.
