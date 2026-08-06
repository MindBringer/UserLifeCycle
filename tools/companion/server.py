#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, os, shutil, socket, subprocess, threading, webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
WEB = Path(__file__).resolve().parent
DEFAULT_HOST, DEFAULT_PORT, MAX_PORT_TRIES = "127.0.0.1", 8780, 20
RELEASE_CONFIRMATION = "RELEASE NACH MAIN"
APPLY_CONFIRMATION = "APPLY SCHEMA"
ACTIONS = {
    "status": ["git", "status", "--short", "--branch"],
    "fetch": ["git", "fetch", "--prune", "origin"],
    "pull": ["git", "pull", "--ff-only"],
    "audit": ["python3", "./tools/companion/audit_repo.py"],
    "validate": ["pwsh", "./powerplatform/scripts/Validate-Solution.ps1"],
    "build": ["pwsh", "./powerplatform/scripts/Build.ps1"],
    "schema-analyze": ["pwsh", "./Provisioning/Invoke-SchemaAnalyzer.ps1"],
    "schema-compile": ["pwsh", "./Provisioning/Compile-Schema.ps1"],
    "provision-dryrun": ["pwsh", "./Provisioning/Invoke-ProvisioningLocal.ps1", "-Mode", "DryRun"],
    "provision-validate": ["pwsh", "./Provisioning/Invoke-ProvisioningLocal.ps1", "-Mode", "Validate"],
    "reset-dryrun": ["pwsh", "./Provisioning/Invoke-ResetLocal.ps1", "-Mode", "DryRun"],
    "seed-dryrun": ["pwsh", "./Provisioning/Invoke-SeedLocal.ps1", "-Mode", "DryRun"],
    "seed-validate": ["pwsh", "./Provisioning/Invoke-SeedLocal.ps1", "-Mode", "Validate"],
}

def run(command, timeout=3600):
    return subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False, timeout=timeout)

def checked(command, log, timeout=3600):
    log.append("\n$ " + " ".join(command)); result = run(command, timeout)
    if result.stdout: log.append(result.stdout.rstrip())
    if result.returncode: raise RuntimeError(f"Schritt fehlgeschlagen (Exit {result.returncode}): {' '.join(command)}")

def release(payload):
    log=[]
    try:
        if payload.get("confirmation") != RELEASE_CONFIRMATION: raise RuntimeError("Bestätigung fehlt.")
        if shutil.which("gh") is None: raise RuntimeError("GitHub CLI fehlt; gh auth login ausführen.")
        checked(["gh","auth","status"],log,60)
        branch=run(["git","branch","--show-current"],30).stdout.strip()
        if not branch or branch == "main": raise RuntimeError("Release nur aus Feature-/Fix-Branch zulässig.")
        checked(["python3","./tools/companion/audit_repo.py"],log)
        checked(["pwsh","./Provisioning/Compile-Schema.ps1"],log)
        checked(["pwsh","./powerplatform/scripts/Validate-Solution.ps1"],log)
        checked(["pwsh","./powerplatform/scripts/Build.ps1"],log)
        if run(["git","status","--porcelain"],30).stdout.strip():
            version=(ROOT/"powerplatform/VERSION").read_text().strip()
            checked(["git","add","-A"],log); checked(["git","commit","-m",f"chore(release): finalize {version}"],log)
        checked(["git","fetch","--prune","origin"],log)
        checked(["git","rebase","origin/main"],log)
        checked(["python3","./tools/companion/audit_repo.py"],log)
        checked(["pwsh","./Provisioning/Compile-Schema.ps1"],log)
        checked(["pwsh","./powerplatform/scripts/Build.ps1"],log)
        checked(["git","push","--force-with-lease","-u","origin",branch],log)
        pr=run(["gh","pr","view","--json","number","--jq",".number"],60)
        if pr.returncode or not pr.stdout.strip():
            checked(["gh","pr","create","--base","main","--head",branch,"--title",f"Release {branch}","--body","Automatisch durch den UserLifeCycle Developer Companion erstellt."],log,120)
        checks=run(["gh","pr","checks","--watch","--fail-fast"],1800)
        log += ["\n$ gh pr checks --watch --fail-fast", checks.stdout.rstrip()]
        if checks.returncode == 1 and "no checks reported" not in checks.stdout.lower(): raise RuntimeError("PR-Checks fehlgeschlagen.")
        if checks.returncode not in (0,1): raise RuntimeError("PR-Checks konnten nicht ausgewertet werden.")
        checked(["gh","pr","merge","--squash","--delete-branch"],log,300)
        checked(["git","switch","main"],log); checked(["git","pull","--ff-only","origin","main"],log)
        return {"ok":True,"exitCode":0,"command":"Full release","output":"\n".join(log)}
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        log.append(f"\nABBRUCH: {exc}"); return {"ok":False,"exitCode":1,"command":"Full release","output":"\n".join(log)}

