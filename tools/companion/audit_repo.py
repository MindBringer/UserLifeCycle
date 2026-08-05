#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
errors: list[str] = []
solution = ROOT / "powerplatform" / "src" / "BenutzerLifeCycle"
canvas_source = ROOT / "powerplatform" / "canvas-src" / "gp_blcroleentitlementmanager"
canvas_src = canvas_source / "Src"
required = [
    ROOT / "powerplatform" / "VERSION",
    solution / "Other" / "Solution.xml",
    solution / "Other" / "Customizations.xml",
    canvas_src / "App.pa.yaml",
]
for path in required:
    if not path.exists():
        errors.append(f"Pflichtdatei fehlt: {path.relative_to(ROOT)}")

tracked = subprocess.run(
    ["git", "ls-files"], cwd=ROOT, text=True, capture_output=True, check=True
).stdout.splitlines()
for item in tracked:
    if item.startswith((
        "powerplatform/generated/",
        "export/",
        ".refact/buddy/chats/",
        ".refact/buddy/logs/",
        ".refact/buddy/state/",
    )):
        errors.append(f"Lokales/erzeugtes Artefakt ist versioniert: {item}")
    if item.endswith(".zip"):
        errors.append(f"ZIP-Artefakt ist versioniert: {item}")

canvas_apps = list(solution.glob("CanvasApps/*_DocumentUri.msapp"))
if len(canvas_apps) != 1:
    errors.append(f"Erwartet genau eine Canvas-App in der Solution, gefunden: {len(canvas_apps)}")

canvas_yaml = list(canvas_src.rglob("*.pa.yaml")) if canvas_src.exists() else []
if len(canvas_yaml) < 2:
    errors.append(
        f"SourceCode-Layout unvollständig: mindestens App und ein Screen erwartet, gefunden: {len(canvas_yaml)}"
    )

version_file = ROOT / "powerplatform" / "VERSION"
version = version_file.read_text(encoding="utf-8").strip() if version_file.exists() else ""
if not version:
    errors.append("powerplatform/VERSION ist leer")

if errors:
    print("REPOSITORY-AUDIT: FEHLER")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print(
    f"REPOSITORY-AUDIT: OK · Version {version} · "
    f"{len(canvas_yaml)} Canvas-YAML-Dateien · {len(tracked)} versionierte Dateien"
)
