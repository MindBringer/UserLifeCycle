#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ulc_engine", ROOT / "tools/lifecycle/engine.py")
engine = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(engine)
config = json.loads((ROOT / "engine/engine-config.json").read_text(encoding="utf-8"))

CATALOG = {
    "roleEntitlements": [
        {"roleProfileKey":"ROLE_OLD","entitlementKey":"E_MAIL"},
        {"roleProfileKey":"ROLE_OLD","entitlementKey":"E_OLD"},
        {"roleProfileKey":"ROLE_NEW","entitlementKey":"E_MAIL"},
        {"roleProfileKey":"ROLE_NEW","entitlementKey":"E_NEW"}
    ],
    "taskTemplates": [
        {"technicalKey":"ENTITLEMENT_CHANGE","title":"Berechtigung ändern","actionType":"Change","ownerType":"IT","slaProfileKey":"SLA_STD"},
        {"technicalKey":"WELCOME","title":"Eintritt vorbereiten","actionType":"Manual","ownerType":"HR","slaProfileKey":"SLA_STD"}
    ],
    "slaProfiles": [{"technicalKey":"SLA_STD","dueDays":2,"reminderDaysBefore":1,"calendarMode":"BusinessDays"}],
    "assignmentRules": [{"technicalKey":"RULE_WELCOME","lifecycleType":"Onboarding","taskTemplateKey":"WELCOME","priority":100,"active":True}]
}


def plan(kind, current, target=None, exceptions=None):
    return engine.generate_plan({
        "request":{"requestId":f"REQ-{kind}","type":kind,"effectiveDate":"2026-08-10T08:00:00Z","targetRoleProfileKey":target,"currentDesiredEntitlements":current,"exceptionEntitlements":exceptions or []},
        "employment":{"organizationKey":"ORG","departmentKey":"IT","locationKey":"HQ","positionKey":"DEV"},
        "catalog":CATALOG
    }, config)

joiner = plan("Onboarding", [], "ROLE_NEW")
assert joiner["entitlementDelta"] == {"grant":["E_MAIL","E_NEW"],"revoke":[]}
assert len(joiner["tasks"]) == 3

mover = plan("Mover", ["E_MAIL","E_OLD"], "ROLE_NEW")
assert mover["entitlementDelta"] == {"grant":["E_NEW"],"revoke":["E_OLD"]}
assert len(mover["tasks"]) == 2

mover_exception = plan("Mover", ["E_MAIL","E_OLD"], "ROLE_NEW", ["E_OLD"])
assert mover_exception["entitlementDelta"] == {"grant":["E_NEW"],"revoke":[]}

leaver = plan("Offboarding", ["E_MAIL","E_NEW"])
assert leaver["entitlementDelta"] == {"grant":[],"revoke":["E_MAIL","E_NEW"]}
assert len(leaver["tasks"]) == 2

# idempotency
assert engine.generate_plan({"request":{"requestId":"REQ-X","type":"Mover","effectiveDate":"2026-08-10T08:00:00Z","targetRoleProfileKey":"ROLE_NEW","currentDesiredEntitlements":["E_OLD"]},"employment":{},"catalog":CATALOG}, config)["engineRunKey"] == engine.generate_plan({"request":{"requestId":"REQ-X","type":"Mover","effectiveDate":"2026-08-10T08:00:00Z","targetRoleProfileKey":"ROLE_NEW","currentDesiredEntitlements":["E_OLD"]},"employment":{},"catalog":CATALOG}, config)["engineRunKey"]

print("LIFECYCLE SELFTEST: OK · Joiner/Mover/Leaver/Idempotency")