def execute(command):
    result=run(command)
    return {"ok":result.returncode==0,"exitCode":result.returncode,"command":" ".join(command),"output":result.stdout}

def info():
    return {"branch":run(["git","branch","--show-current"],30).stdout.strip(),"version":(ROOT/"powerplatform/VERSION").read_text().strip(),"dirty":bool(run(["git","status","--porcelain"],30).stdout.strip()),"root":str(ROOT),"provisioningConfigured":(ROOT/"Provisioning/settings.local.psd1").exists()}

class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*a,**k): super().__init__(*a,directory=str(WEB),**k)
    def log_message(self,*a): return
    def send_json(self,p,status=200):
        data=json.dumps(p,ensure_ascii=False).encode(); self.send_response(status); self.send_header("Content-Type","application/json; charset=utf-8"); self.send_header("Content-Length",str(len(data))); self.send_header("Cache-Control","no-store"); self.end_headers(); self.wfile.write(data)
    def read_payload(self):
        length=int(self.headers.get("Content-Length","0")); body=self.rfile.read(length) if length else b"{}"
        try: return json.loads(body)
        except json.JSONDecodeError: return {}
    def do_GET(self):
        if urlparse(self.path).path=="/api/info": self.send_json(info()); return
        super().do_GET()
    def do_POST(self):
        action=urlparse(self.path).path.rsplit("/",1)[-1]
        if action=="release": self.send_json(release(self.read_payload())); return
        if action=="provision-apply":
            payload=self.read_payload()
            if payload.get("confirmation") != APPLY_CONFIRMATION:
                self.send_json({"ok":False,"exitCode":409,"output":"Bestätigung APPLY SCHEMA fehlt."},409); return
            self.send_json(execute(["pwsh","./Provisioning/Invoke-ProvisioningLocal.ps1","-Mode","Apply"])); return
        if action=="reset-apply":
            token=str(self.read_payload().get("confirmation") or "")
            if not token.startswith("RESET|"):
                self.send_json({"ok":False,"exitCode":409,"output":"Gültiges Reset-Token aus dem Dry Run fehlt."},409); return
            self.send_json(execute(["pwsh","./Provisioning/Invoke-ResetLocal.ps1","-Mode","Apply","-ConfirmationToken",token])); return
        if action=="seed-apply":
            self.send_json(execute(["pwsh","./Provisioning/Invoke-SeedLocal.ps1","-Mode","Apply"])); return
        command=ACTIONS.get(action)
        if not command: self.send_json({"ok":False,"exitCode":404,"output":"Unbekannte Aktion."},404); return
        if action=="pull" and run(["git","status","--porcelain"],30).stdout.strip(): self.send_json({"ok":False,"exitCode":409,"output":"Pull abgebrochen: lokale Änderungen vorhanden."},409); return
        self.send_json(execute(command))

def available(host,port):
    with socket.socket() as s:
        try: s.bind((host,port)); return True
        except OSError: return False

def main():
    p=argparse.ArgumentParser(); p.add_argument("--host",default=os.getenv("ULC_COMPANION_HOST",DEFAULT_HOST)); p.add_argument("--port",type=int); p.add_argument("--no-browser",action="store_true"); a=p.parse_args()
    if a.port is not None:
        if not available(a.host,a.port): raise SystemExit(f"Port {a.port} ist belegt.")
        port=a.port
    else:
        start=int(os.getenv("ULC_COMPANION_PORT",DEFAULT_PORT)); port=next((x for x in range(start,start+MAX_PORT_TRIES) if available(a.host,x)),None)
        if port is None: raise SystemExit("Kein freier Companion-Port gefunden.")
    url=f"http://{a.host}:{port}"; print(f"UserLifeCycle Developer Companion: {url}\nRepository: {ROOT}")
    server=ThreadingHTTPServer((a.host,port),Handler)
    if not a.no_browser: threading.Timer(.5,lambda:webbrowser.open(url)).start()
    try: server.serve_forever()
    except KeyboardInterrupt: print("\nCompanion beendet.")
    finally: server.server_close()
if __name__=="__main__": main()
