#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,html,json,re
from collections import Counter
from pathlib import Path

SYSTEM={"_ColorTag","_ComplianceFlags","_ComplianceTag","_ComplianceTagUserId","_ComplianceTagWrittenTime","_IsRecord","_UIVersionString","AppAuthor","AppEditor","Attachments","Author","ComplianceAssetId","ContentType","Created","DocIcon","Edit","Editor","FolderChildCount","ID","ItemChildCount","LinkTitle","LinkTitleNoMenu","Modified"}
SUFFIXES=(".pa.yaml",".json",".xml",".ps1",".md",".csv")

def args():
 p=argparse.ArgumentParser();
 for n in ("schema","target","canvas","flows","provisioning","output"): p.add_argument(f"--{n}",required=True,type=Path)
 return p.parse_args()

def load(p): return json.loads(p.read_text(encoding="utf-8-sig"))

def corpus(root,exclude=None):
 exclude=exclude or set(); out=[]; files=[]
 if not root.exists(): return "",files
 for p in sorted(root.rglob("*")):
  if p.is_file() and p not in exclude and p.name.endswith(SUFFIXES):
   out.append(p.read_text(encoding="utf-8-sig",errors="ignore")); files.append(str(p))
 return "\n".join(out),files

def has(text,name):
 return bool(name and re.search(rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])",text,re.I))

def classify(lst,field,target,refs):
 key=f"{lst}.{field['internalName']}"; explicit=target.get("fieldActions",{}).get(key)
 if explicit: return explicit["action"],explicit.get("target",""),"Explizite Zielmodellregel"
 if refs["canvas"] or refs["flow"]: return "KEEP","","Aktuell durch Canvas oder Flow referenziert"
 if refs["provisioning"]: return "REVIEW","","Im Provisioning vorhanden, aber nicht in Canvas/Flows gefunden"
 return "REVIEW","","Keine Code-Referenz gefunden; fachliche Prüfung erforderlich"

def render(rows,lists,summary):
 counts=Counter(r["Action"] for r in rows)
 badges="".join(f'<span class="b {k.lower()}">{html.escape(k)}: {v}</span>' for k,v in sorted(counts.items()))
 lcols=("List","Action","Target","Fields","Canvas","Flows","Reason")
 fcols=("List","Field","Type","Required","Indexed","Unique","Canvas","Flow","Provisioning","Action","Target","Reason")
 def table(data,cols):
  head="".join(f"<th>{c}</th>" for c in cols)
  body="".join("<tr>"+"".join(f"<td>{html.escape(str(r.get(c,'')))}</td>" for c in cols)+"</tr>" for r in data)
  return f'<div class="scroll"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'
 new="".join(f"<li><code>{html.escape(x)}</code></li>" for x in summary["newLists"])
 return f'''<!doctype html><html lang="de"><head><meta charset="utf-8"><title>BLC Schema Matrix</title><style>body{{font-family:system-ui;background:#f4f6f8;color:#172033}}main{{max-width:1500px;margin:24px auto}}section{{background:white;padding:18px;margin:16px 0;border:1px solid #d8dee8;border-radius:10px}}table{{width:100%;border-collapse:collapse;font-size:13px}}th,td{{padding:8px;border-bottom:1px solid #e6eaf0;text-align:left;vertical-align:top}}th{{position:sticky;top:0;background:#eef2f7}}.scroll{{overflow:auto;max-height:70vh}}.b{{display:inline-block;padding:5px 9px;margin:3px;border-radius:999px;background:#e2e8f0}}.keep{{background:#dcfce7}}.move,.change{{background:#dbeafe}}.review{{background:#fef3c7}}code{{background:#eef2f7;padding:2px 4px}}</style></head><body><main><h1>BenutzerLifeCycle 2.0 – Schema- und Referenzmatrix</h1><p>Automatisch aus Live-Schema, Canvas, Flows, Provisioning und Zielmodell.</p>{badges}<section><h2>Zusammenfassung</h2><p>{summary['listCount']} Listen · {summary['fieldCount']} Felder · {summary['canvasFiles']} Canvas-Dateien · {summary['flowFiles']} Flow-Dateien</p><ul>{new}</ul></section><section><h2>Listenmatrix</h2>{table(lists,lcols)}</section><section><h2>Feldmatrix</h2>{table(rows,fcols)}</section></main></body></html>'''

def main():
 a=args(); schema=load(a.schema); target=load(a.target)
 canvas,cfiles=corpus(a.canvas); flows,ffiles=corpus(a.flows); provisioning,pfiles=corpus(a.provisioning,{a.target})
 rows=[]; lists=[]
 for ld in schema.get("lists",[]):
  name=str(ld.get("title",""))
  if not name.startswith(target.get("scopePrefix","BLC_")): continue
  rule=target.get("listActions",{}).get(name,{"action":"REVIEW","reason":"Keine Zielmodellregel"})
  fields=[f for f in ld.get("fields",[]) if f.get("internalName") not in SYSTEM and not f.get("hidden") and not f.get("readOnly")]
  lists.append({"List":name,"Action":rule.get("action","REVIEW"),"Target":rule.get("target") or ", ".join(rule.get("targets",[])),"Fields":len(fields),"Canvas":"yes" if has(canvas,name) else "no","Flows":"yes" if has(flows,name) else "no","Reason":rule.get("reason","")})
  for f in fields:
   internal=str(f.get("internalName","")); refs={"canvas":has(canvas,internal),"flow":has(flows,internal),"provisioning":has(provisioning,internal)}
   action,tgt,reason=classify(name,f,target,refs)
   rows.append({"List":name,"Field":internal,"DisplayName":f.get("title",""),"Type":f.get("type",""),"Required":bool(f.get("required")),"Indexed":bool(f.get("indexed")),"Unique":bool(f.get("enforceUnique")),"LookupList":f.get("lookupList",""),"LookupField":f.get("lookupField",""),"Choices":" | ".join(map(str,f.get("choices",[]))),"Canvas":refs["canvas"],"Flow":refs["flow"],"Provisioning":refs["provisioning"],"Action":action,"Target":tgt,"Reason":reason})
 rows.sort(key=lambda r:(r["List"],r["Field"])); lists.sort(key=lambda r:r["List"]); a.output.mkdir(parents=True,exist_ok=True)
 summary={"listCount":len(lists),"fieldCount":len(rows),"canvasFiles":len(cfiles),"flowFiles":len(ffiles),"provisioningFiles":len(pfiles),"newLists":target.get("newLists",[])}
 data={"schemaVersion":target.get("schemaVersion"),"summary":summary,"lists":lists,"fields":rows}
 (a.output/"schema-matrix.json").write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
 if rows:
  with (a.output/"schema-matrix.csv").open("w",encoding="utf-8-sig",newline="") as h:
   w=csv.DictWriter(h,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
 (a.output/"schema-matrix.html").write_text(render(rows,lists,summary),encoding="utf-8")
 print(f"SCHEMA-ANALYZER: OK · {len(lists)} Listen · {len(rows)} Felder · {a.output}")

if __name__=="__main__": main()
