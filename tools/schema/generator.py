#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_list(item: dict, source: str) -> None:
    for key in ("internalName", "displayName"):
        if not item.get(key):
            raise ValueError(f"{source}: Liste ohne {key}")
    if not item["internalName"].startswith("BLC_"):
        raise ValueError(f"{source}: Ungültiges Präfix: {item['internalName']}")
    field_names: set[str] = set()
    for field in item.get("fields", []):
        name = field.get("internalName")
        if not name or not field.get("displayName") or not field.get("type"):
            raise ValueError(f"{source}/{item['internalName']}: unvollständiges Feld")
        if name in field_names:
            raise ValueError(f"{source}/{item['internalName']}: doppeltes Feld {name}")
        field_names.add(name)


def compile_schema(schema_dir: Path) -> dict:
    manifest = load_json(schema_dir / "manifest.json")
    modules: list[dict] = []
    seen_lists: set[str] = set()

    for relative_path in manifest["modules"]:
        module_path = schema_dir / relative_path
        module = load_json(module_path)
        module["sourceFile"] = relative_path
        modules.append(module)

    modules.sort(key=lambda item: item.get("order", 999))
    lists: list[dict] = []
    for module in modules:
        for item in module.get("lists", []):
            validate_list(item, module["sourceFile"])
            name = item["internalName"]
            if name in seen_lists:
                raise ValueError(f"Liste mehrfach definiert: {name}")
            seen_lists.add(name)
            enriched = dict(item)
            enriched["module"] = module["module"]
            lists.append(enriched)

    return {
        "schemaVersion": manifest["schemaVersion"],
        "project": manifest["project"],
        "prefix": manifest["prefix"],
        "policies": manifest.get("policies", {}),
        "modules": [module["module"] for module in modules],
        "summary": {
            "moduleCount": len(modules),
            "listCount": len(lists),
            "fieldCount": sum(len(item.get("fields", [])) for item in lists),
        },
        "lists": lists,
    }


def write_report(schema: dict, destination: Path) -> None:
    rows = []
    for item in schema["lists"]:
        rows.append(
            "<tr>"
            f"<td>{item['module']}</td>"
            f"<td><code>{item['internalName']}</code></td>"
            f"<td>{item['displayName']}</td>"
            f"<td>{item.get('mode', 'create')}</td>"
            f"<td>{len(item.get('fields', []))}</td>"
            "</tr>"
        )
    html = f"""<!doctype html><html lang='de'><head><meta charset='utf-8'>
<title>UserLifeCycle Schema {schema['schemaVersion']}</title>
<style>body{{font-family:system-ui;margin:2rem;color:#172033}}table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #d7deea;padding:.55rem;text-align:left}}th{{background:#eef2f7}}code{{background:#eef2f7;padding:.1rem .25rem}}</style></head><body>
<h1>UserLifeCycle Schema {schema['schemaVersion']}</h1>
<p>{schema['summary']['moduleCount']} Module, {schema['summary']['listCount']} Listen, {schema['summary']['fieldCount']} explizite Felder.</p>
<table><thead><tr><th>Modul</th><th>Interner Name</th><th>Anzeige</th><th>Modus</th><th>Felder</th></tr></thead><tbody>{''.join(rows)}</tbody></table>
</body></html>"""
    destination.write_text(html, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Compile modular UserLifeCycle schema")
    parser.add_argument("--schema-dir", default=str(ROOT / "schema"))
    parser.add_argument("--output-dir", default=str(ROOT / "generated" / "schema"))
    args = parser.parse_args()

    schema_dir = Path(args.schema_dir).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    schema = compile_schema(schema_dir)
    compiled_path = output_dir / "compiled-schema.json"
    report_path = output_dir / "schema-report.html"
    compiled_path.write_text(json.dumps(schema, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_report(schema, report_path)
    print(f"SCHEMA COMPILE: OK · {schema['summary']['listCount']} Listen · {compiled_path}")
    print(f"SCHEMA REPORT: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
