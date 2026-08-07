#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def stable_key(*parts: object) -> str:
    raw = "|".join(str(p or "") for p in parts)
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:20]
    return f"ULC-{digest}"


def parse_date(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def add_business_days(start: datetime, days: int) -> datetime:
    current = start
    step = 1 if days >= 0 else -1
    remaining = abs(days)
    while remaining:
        current += timedelta(days=step)
        if current.weekday() < 5:
            remaining -= 1
    return current


def add_days(start: datetime, days: int, mode: str) -> datetime:
    return add_business_days(start, days) if mode == "BusinessDays" else start + timedelta(days=days)


def rule_matches(rule: dict, request: dict, employment: dict) -> bool:
    if not rule.get("active", True):
        return False
    lifecycle = rule.get("lifecycleType", "Any")
    if lifecycle not in ("Any", request["type"]):
        return False
    for field in ("organizationKey", "departmentKey", "locationKey", "positionKey"):
        expected = rule.get(field)
        if expected and expected != employment.get(field):
            return False
    return True


def select_rules(rules: list[dict], request: dict, employment: dict) -> list[dict]:
    selected = [r for r in rules if rule_matches(r, request, employment)]
    selected.sort(key=lambda r: (-int(r.get("priority", 0)), r.get("technicalKey", "")))
    result = []
    for rule in selected:
        result.append(rule)
        if rule.get("stopProcessing"):
            break
    return result


def role_entitlements(role_key: str | None, catalog: dict) -> set[str]:
    if not role_key:
        return set()
    return {
        row["entitlementKey"]
        for row in catalog.get("roleEntitlements", [])
        if row.get("roleProfileKey") == role_key and row.get("active", True)
    }


def calculate_entitlement_delta(request: dict, catalog: dict) -> dict:
    current = set(request.get("currentDesiredEntitlements", []))
    if request["type"] == "Offboarding":
        return {"grant": [], "revoke": sorted(current)}

    target = role_entitlements(request.get("targetRoleProfileKey"), catalog)
    if request["type"] == "Onboarding":
        return {"grant": sorted(target - current), "revoke": []}

    # Mover: delta only; explicit exceptions are not removed by the engine.
    protected = set(request.get("exceptionEntitlements", []))
    revoke = (current - target) - protected
    grant = target - current
    return {"grant": sorted(grant), "revoke": sorted(revoke)}


def make_task(request: dict, template: dict, action: str, ref_key: str | None, effective: datetime, sla: dict) -> dict:
    due_days = int(sla.get("dueDays", 0))
    mode = sla.get("calendarMode", "CalendarDays")
    due = add_days(effective, due_days, mode)
    reminder_days = int(sla.get("reminderDaysBefore", 0))
    reminder = add_days(due, -reminder_days, mode) if reminder_days else None
    engine_key = stable_key(request["requestId"], template.get("technicalKey"), action, ref_key)
    return {
        "engineTaskKey": engine_key,
        "requestId": request["requestId"],
        "templateKey": template.get("technicalKey"),
        "title": template.get("title") or template.get("technicalKey"),
        "actionType": action,
        "referenceKey": ref_key,
        "ownerType": template.get("ownerType", "IT"),
        "ownerValue": template.get("ownerValue", ""),
        "blocking": bool(template.get("blocking", False)),
        "evidenceRequired": bool(template.get("evidenceRequired", False)),
        "status": "Open",
        "dueAt": due.isoformat(),
        "reminderAt": reminder.isoformat() if reminder else None,
    }


def generate_plan(payload: dict, config: dict) -> dict:
    request = payload["request"]
    employment = payload["employment"]
    catalog = payload.get("catalog", {})
    effective = parse_date(request.get("effectiveDate"))
    selected_rules = select_rules(catalog.get("assignmentRules", []), request, employment)
    delta = calculate_entitlement_delta(request, catalog)
    templates = {x["technicalKey"]: x for x in catalog.get("taskTemplates", [])}
    slas = {x["technicalKey"]: x for x in catalog.get("slaProfiles", [])}
    default_sla = config["defaultSla"]
    tasks: list[dict] = []

    for rule in selected_rules:
        template_key = rule.get("taskTemplateKey")
        if not template_key or template_key not in templates:
            continue
        template = templates[template_key]
        sla = slas.get(template.get("slaProfileKey"), default_sla)
        tasks.append(make_task(request, template, template.get("actionType", "Manual"), None, effective, sla))

    entitlement_template = templates.get("ENTITLEMENT_CHANGE")
    if entitlement_template:
        sla = slas.get(entitlement_template.get("slaProfileKey"), default_sla)
        for entitlement in delta["grant"]:
            tasks.append(make_task(request, entitlement_template, "Grant", entitlement, effective, sla))
        for entitlement in delta["revoke"]:
            tasks.append(make_task(request, entitlement_template, "Revoke", entitlement, effective, sla))

    # deterministic de-duplication by task key
    unique = {task["engineTaskKey"]: task for task in tasks}
    tasks = [unique[key] for key in sorted(unique)]
    engine_run_key = stable_key(request["requestId"], request["type"], request.get("effectiveDate"), request.get("targetRoleProfileKey"))

    return {
        "engineVersion": config["engineVersion"],
        "engineRunKey": engine_run_key,
        "requestId": request["requestId"],
        "requestType": request["type"],
        "selectedRules": [r.get("technicalKey") for r in selected_rules],
        "entitlementDelta": delta,
        "tasks": tasks,
        "audit": {
            "entityType": "LifecycleRequest",
            "entityId": request["requestId"],
            "correlationId": engine_run_key,
            "action": "PlanCalculated",
            "source": "LifecycleEngine",
            "occurredAt": datetime.now(timezone.utc).isoformat(),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="UserLifeCycle deterministic lifecycle-engine simulator")
    parser.add_argument("--input", required=True)
    parser.add_argument("--config", default=str(ROOT / "engine" / "engine-config.json"))
    parser.add_argument("--output", default=str(ROOT / "generated" / "engine" / "plan.json"))
    args = parser.parse_args()

    payload = load_json(Path(args.input))
    config = load_json(Path(args.config))
    if payload.get("request", {}).get("type") not in config["requestTypes"]:
        raise SystemExit("Unsupported request type")
    plan = generate_plan(payload, config)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"LIFECYCLE ENGINE: OK · {plan['requestType']} · {len(plan['tasks'])} Tasks · {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
