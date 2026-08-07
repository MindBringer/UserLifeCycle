# Role Engine 2.0

## Ziel

Die Role Engine trennt fachliche Rollen, technische Berechtigungen und beobachteten Istzustand. Lifecycle-Prozesse erzeugen damit keine hart codierten Berechtigungen, sondern berechnen Sollzuweisungen aus katalogisierten Regeln.

## Kernmodell

```text
BLC_RoleProfiles
  -> BLC_RoleEntitlements
      -> BLC_Entitlements

BLC_Employments
  -> BLC_UserRoleAssignments
      -> BLC_UserEntitlementAssignments   (Soll)
      -> BLC_ObservedEntitlements          (Ist)
      -> BLC_EntitlementExceptions         (genehmigte Abweichung)
```

## Rollenprofile

`BLC_RoleProfiles` ist ein fachlicher Katalog. Ein Rollenprofil besitzt einen stabilen `TechnicalKey`, Version, Aktivstatus und Risikoklasse. Rollenprofile dürfen keine providerspezifischen IDs als Primärschlüssel verwenden.

## Entitlements

`BLC_Entitlements` beschreibt das kleinste verwaltete Berechtigungsobjekt, zum Beispiel:

- Entra-/AD-Gruppe
- Microsoft-365-Lizenz
- Anwendungsrolle
- Mailbox-Berechtigung
- VPN
- Telefonie
- SharePoint-Berechtigung

`TargetSystemKey` referenziert perspektivisch den synchronisierten Systemkatalog aus dem GovernancePortal. Bis dahin bleibt der technische Schlüssel providerneutral.

## Soll und Ist

`BLC_UserEntitlementAssignments` ist das berechnete Soll. `BLC_ObservedEntitlements` wird später durch Provider wie Microsoft Graph, Entra ID, Intune oder Fachsysteme befüllt. Beide Strukturen bleiben getrennt, damit Abweichungen explizit ausgewertet werden können.

## Exceptions

`BLC_EntitlementExceptions` bildet genehmigte Abweichungen vom Soll ab. Ausnahmen besitzen Begründung, Genehmiger, Gültigkeitszeitraum und Status. Eine Ausnahme verändert das Rollenprofil nicht.

## Task Templates, Assignment Rules und SLA

Die Role Engine nutzt die Lifecycle-Basis:

- `BLC_TaskTemplates`: wiederverwendbare Aufgaben
- `BLC_AssignmentRules`: bedingte Auswahl von Rollenprofilen oder Tasks
- `BLC_SLAProfiles`: Fälligkeit, Reminder und Eskalation

Assignment Rules können Organisation, Abteilung, Standort und Position berücksichtigen. Die spätere Lifecycle Engine wertet sie deterministisch nach Priorität aus.

## Datenhoheit

UserLifeCycle führt:

- Rollenprofile
- Entitlement-Soll
- Benutzerbezogene Rollen-/Entitlement-Zuordnung
- genehmigte Ausnahmen

GovernancePortal führt perspektivisch:

- Systeme
- Anwendungen
- Assets und Geräte
- technische Owner und Kritikalität

Die Kopplung erfolgt über stabile technische Schlüssel bzw. externe IDs, nicht über Cross-Site-Lookups.

## Seeds

PR2 legt keine firmenspezifischen Rollen, Berechtigungen oder SLA-Werte fest. Solche Daten sind Konfiguration und werden erst anhand realer Organisations- und Berechtigungsdaten als deklarative Seed-Sets ergänzt.
