#!/usr/bin/env python3
"""Read the pinned Classic-DB SQL dump; never execute the SQL.

Output is an explicitly Classic reference layer, not a Forever loot database.
Only single, condition-free selection paths get a 1x DB-roll percentage.
Repeated references, duplicate paths, quests, conditions and history-dependent
equal-chance groups retain their item relation but have no displayed percentage.
Derived database fields remain subject to Classic-DB's GPL-3.0 and copyright
notices. No dialogue, scripts, artwork, or private-server implementation ships.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
import csv
import gzip
import hashlib
import json
import math
import re
import time

BASE = Path(__file__).resolve().parent
TUPLE = re.compile(r"\((?:'(?:\\.|[^'\\])*'|[^'()])*\)")
METHODS = {
    "loot": ("creature_loot_template", "LootId", "lootId"),
    "skinning": ("skinning_loot_template", "SkinningLootId", "skinningLootId"),
    "pickpocket": ("pickpocketing_loot_template", "PickpocketLootId", "pickpocketLootId"),
}
NOTE = (
    "Classic DB-basiskans (1× lootrollen), basissnapshot 2023-10-09; niet bevestigd voor Forever. "
    "Percentages beschrijven uitsluitend aantoonbare DB-selectiepaden vóór servermodifiers, "
    "loot-slotlimieten en persoonlijke buitverdeling. Questvoorwaarden, andere voorwaarden, "
    "herhaalde/overlappende referenties en afhankelijke poolselectie blijven onbekend. "
    "De 437 latere repository-updates zijn niet toegepast."
)


def read_table(sql: str, table: str):
    schema = re.search(r"CREATE TABLE `" + re.escape(table) + r"`\s*\((.*?)\) ENGINE", sql, re.S)
    if not schema:
        raise ValueError(f"Missing schema for {table}")
    columns = re.findall(r"^\s*`([^`]+)`", schema.group(1), re.M)
    prefix = f"INSERT INTO `{table}` VALUES "
    parsed = 0
    for line in sql.splitlines():
        if not line.startswith(prefix):
            continue
        body = line[len(prefix):].rstrip(";\r\n")
        previous = 0
        for match in TUPLE.finditer(body):
            assert body[previous:match.start()].strip() in ("", ","), (table, previous)
            previous = match.end()
            values = next(csv.reader([match.group(0)[1:-1]], delimiter=",", quotechar="'", escapechar="\\", strict=True))
            assert len(values) == len(columns), (table, len(values), len(columns))
            parsed += 1
            yield dict(zip(columns, values))
        assert not body[previous:].strip(), (table, "unparsed trailing data")
    print(f"parsed {table}: {parsed:,} rows", flush=True)


@dataclass(frozen=True)
class Row:
    item: int
    chance: float
    group: int
    minimum: int
    maximum: int
    condition: int

    @property
    def reference(self):
        return -self.minimum if self.minimum < 0 else None


def encode_row(item, percent, quest, condition, minimum, maximum):
    # Retain enough significant digits for very small reference probabilities.
    fields = [str(item), "" if percent is None else format(percent, ".10g"),
              "1" if quest else "", "" if condition is None else str(condition), "", "",
              "" if minimum is None else str(minimum), "" if maximum is None else str(maximum)]
    return "|".join(fields)


class Resolver:
    def __init__(self, refs):
        self.refs = refs
        self.invalid = Counter()

    def path_counts(self, rows, stack=()):
        """Count possible paths, capped at 2; repeated reference calls count twice.

        Deliberately conservative: two mutually exclusive paths also count twice.
        That may withhold a calculable rate, but cannot invent one.
        """
        out = Counter()
        for row in rows:
            if row.reference is None:
                out[row.item] = min(2, out[row.item] + 1)
            elif row.reference in stack:
                self.invalid["reference_cycle"] += 1
            elif row.reference not in self.refs:
                self.invalid["missing_reference"] += 1
            else:
                child = self.path_counts(self.refs[row.reference], stack + (row.reference,))
                for item, n in child.items():
                    out[item] = min(2, out[item] + n * min(2, row.maximum))
        return out

    def resolve(self, rows):
        counts = self.path_counts(rows)
        leaves = defaultdict(list)

        def walk(current, parent_probability=1.0, inherited_conditions=(), inherited_repeated=False, stack=()):
            groups = defaultdict(list)
            for row in current:
                groups[row.group].append(row)
            weights = {}
            reasons = {}
            for group, members in groups.items():
                if group == 0:
                    for row in members:
                        weights[id(row)] = min(100.0, abs(row.chance)) / 100
                    continue
                explicit = sum(abs(row.chance) for row in members if row.chance != 0)
                equal = [row for row in members if row.chance == 0]
                conditioned = any(row.condition for row in members)
                # Equal-group selection tests the row's actual item field,
                # including the placeholder field on a reference row.
                history_dependent = any(counts.get(row.item, 0) > (1 if row.reference is None else 0) for row in equal)
                for row in members:
                    if conditioned:
                        weights[id(row)] = None
                        reasons[id(row)] = "group_conditions"
                    elif explicit > 100.000000001:
                        weights[id(row)] = None
                        reasons[id(row)] = "overfull_group"
                    elif row.chance != 0:
                        weights[id(row)] = abs(row.chance) / 100
                    elif history_dependent:
                        weights[id(row)] = None
                        reasons[id(row)] = "history_dependent_equal_group"
                    else:
                        weights[id(row)] = max(0.0, 1 - explicit / 100) / len(equal)
            for row in current:
                conditions = inherited_conditions + ((row.condition,) if row.condition else ())
                weight = weights[id(row)]
                probability = None if parent_probability is None or weight is None or conditions else parent_probability * weight
                repeated = inherited_repeated or (row.reference is not None and row.maximum != 1)
                if repeated:
                    probability = None
                if row.reference is not None:
                    if row.reference not in stack and row.reference in self.refs:
                        walk(self.refs[row.reference], probability, conditions, repeated, stack + (row.reference,))
                    continue
                quest = row.chance < 0
                if quest:
                    probability = None
                reason = ("quest" if quest else "conditions" if conditions else "repeated_reference" if repeated
                          else reasons.get(id(row), "composite_unknown" if probability is None else None))
                leaves[row.item].append({
                    "probability": probability, "quest": quest, "conditions": set(conditions),
                    "minimum": None if repeated else row.minimum,
                    "maximum": None if repeated else row.maximum,
                    "reason": reason,
                })

        walk(rows)
        packed, known, missing = [], 0, Counter()
        for item in sorted(leaves):
            paths = leaves[item]
            one = paths[0]
            probability = one["probability"] if len(paths) == 1 else None
            if len(paths) > 1:
                missing["multiple_paths"] += 1
            elif probability is None:
                missing[one["reason"] or "unknown"] += 1
            else:
                assert math.isfinite(probability) and -1e-12 <= probability <= 1 + 1e-12
                known += 1
            # "quest" means every observed path in this reference requires it.
            quest = all(path["quest"] for path in paths)
            conditions = set.union(*(path["conditions"] for path in paths))
            condition = next(iter(conditions)) if len(conditions) == 1 else None
            packed.append(encode_row(item, None if probability is None else max(0, min(100, probability * 100)), quest, condition,
                                     one["minimum"] if len(paths) == 1 else None,
                                     one["maximum"] if len(paths) == 1 else None))
        return {"packed": ";".join(packed) + (";" if packed else ""), "rowCount": len(packed),
                "knownChanceCount": known, "unknownReasons": dict(missing)}


def verify_math():
    r = Resolver({})
    def rates(rows, refs=None):
        text = (Resolver(refs).resolve(rows) if refs is not None else r.resolve(rows))["packed"]
        return {int(parts[0]): None if not parts[1] else float(parts[1])
                for parts in (line.split("|") for line in text.rstrip(";").split(";"))}
    assert rates([Row(1, 25, 0, 1, 1, 0)]) == {1: 25}
    assert rates([Row(1, 20, 1, 1, 1, 0), Row(2, 0, 1, 1, 1, 0), Row(3, 0, 1, 1, 1, 0)]) == {1: 20, 2: 40, 3: 40}
    assert rates([Row(1, -100, 0, 1, 1, 0), Row(2, 50, 0, 1, 1, 7)]) == {1: None, 2: None}
    assert rates([Row(1, 20, 1, 1, 1, 7), Row(2, 0, 1, 1, 1, 0)]) == {1: None, 2: None}
    assert rates([Row(1, 70, 1, 1, 1, 0), Row(2, 70, 1, 1, 1, 0)]) == {1: None, 2: None}
    assert rates([Row(0, 50, 0, -10, 1, 0)], {10: [Row(1, 40, 0, 1, 1, 0)]}) == {1: 20}
    assert rates([Row(0, 50, 0, -10, 2, 0)], {10: [Row(1, 40, 0, 1, 1, 0)]}) == {1: None}
    assert rates([Row(1, 10, 0, 1, 1, 0), Row(1, 0, 1, 1, 1, 0), Row(2, 0, 1, 1, 1, 0)]) == {1: None, 2: None}
    assert rates([Row(1, 10, 0, 1, 1, 0), Row(1, 20, 0, 1, 1, 0)]) == {1: None}
    print("PASS 9 probability gates: groups, residual shares, conditions, quests, repeats, overlaps", flush=True)


def main():
    started = time.monotonic()
    verify_math()
    compressed = (BASE / "ClassicDB_1_12_1_z2815.sql.gz").read_bytes()
    raw = gzip.decompress(compressed)
    sql = raw.decode("utf-8")
    dump_date = re.search(r"-- Dump completed on ([^\n]+)", sql).group(1).strip()
    items = {}
    for row in read_table(sql, "item_template"):
        item = int(row["entry"])
        items[item] = {"id": item, "name": row["name"], "quality": int(row["Quality"])}
    all_templates = {}
    rejected = Counter()
    for table in [*(v[0] for v in METHODS.values()), "reference_loot_template"]:
        templates = defaultdict(list)
        for row in read_table(sql, table):
            entry = int(row["entry"])
            value = Row(int(row["item"]), float(row["ChanceOrQuestChance"]), int(row["groupid"]),
                        int(row["mincountOrRef"]), int(row["maxcount"]), int(row["condition_id"]))
            if (value.minimum == 0 or value.group >= 128 or value.maximum > 255 or value.maximum < 1
                or (value.minimum > 0 and (value.item not in items or value.maximum < value.minimum))
                or (value.minimum < 0 and value.chance < 0)
                or (value.chance == 0 and value.group == 0)
                or (value.chance != 0 and abs(value.chance) < 0.000001)):
                rejected[table] += 1
                continue
            templates[entry].append(value)
        all_templates[table] = templates
    resolver = Resolver(all_templates["reference_loot_template"])
    tables = {}
    for method, (table, _, _) in METHODS.items():
        tables[method] = {entry: resolver.resolve(rows) for entry, rows in all_templates[table].items()}
        print(method, len(tables[method]), "templates",
              sum(t["rowCount"] for t in tables[method].values()), "expanded relations", flush=True)

    npcs = {}
    for row in read_table(sql, "creature_template"):
        links = {out_key: int(row[field]) for _, field, out_key in METHODS.values()}
        if not any(links[out_key] in tables[method] and tables[method][links[out_key]]["rowCount"]
                   for method, (_, _, out_key) in METHODS.items()):
            continue
        npc = int(row["Entry"])
        npcs[npc] = {"id": npc, "name": row["Name"], "minLevel": int(row["MinLevel"]),
                     "maxLevel": int(row["MaxLevel"]), "classification": int(row["Rank"]), **links}
    world_maps = defaultdict(set)
    for row in read_table(sql, "creature"):
        npc = int(row["id"])
        if npc in npcs:
            world_maps[npc].add(int(row["map"]))
    for npc, maps in world_maps.items():
        npcs[npc]["worldMapIDs"] = sorted(maps)  # Game map IDs, explicitly NOT uiMapIDs.

    source = {
        "key": "cmangos_classic_z2815", "name": "CMaNGOS Classic-DB z2815 (Classic-referentie)",
        "url": "https://github.com/cmangos/classic-db/blob/37eeeeb1d4c12f00ded1b542e758f71d6135d391/Full_DB/ClassicDB_1_12_1_z2815.sql.gz",
        "license": "GPL-3.0; Blizzard copyright notice retained",
        "revision": "37eeeeb1d4c12f00ded1b542e758f71d6135d391",
        "date": "2023-10-09", "dumpCompleted": dump_date,
        "gzipSHA256": hashlib.sha256(compressed).hexdigest(), "sqlSHA256": hashlib.sha256(raw).hexdigest(),
        "coreRevision": "c633638e8d08a9c2e408c93743720f5f65e420fb",
        "note": NOTE, "subsequentUpdatesApplied": False,
        "mapIdType": "worldMapIDs are old server terrain/instance map IDs; never use them as uiMapIDs",
    }
    stats = {"npcs": len(npcs), "items": len(items), "methods": {}}
    for method, (_, _, key) in METHODS.items():
        used = [tables[method][npc[key]] for npc in npcs.values() if npc[key] in tables[method]]
        stats["methods"][method] = {
            "npcs": sum(t["rowCount"] > 0 for t in used),
            "rows": sum(t["rowCount"] for t in used),
            "knownChances": sum(t["knownChanceCount"] for t in used),
        }
    stats["rejectedRows"] = dict(rejected)
    stats["referenceIssues"] = dict(resolver.invalid)
    output = {"schema": 1, "compiled": "2026-11-06", "exhaustive": False,
              "source": source, "items": items, "npcs": npcs, "tables": tables, "stats": stats}
    target = BASE / "classic_reference.json"
    target.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n")
    (BASE / "summary.json").write_text(json.dumps({"source": source, "stats": stats}, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(stats, ensure_ascii=False), flush=True)
    print(f"Wrote {target}: {target.stat().st_size:,} bytes in {time.monotonic() - started:.1f}s", flush=True)


if __name__ == "__main__":
    main()
