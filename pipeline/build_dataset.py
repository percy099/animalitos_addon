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

    wb_lockouts = {k: v for k, v in curated.get("worldBossLockouts", {}).items() if not k.startswith("_")}

    instances, sources, report = {}, [], defaultdict(list)

    def make_instance(jid):
        inst = raw["instances"][str(jid)]
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
        if lockout == "unknown":
            report["unknownLockout"].append(f"{jid} {inst['name']}")
        return {
            "tier": inst["tier"],
            "isRaid": inst["isRaid"],
            "mapID": inst["mapID"],
            "legacy": inst["tier"] < current_tier,
            "worldBoss": False,
            "lockoutModel": lockout,
            "entrance": entrance and {
                "uiMapID": entrance["uiMapID"],
                "x": round(entrance["x"], 4),
                "y": round(entrance["y"], 4),
                "continent": entrance.get("continent"),
            },
            "_name": inst["name"],
        }

    for (jid, encounter_id, mount_id), g in sorted(grouped.items()):
        inst = raw["instances"][str(jid)]
        enc = raw["encounters"].get(str(encounter_id), {})
        is_world_boss = jid in pseudo
        if is_world_boss:
            # The EJ lists every world boss of a continent as one "raid" whose
            # bosses live in different zones. Each boss becomes its own entry,
            # keyed by -journalEncounterID; the addon finds its map position
            # in game (C_EncounterJournal.GetEncountersOnMap) and reads the
            # weekly kill from GetSavedWorldBossInfo.
            wb_key = -encounter_id
            if wb_key not in instances:
                instances[wb_key] = {
                    "tier": inst["tier"],
                    "isRaid": True,
                    "legacy": inst["tier"] < current_tier,
                    "worldBoss": True,
                    "ejInstance": jid,
                    "encounter": encounter_id,
                    "lockoutModel": wb_lockouts.get(str(jid), "unknown"),
                    "_name": f"{enc.get('name')} ({inst['name']})",
                }
                if instances[wb_key]["lockoutModel"] == "unknown":
                    report["unknownLockout"].append(f"{wb_key} {enc.get('name')} (world boss, {inst['name']})")
            sources.append({
                "mountID": mount_id,
                "itemID": g["itemID"],
                "journalInstanceID": wb_key,
                "journalEncounterID": encounter_id,
                "dungeonEncounterID": enc.get("dungeonEncounterID"),
                "difficulties": [0],  # world bosses: one weekly kill, no difficulty choice
                "_comment": f"{enc.get('name')} - {inst['name']} (world boss)",
            })
            continue
        if jid not in instances:
            instances[jid] = make_instance(jid)
        sources.append({
            "mountID": mount_id,
            "itemID": g["itemID"],
            "journalInstanceID": jid,
            "journalEncounterID": encounter_id,
            "dungeonEncounterID": enc.get("dungeonEncounterID"),
            "difficulties": sorted(g["difficulties"]),
            "_comment": f"{enc.get('name')} - {inst['name']}",
        })

    # Hand-curated drops the Encounter Journal does not list (hidden bosses,
    # the other bosses of a shared drop). Each one was verified by hand on
    # Wowhead / warcraft.wiki.gg (see its "reason"). journalEncounterID is
    # resolved in game from dungeonEncounterID; hiddenBoss = locale key of a
    # boss that is not in the journal (its kill cannot be read: To verify).
    for x in curated.get("extraSources", {}).get("list", []):
        jid = x["journalInstanceID"]
        if str(jid) not in raw["instances"]:
            report["extraSourceUnknownInstance"].append(f"{jid} (mount {x['mountID']})")
            continue
        if jid not in instances:
            instances[jid] = make_instance(jid)
        name = raw["instances"][str(jid)]["name"]
        sources.append({
            "mountID": x["mountID"],
            "itemID": x["itemID"],
            "journalInstanceID": jid,
            "journalEncounterID": x.get("journalEncounterID"),
            "dungeonEncounterID": x.get("dungeonEncounterID"),
            "difficulties": sorted(x["difficulties"]),
            "hiddenBoss": x.get("hiddenBoss"),
            "curated": True,
            "_comment": f"{x.get('name', '?')} - {name} (curated)",
        })
        report["curatedSources"].append(f"{x.get('name')} - {name}")
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


