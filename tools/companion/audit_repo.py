#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
errors = []
required = [
    ROOT / "powerplatform" / "VERSION",
    ROOT / "powerplatform" / "src" / "BenutzerLifeCycle" / "Other" / "Solution.xml",
    ROOT / "powerplatform" / "src" / "BenutzerLifeCycle" / "Other" / "Customizations.xml",
]
for path in required:
    if not path.exists():
        errors.append(f"Pflichtdatei fehlt: {path.relative_to(ROOT)}")

tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.splitlines()
for item in tracked:
    if item.startswith(("powerplatform/generated/", "export/", ".refact/buddy/chats/", ".refact/buddy/logs/", ".refact/buddy/state/")):
        errors.append(f"Lokales/erzeugtes Artefakt ist versioniert: {item}")
    if item.endswith(".zip"):
        errors.append(f"ZIP-Artefakt ist versioniert: {item}")

canvas = list((ROOT / "powerplatform" / "src").glob("**/CanvasApps/*_DocumentUri.msapp"))
if len(canvas) != 1:
    errors.append(f"Erwartet genau eine Canvas-App, gefunden: {len(canvas)}")

version = (ROOT / "powerplatform" / "VERSION").read_text(encoding="utf-8").strip() if (ROOT / "powerplatform" / "VERSION").exists() else ""
if not version:
    errors.append("powerplatform/VERSION ist leer")

if errors:
    print("REPOSITORY-AUDIT: FEHLER")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)
print(f"REPOSITORY-AUDIT: OK · Version {version} · {len(tracked)} versionierte Dateien")
