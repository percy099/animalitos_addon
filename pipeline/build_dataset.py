"""Build the addon dataset from an in-game `/aplan scan` plus curated overrides.

Usage:
    python3 pipeline/build_dataset.py "<path to WTF/.../SavedVariables/AnimalitosPlanner.lua>"
    python3 pipeline/build_dataset.py --from-raw data/raw/scan-12.1.5.70783.json

Outputs (all committed to the repo):
    data/raw/scan-<client>.json        normalized snapshot of the scan (reproducible input)
    AnimalitosPlanner/Data/Dataset.lua  generated Lua table (do not edit by hand)
    data/reports/dataset-report.md      gaps that need curation
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import defaultdict
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import savedvars  # noqa: E402

CURATED = ROOT / "data" / "curated" / "overrides.json"
RAW_DIR = ROOT / "data" / "raw"
REPORT = ROOT / "data" / "reports" / "dataset-report.md"
OUT_LUA = ROOT / "AnimalitosPlanner" / "Data" / "Dataset.lua"

DIFFICULTY_NAMES = {
    1: "Normal", 2: "Heroic", 23: "Mythic",
    3: "10 Normal", 4: "25 Normal", 5: "10 Heroic", 6: "25 Heroic", 9: "40 Player",
    14: "Normal", 15: "Heroic", 16: "Mythic", 7: "LFR (legacy)", 17: "LFR",
}
ZONE_MAP_TYPES = {3, 4, 5}      # Zone, Dungeon, Micro
AMBIGUOUS_MARGIN = 0.03


def values(t):
    """Lua array tables arrive as {1: a, 2: b}; return the values in key order."""
    if isinstance(t, dict):
        return [t[k] for k in sorted(t, key=lambda k: (not isinstance(k, int), k))]
    return list(t or [])


def normalize_scan(scan: dict) -> dict:
    """Turn the SavedVariables scan into plain JSON-friendly structures."""
    instances = {}
    for jid, inst in scan["instances"].items():
        info = inst.get("info", {})
        instances[str(jid)] = {
            "name": inst["name"],
            "isRaid": inst["isRaid"],
            "tier": inst["tier"],
            "tierName": inst["tierName"],
            "mapID": info.get(10) if isinstance(info.get(10), int) else None,
            "difficulties": {
                str(d): {
                    "numLoot": v.get("numLoot", 0),
                    "uncached": v.get("uncached", 0),
                    "mounts": [
                        {"mountID": m["mountID"], "itemID": m["itemID"], "encounterID": m.get("encounterID")}
                        for m in values(v.get("mounts"))
                    ],
                }
                for d, v in sorted(inst["difficulties"].items())
            },
        }
    encounters = {
        str(eid): {k: e.get(k) for k in ("name", "journalInstanceID", "dungeonEncounterID", "instanceID")}
        for eid, e in scan["encounters"].items()
    }
    entrances = {
        str(jid): [
            {k: e.get(k) for k in ("uiMapID", "mapType", "x", "y", "areaPoiID", "continent")}
            for e in values(lst)
        ]
        for jid, lst in scan["entrances"].items()
    }
    maps = {str(k): v for k, v in scan.get("maps", {}).items()}
    return {
        "client": scan["client"],
        "locale": scan.get("locale"),
        "scannedAt": scan.get("finishedAt") or scan.get("startedAt"),
        "instances": instances,
        "encounters": encounters,
        "entrances": entrances,
        "maps": maps,
    }


def edge_distance(e) -> float:
    return min(e["x"], 1 - e["x"], e["y"], 1 - e["y"])


def pick_entrance(candidates, maps, override=None):
    """Choose the entrance on the zone map that contains it.

    The same entrance is drawn on neighbouring zone maps near their edges, so
    prefer zone-level maps and the point farthest from the map border.
    Returns (entrance | None, ambiguous: bool).
    """
    if override:
        match = [c for c in candidates if c["uiMapID"] == override["uiMapID"]]
        if match:
            return match[0], False
        if "x" in override:
            return override, False
    zone = [c for c in candidates if c["mapType"] in ZONE_MAP_TYPES and c["x"] is not None]
    pool = zone or [c for c in candidates if c["x"] is not None]
    if not pool:
        return None, False
    ranked = sorted(pool, key=edge_distance, reverse=True)
    ambiguous = (
        len(ranked) > 1
        and ranked[0]["uiMapID"] != ranked[1]["uiMapID"]
        and edge_distance(ranked[0]) - edge_distance(ranked[1]) < AMBIGUOUS_MARGIN
    )
    return ranked[0], ambiguous


def build(raw: dict, curated: dict):
    pseudo = set(curated["worldBossPseudoInstances"]["ids"])
    excluded = set(curated["excludeInstances"]["ids"])
    current_tier = curated["currentExpansionTier"]
    entrance_overrides = curated.get("entranceOverrides", {})
    lockouts = {k: v for k, v in curated.get("lockoutModels", {}).items() if not k.startswith("_")}

    # Group mount drops into sources: (instance, encounter, mount) -> difficulties
    grouped = defaultdict(lambda: {"difficulties": set(), "itemID": None})
    for jid, inst in raw["instances"].items():
        if int(jid) in excluded:
            continue
        for d, diff in inst["difficulties"].items():
            for m in diff["mounts"]:
                key = (int(jid), m["encounterID"], m["mountID"])
                grouped[key]["difficulties"].add(int(d))
                grouped[key]["itemID"] = m["itemID"]

    instances, sources, report = {}, [], defaultdict(list)
    for (jid, encounter_id, mount_id), g in sorted(grouped.items()):
        inst = raw["instances"][str(jid)]
        enc = raw["encounters"].get(str(encounter_id), {})
        is_world_boss = jid in pseudo
        if jid not in instances:
            entrance, ambiguous = (None, False)
            if not is_world_boss:
                entrance, ambiguous = pick_entrance(
                    raw["entrances"].get(str(jid), []), raw["maps"], entrance_overrides.get(str(jid))
                )
                if entrance is None:
                    report["missingEntrance"].append(f"{jid} {inst['name']} ({inst['tierName']})")
                elif ambiguous:
                    report["ambiguousEntrance"].append(
                        f"{jid} {inst['name']}: picked uiMap {entrance['uiMapID']} — confirm or add an override"
                    )
            lockout = lockouts.get(str(jid), "unknown")
            if lockout == "unknown" and not is_world_boss:
                report["unknownLockout"].append(f"{jid} {inst['name']}")
            instances[jid] = {
                "tier": inst["tier"],
                "isRaid": inst["isRaid"],
                "mapID": inst["mapID"],
                "legacy": inst["tier"] < current_tier,
                "worldBoss": is_world_boss,
                "lockoutModel": lockout,
                "entrance": entrance and {
                    "uiMapID": entrance["uiMapID"],
                    "x": round(entrance["x"], 4),
                    "y": round(entrance["y"], 4),
                    "continent": entrance.get("continent"),
                },
                "_name": inst["name"],
            }
        sources.append({
            "mountID": mount_id,
            "itemID": g["itemID"],
            "journalInstanceID": jid,
            "journalEncounterID": encounter_id,
            "dungeonEncounterID": enc.get("dungeonEncounterID"),
            "difficulties": sorted(g["difficulties"]),
            "_comment": f"{enc.get('name')} - {inst['name']}",
        })
    return instances, sources, report


def lua_value(v, indent=0) -> str:
    pad = "    " * indent
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "{ " + ", ".join(lua_value(x) for x in v) + " }"
    if isinstance(v, dict):
        items = [f"{k} = {lua_value(x, indent + 1)}" for k, x in v.items() if x is not None and not k.startswith("_")]
        return "{ " + ", ".join(items) + " }"
    raise TypeError(type(v))


def write_lua(instances, sources, raw, digest):
    lines = [
        "-- GENERATED by pipeline/build_dataset.py — do not edit by hand.",
        f"-- Source: in-game /aplan scan, client {raw['client']}, scanned {raw['scannedAt']}.",
        "local _, ns = ...",
        "ns.Data = {",
        f"    version = {{ client = {json.dumps(raw['client'])}, generated = {json.dumps(date.today().isoformat())}, hash = {json.dumps(digest)} }},",
        "    instances = {",
    ]
    for jid in sorted(instances):
        inst = instances[jid]
        lines.append(f"        [{jid}] = {lua_value(inst)}, -- {inst['_name']}")
    lines.append("    },")
    lines.append("    sources = {")
    for s in sources:
        lines.append(f"        {lua_value(s)}, -- {s['_comment']}")
    lines.append("    },")
    lines.append("}")
    OUT_LUA.parent.mkdir(parents=True, exist_ok=True)
    OUT_LUA.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_report(instances, sources, report, raw):
    legacy = [i for i in instances.values() if i["legacy"] and not i["worldBoss"]]
    lines = [
        "# Dataset report",
        "",
        f"Generated from client `{raw['client']}` (scan {raw['scannedAt']}).",
        "",
        "| Metric | Value |",
        "|---|---|",
        f"| Sources (mount × boss × instance) | {len(sources)} |",
        f"| Unique mounts | {len({s['mountID'] for s in sources})} |",
        f"| Instances with mounts | {len(instances)} |",
        f"| Legacy instances (MVP scope) | {len(legacy)} |",
        f"| World-boss pseudo-instances | {sum(1 for i in instances.values() if i['worldBoss'])} |",
        "",
    ]
    titles = {
        "missingEntrance": "Instances without an entrance (add `entranceOverrides` with uiMapID/x/y)",
        "ambiguousEntrance": "Ambiguous entrances (confirm or override)",
        "unknownLockout": "Instances without a validated lockout model (v0.3)",
    }
    for key, title in titles.items():
        items = report.get(key, [])
        lines += [f"## {title} — {len(items)}", ""]
        lines += [f"- {x}" for x in items] or ["- none"]
        lines.append("")
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("savedvariables", nargs="?", help="AnimalitosPlanner.lua SavedVariables file with a scan")
    ap.add_argument("--from-raw", help="rebuild from a committed data/raw/scan-*.json instead")
    args = ap.parse_args()

    if args.from_raw:
        raw = json.loads(Path(args.from_raw).read_text(encoding="utf-8"))
    elif args.savedvariables:
        db = savedvars.load(args.savedvariables)["AnimalitosPlannerDB"]
        if "scan" not in db:
            sys.exit("No scan found: run /aplan scan in game, then /reload.")
        raw = normalize_scan(db["scan"])
        RAW_DIR.mkdir(parents=True, exist_ok=True)
        raw_path = RAW_DIR / f"scan-{raw['client']}.json"
        raw_path.write_text(json.dumps(raw, indent=1, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
        print(f"raw snapshot  -> {raw_path.relative_to(ROOT)}")
    else:
        ap.error("pass a SavedVariables file or --from-raw")

    curated = json.loads(CURATED.read_text(encoding="utf-8"))
    instances, sources, report = build(raw, curated)
    digest = hashlib.sha1(json.dumps([instances, sources], sort_keys=True, default=str).encode()).hexdigest()[:12]
    write_lua(instances, sources, raw, digest)
    write_report(instances, sources, report, raw)
    print(f"dataset       -> {OUT_LUA.relative_to(ROOT)} ({len(sources)} sources, {len(instances)} instances)")
    print(f"report        -> {REPORT.relative_to(ROOT)}")
    for k, v in report.items():
        print(f"  {k}: {len(v)}")


if __name__ == "__main__":
    main()
