# Canvas Foundation

## Ziel

Die bestehende Canvas-App wird von der historischen Mitarbeiterentität auf das kanonische 2.0-Domänenmodell umgestellt.

Zielquellen:

- `BLC_Persons` für personenbezogene Stammdaten
- `BLC_Employments` für Beschäftigungs-, Organisations- und Rollenbezug

`BLC_Employees` ist kein zulässiger Zielbestand mehr.

## Migrationsprinzip

Die Umstellung erfolgt referenzbasiert und nicht als globale Textersetzung. Eine direkte Ersetzung `BLC_Employees -> BLC_Employments` wäre fachlich falsch, weil Personenattribute und Beschäftigungsattribute getrennt modelliert sind.

Vor jeder Änderung wird `tools/canvas/impact.py` ausgeführt. Der Report zeigt direkte Legacy-Referenzen, `cmbEmployee`-Verwendungen sowie bereits vorhandene Persons-/Employments-Verweise.

## Ziel für Mitarbeiter-Auswahl

Mover und Offboarding wählen künftig eine Beschäftigung, nicht einen losgelösten Personendatensatz. Die Anzeige wird aus `Employment -> Person` aufgebaut. Der fachliche Schlüssel für Folgeprozesse ist `EmploymentID`; `PersonID` bleibt der dauerhafte Personenbezug.

## Onboarding

Onboarding erfasst weiterhin die für den Vorgang erforderlichen Personendaten. Die tatsächliche Materialisierung in `BLC_Persons` und `BLC_Employments` erfolgt kontrolliert über den neuen Schreibpfad im Lifecycle-/Flow-Refactoring. Damit entstehen keine parallelen Schreibpfade zur bestehenden produktiven Logik.

## Release-Gates

1. Impact-Report ist reproduzierbar.
2. Direkte `BLC_Employees`-Referenzen sind vollständig bekannt.
3. Neue Canvas-Änderungen verwenden `BLC_Persons` und `BLC_Employments`.
4. Vor Entfernung von `BLC_Employees` müssen Canvas und Flows 0 direkte Referenzen melden.
5. Build und Solution-Validate bleiben grün.
