#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILTIN_FIELDS = {"Title", "ID", "Created", "Modified", "Author", "Editor"}


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def field_map(item: dict) -> dict[str, dict]:
    return {field["internalName"]: field for field in item.get("fields", [])}


def normalize_field(field: dict) -> dict:
    normalized = dict(field)
    normalized.setdefault("required", False)
    normalized.setdefault("indexed", False)
    normalized.setdefault("unique", False)
    normalized.setdefault("choices", [])
    if normalized.get("type") in {"Lookup", "LookupMulti"}:
        normalized.setdefault("lookupField", "Title")
    return normalized


def validate_list(item: dict, source: str, policies: dict) -> None:
    for key in ("internalName", "displayName"):
        if not item.get(key):
            raise ValueError(f"{source}: Liste ohne {key}")
    if not item["internalName"].startswith("BLC_"):
        raise ValueError(f"{source}: Ungültiges Präfix: {item['internalName']}")

    fields: dict[str, dict] = {}
    for raw_field in item.get("fields", []):
        field = normalize_field(raw_field)
        name = field.get("internalName")
        if not name or not field.get("displayName") or not field.get("type"):
            raise ValueError(f"{source}/{item['internalName']}: unvollständiges Feld")
        if name in fields:
            raise ValueError(f"{source}/{item['internalName']}: doppeltes Feld {name}")
        fields[name] = field

    if policies.get("requireTechnicalKeyForCatalogs") and item.get("catalog"):
        technical_key = fields.get("TechnicalKey")
        if not technical_key:
            raise ValueError(f"{source}/{item['internalName']}: Katalog ohne TechnicalKey")
        if not technical_key.get("required") or not technical_key.get("indexed") or not technical_key.get("unique"):
            raise ValueError(
                f"{source}/{item['internalName']}: TechnicalKey muss required, indexed und unique sein"
            )

    if policies.get("requireStableIdForEntities") and item.get("entity"):
        stable_id_name = item.get("stableIdField")
        stable_id = fields.get(stable_id_name) if stable_id_name else None
        if not stable_id:
            raise ValueError(f"{source}/{item['internalName']}: Entität ohne gültiges stableIdField")
        if not stable_id.get("required") or not stable_id.get("indexed") or not stable_id.get("unique"):
            raise ValueError(
                f"{source}/{item['internalName']}: {stable_id_name} muss required, indexed und unique sein"
            )


def validate_lookups(lists: list[dict], policies: dict) -> None:
    if not policies.get("validateLookupTargets"):
        return

    by_name = {item["internalName"]: item for item in lists}
    for item in lists:
        for field in item.get("fields", []):
            if field.get("type") not in {"Lookup", "LookupMulti"}:
                continue
            target_name = field.get("lookupList")
            target_field = field.get("lookupField", "Title")
            if not target_name or target_name not in by_name:
                raise ValueError(
                    f"{item['internalName']}.{field['internalName']}: unbekannte Lookup-Liste {target_name}"
                )
            target_fields = field_map(by_name[target_name])
            if target_field not in BUILTIN_FIELDS and target_field not in target_fields:
                raise ValueError(
                    f"{item['internalName']}.{field['internalName']}: Lookup-Feld "
                    f"{target_name}.{target_field} existiert nicht"
                )


def compile_schema(schema_dir: Path) -> dict:
    manifest = load_json(schema_dir / "manifest.json")
    policies = manifest.get("policies", {})
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
            validate_list(item, module["sourceFile"], policies)
            name = item["internalName"]
            if name in seen_lists:
                raise ValueError(f"Liste mehrfach definiert: {name}")
            seen_lists.add(name)
            enriched = dict(item)
            enriched.setdefault("description", "")
            enriched.setdefault("fields", [])
            enriched["fields"] = [normalize_field(field) for field in enriched["fields"]]
            enriched.setdefault("mode", "create")
            enriched["module"] = module["module"]
            lists.append(enriched)

    validate_lookups(lists, policies)

    return {
        "schemaVersion": manifest["schemaVersion"],
        "project": manifest["project"],
        "prefix": manifest["prefix"],
        "policies": policies,
        "modules": [module["module"] for module in modules],
        "summary": {
            "moduleCount": len(modules),
            "listCount": len(lists),
            "fieldCount": sum(len(item.get("fields", [])) for item in lists),
            "entityCount": sum(1 for item in lists if item.get("entity")),
            "catalogCount": sum(1 for item in lists if item.get("catalog")),
            "lookupCount": sum(
                1
                for item in lists
                for field in item.get("fields", [])
                if field.get("type") in {"Lookup", "LookupMulti"}
            ),
        },
        "lists": lists,
    }


def write_report(schema: dict, destination: Path) -> None:
    rows = []
    for item in schema["lists"]:
        rows.append(
            "<tr>"
            f"<td>{html.escape(item['module'])}</td>"
            f"<td><code>{html.escape(item['internalName'])}</code></td>"
            f"<td>{html.escape(item['displayName'])}</td>"
            f"<td>{html.escape(item.get('mode', 'create'))}</td>"
            f"<td>{'Entity' if item.get('entity') else 'Catalog' if item.get('catalog') else 'Standard'}</td>"
            f"<td>{len(item.get('fields', []))}</td>"
            "</tr>"
        )
    summary = schema["summary"]
    report = f"""<!doctype html><html lang='de'><head><meta charset='utf-8'>
<title>UserLifeCycle Schema {html.escape(schema['schemaVersion'])}</title>
<style>body{{font-family:system-ui;margin:2rem;color:#172033}}table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #d7deea;padding:.55rem;text-align:left}}th{{background:#eef2f7}}code{{background:#eef2f7;padding:.1rem .25rem}}</style></head><body>
<h1>UserLifeCycle Schema {html.escape(schema['schemaVersion'])}</h1>
<p>{summary['moduleCount']} Module · {summary['listCount']} Listen · {summary['fieldCount']} explizite Felder · {summary['entityCount']} Entitäten · {summary['catalogCount']} Kataloge · {summary['lookupCount']} Lookups.</p>
<table><thead><tr><th>Modul</th><th>Interner Name</th><th>Anzeige</th><th>Modus</th><th>Klasse</th><th>Felder</th></tr></thead><tbody>{''.join(rows)}</tbody></table>
</body></html>"""
    destination.write_text(report, encoding="utf-8")


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
    print(
        f"SCHEMA COMPILE: OK · {schema['summary']['listCount']} Listen · "
        f"{schema['summary']['fieldCount']} Felder · {compiled_path}"
    )
    print(f"SCHEMA REPORT: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