def holiday_bosses(curated):
    """World event bosses (Dungeon Finder queues), straight from overrides."""
    out = []
    for h in curated.get("holidayBosses", {}).get("list", []):
        out.append({
            "lfgDungeonID": h["lfgDungeonID"],
            "event": h["event"],
            "mounts": [{"mountID": m["mountID"], "itemID": m["itemID"]} for m in h["mounts"]],
            "_comment": h.get("name", "?"),
        })
    return out


def vendor_requirements(curated):
    """[itemID] = requirement the item tooltip does not show (curated by hand)."""
    out = {}
    for e in curated.get("vendorRequirements", {}).get("list", []):
        req = {"reputation": e["reputation"], "standing": e["standing"]}
        if e.get("exceptRace"):
            req["exceptRace"] = e["exceptRace"]
        for item in e["itemIDs"]:
            out[item] = req
    return out


def write_lua(instances, sources, raw, digest, holidays=(), mount_items=None, vendor_reqs=None):
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
    lines.append("    holidays = {")
    for h in holidays:
        lines.append(f"        {lua_value(h)}, -- {h['_comment']}")
    lines.append("    },")
    # [mountID] = itemID that teaches it (from /aplan scan items): the item
    # tooltip says what a vendor asks for (reputation, faction, class).
    # [itemID] = what a vendor asks for that the tooltip does not show.
    lines.append("    vendorReqs = {")
    for item in sorted(vendor_reqs or {}):
        lines.append(f"        [{item}] = {lua_value(vendor_reqs[item])},")
    lines.append("    },")
    lines.append("    mountItems = {")
    pairs = [f"[{m}]={i}" for m, i in sorted((mount_items or {}).items())]
    for k in range(0, len(pairs), 8):
        lines.append("        " + ", ".join(pairs[k:k + 8]) + ",")
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
        f"| World bosses with mounts | {sum(1 for i in instances.values() if i['worldBoss'])} |",
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


def load_mount_items(db):
    """[mountID] = itemID. From the SavedVariables (/aplan scan items), saved
    as data/raw/mountitems-<client>.json; otherwise the newest snapshot."""
    if db and db.get("mountItems"):
        mi = db["mountItems"]
        items = mi.get("items") or {}
        if isinstance(items, list):
            items = {k + 1: v for k, v in enumerate(items) if v}
        data = {"client": mi.get("client"), "scannedAt": mi.get("scannedAt"),
                "items": {str(int(k)): int(v) for k, v in items.items() if v}}
        RAW_DIR.mkdir(parents=True, exist_ok=True)
        path = RAW_DIR / f"mountitems-{data['client']}.json"
        path.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print(f"mount items   -> {path.relative_to(ROOT)}")
    else:
        snaps = sorted(RAW_DIR.glob("mountitems-*.json"))
        if not snaps:
            return {}
        data = json.loads(snaps[-1].read_text(encoding="utf-8"))
    return {int(k): int(v) for k, v in data["items"].items()}

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("savedvariables", nargs="?", help="AnimalitosPlanner.lua SavedVariables file with a scan")
    ap.add_argument("--from-raw", help="rebuild from a committed data/raw/scan-*.json instead")
    args = ap.parse_args()
    db = None

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

    mount_items = load_mount_items(db if not args.from_raw else None)
    curated = json.loads(CURATED.read_text(encoding="utf-8"))
    instances, sources, report = build(raw, curated)
    digest = hashlib.sha1(json.dumps([instances, sources], sort_keys=True, default=str).encode()).hexdigest()[:12]
    holidays = holiday_bosses(curated)
    vendor_reqs = vendor_requirements(curated)
    write_lua(instances, sources, raw, digest, holidays, mount_items, vendor_reqs)
    print(f"vendor reqs   -> {len(vendor_reqs)} items with a curated requirement")
    print(f"mount items   -> {len(mount_items)} mounts with their item")
    print(f"holidays      -> {len(holidays)} event bosses")
    write_report(instances, sources, report, raw)
    print(f"dataset       -> {OUT_LUA.relative_to(ROOT)} ({len(sources)} sources, {len(instances)} instances)")
    print(f"report        -> {REPORT.relative_to(ROOT)}")
    for k, v in report.items():
        print(f"  {k}: {len(v)}")


if __name__ == "__main__":
    main()
