#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from collections import Counter
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "powerplatform" / "canvas-src" / "gp_blcroleentitlementmanager" / "Src"
OUT = ROOT / "generated" / "canvas-impact"

PATTERNS = {
    "legacy_employees": re.compile(r"\bBLC_Employees\b"),
    "persons": re.compile(r"\bBLC_Persons\b"),
    "employments": re.compile(r"\bBLC_Employments\b"),
    "cmb_employee": re.compile(r"\bcmbEmployee\b"),
    "lifecycle_requests": re.compile(r"\bBLC_LifecycleRequests\b"),
    "lifecycle_tasks": re.compile(r"\bBLC_LifecycleTasks\b"),
}


def snippets(text: str, pattern: re.Pattern[str], radius: int = 90) -> list[str]:
    result: list[str] = []
    for match in pattern.finditer(text):
        start = max(0, match.start() - radius)
        end = min(len(text), match.end() + radius)
        snippet = " ".join(text[start:end].replace("\r", " ").replace("\n", " ").split())
        result.append(snippet)
    return result


def main() -> int:
    if not SRC.exists():
        raise SystemExit(f"Canvas source fehlt: {SRC}")

    rows: list[dict] = []
    totals: Counter[str] = Counter()
    legacy_hits: list[dict] = []

    for path in sorted(SRC.glob("*.pa.yaml")):
        text = path.read_text(encoding="utf-8")
        counts = {name: len(pattern.findall(text)) for name, pattern in PATTERNS.items()}
        totals.update(counts)
        rows.append({"file": path.name, **counts})
        for snippet in snippets(text, PATTERNS["legacy_employees"]):
            legacy_hits.append({"file": path.name, "snippet": snippet})

    payload = {
        "source": str(SRC.relative_to(ROOT)),
        "summary": dict(totals),
        "files": rows,
        "legacyEmployeeReferences": legacy_hits,
        "target": {
            "personSource": "BLC_Persons",
            "employmentSource": "BLC_Employments",
            "legacySource": "BLC_Employees",
        },
    }

    OUT.mkdir(parents=True, exist_ok=True)
    json_path = OUT / "canvas-impact.json"
    html_path = OUT / "canvas-impact.html"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    table_rows = "".join(
        "<tr>"
        f"<td>{escape(row['file'])}</td>"
        f"<td>{row['legacy_employees']}</td>"
        f"<td>{row['persons']}</td>"
        f"<td>{row['employments']}</td>"
        f"<td>{row['cmb_employee']}</td>"
        "</tr>"
        for row in rows
        if any(row[key] for key in ("legacy_employees", "persons", "employments", "cmb_employee"))
    )
    hit_rows = "".join(
        f"<tr><td>{escape(hit['file'])}</td><td><code>{escape(hit['snippet'])}</code></td></tr>"
        for hit in legacy_hits
    ) or "<tr><td colspan='2'>Keine direkten BLC_Employees-Referenzen gefunden.</td></tr>"

    html_path.write_text(
        "<!doctype html><html lang='de'><head><meta charset='utf-8'><title>Canvas Impact</title>"
        "<style>body{font-family:system-ui;margin:2rem;color:#172033}table{border-collapse:collapse;width:100%;margin-bottom:2rem}"
        "th,td{border:1px solid #d7deea;padding:.55rem;text-align:left;vertical-align:top}th{background:#eef2f7}"
        "code{white-space:pre-wrap;word-break:break-word}</style></head><body>"
        "<h1>Canvas Foundation – Impact</h1>"
        f"<p><strong>BLC_Employees:</strong> {totals['legacy_employees']} · "
        f"<strong>BLC_Persons:</strong> {totals['persons']} · "
        f"<strong>BLC_Employments:</strong> {totals['employments']} · "
        f"<strong>cmbEmployee:</strong> {totals['cmb_employee']}</p>"
        "<h2>Dateien</h2><table><thead><tr><th>Datei</th><th>Employees</th><th>Persons</th><th>Employments</th><th>cmbEmployee</th></tr></thead>"
        f"<tbody>{table_rows}</tbody></table>"
        "<h2>Legacy-Treffer</h2><table><thead><tr><th>Datei</th><th>Kontext</th></tr></thead>"
        f"<tbody>{hit_rows}</tbody></table></body></html>",
        encoding="utf-8",
    )

    print(
        "CANVAS IMPACT: OK · "
        f"BLC_Employees={totals['legacy_employees']} · "
        f"BLC_Persons={totals['persons']} · "
        f"BLC_Employments={totals['employments']} · "
        f"cmbEmployee={totals['cmb_employee']}"
    )
    print(f"CANVAS IMPACT JSON: {json_path}")
    print(f"CANVAS IMPACT HTML: {html_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
