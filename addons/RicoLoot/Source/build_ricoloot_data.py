#!/usr/bin/env python3
"""Build the explicitly labelled RicoLoot reference data from licensed snapshots.

Inputs are research JSON extracted from public GPL/MIT addon source files with
`dump_source_tables.lua`. Nothing here crawls Wowhead or imports ARR addons.
"""
from __future__ import annotations
import argparse
from collections import Counter
from pathlib import Path
import hashlib
import json
import re
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
COMPILED = '2026-11-06'


class LuaReference(str):
    """Internal reference to a shared, generated loot-template table."""


def quoted(value):
    value = str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
    value = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', lambda m: '\\%03d' % ord(m[0]), value)
    return '"' + value + '"'


def lua(value):
    if isinstance(value, LuaReference):
        return str(value)
    if value is None:
        return 'nil'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, str):
        return quoted(value)
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    if isinstance(value, dict):
        return '{' + ','.join((k if isinstance(k, str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', k) else '[' + lua(k) + ']') + '=' + lua(v) for k, v in value.items()) + '}'
    raise TypeError(type(value))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, default=(HERE.parent / 'Data.lua') if HERE.name == 'Source' else ROOT / 'RicoLoot' / 'Data.lua')
    args = parser.parse_args()
    seed = json.loads((HERE / 'lootinsight-data.json').read_text(encoding='utf-8'))
    lj = json.loads((HERE / 'lootified-data.json').read_text(encoding='utf-8'))
    sql_dir = (HERE / 'cmangos') if (HERE / 'cmangos').is_dir() else HERE.parent / 'cmangos'
    sql = json.loads((sql_dir / 'classic_reference.json').read_text(encoding='utf-8'))
    sources = {
        'lootinsight_classic': {'name': 'LootInsight / CMaNGOS Classic-referentie', 'url': 'https://www.curseforge.com/wow/addons/lootinsight-forever/files/9227335', 'license': 'GPL-3.0', 'revision': 'LootInsight 2.18.0; zip sha256 60338c9dac22f6a0e19456668f639b9518b9f7f04f5f3402c637952df1d81108', 'date': '2026-10-17', 'note': 'Vooraf geladen Classic 1.12 corpse-lootrelaties, inclusief grijze items en questitems. Geen bevestiging voor Forever. Deze bron bevat geen percentages, skinning of pickpocket-tabellen.'},
        'pfquest_classic': {'name': 'pfQuest Vanilla-coördinaten via LootInsight', 'url': 'https://github.com/shagu/pfQuest', 'license': 'MIT', 'revision': 'LootInsight 2.18.0 ClassicWorldSpawns.lua', 'date': '2026-10-17', 'note': 'Exacte Classic-zonetoewijzingen; geen bewijs van actuele Forever-spawns.'},
        'lootified_forever': {'name': 'Lootified: bekende Forever-bètadrops', 'url': 'https://www.curseforge.com/wow/addons/lootified/files/9112707', 'license': 'GPL-3.0', 'revision': '1.2.0; zip sha256 6446886ad6fd9a58b5edbf4661aef3fe05970e9f131408c485d320ebf375777c', 'date': '2026-10-09', 'note': 'Gedateerde bekende Forever-bossdrops, geen volledige tabel. De gemengde bron bewijst geen algemene Forever-kans; percentages zijn daarom weggelaten.'},
    }
    sources[sql['source']['key']] = sql['source']
    zones = {}
    mobs = {}
    items = {int(i): {'id': int(i), **meta} for i, meta in seed['itemMeta'].items()}
    rank_names = {0: 'normal', 1: 'elite', 2: 'rareelite', 3: 'worldboss', 4: 'rare'}
    for ident, meta in seed['npcMeta'].items():
        if 'Only GM can see it' in meta['name']:
            continue
        npc = int(ident)
        packed = seed['npcPacked'].get(ident, '')
        ids = sorted({int(v) for v in packed.split(',') if v})
        if not ids:
            continue
        # LootInsight supplies Classic UIMapIDs. The client supplies their labels.
        maps = sorted(int(mid) for mid in seed['spawnEncoded'].get(ident, {})
                      if 1411 <= int(mid) <= 1461 and int(mid) not in (1414, 1415))
        for mid in maps:
            zones[mid] = {'id': mid, 'name': f'Map {mid}', 'uiMapID': mid,
                          'nameFromMap': True, 'provenance': 'classic_reference'}
        mob = {'id': npc, 'name': meta['name'], 'zones': maps, 'tables': [{
            'key': 'classic_corpse', 'label': 'Classic-referentie: buit', 'method': 'loot',
            'source': 'lootinsight_classic', 'provenance': 'classic_reference', 'rateKind': 'reference',
            'complete': False, 'date': '2026-10-17',
            'note': 'Vooraf geladen Classic-buit; niet geverifieerd in Forever. Ontbrekend percentage is onbekend, geen 0%.',
            # Schema 1 permits omitted trailing empty fields.
            'packed': ';'.join(str(i) for i in ids)
        }]}
        extra = lj['WorldMobs'].get(ident)
        if extra:
            mob.update(minLevel=extra[1], maxLevel=extra[2], classification=rank_names.get(extra[3], 'normal'))
        mobs[npc] = mob
    # The older SQL snapshot is a distinct source. Never paint its rates onto
    # LootInsight's newer, differently derived NPC-item relation list.
    # Share each true LootId table between creatures that use that same table.
    templates = {method: {} for method in ('loot', 'skinning', 'pickpocket')}
    template_ids = {}
    template_counts = {}
    method_fields = {'loot': 'lootId', 'skinning': 'skinningLootId', 'pickpocket': 'pickpocketLootId'}
    method_names = {'loot': 'Buit', 'skinning': 'Villen', 'pickpocket': 'Zakkenrollen'}
    sql_stats = Counter()
    supplemental_stats = Counter()
    used_items = set()
    for ident, npc in sql['npcs'].items():
        if 'Only GM can see it' in npc['name']:
            continue
        npc_id = int(ident)
        mob = mobs.setdefault(npc_id, {'id': npc_id, 'name': npc['name'], 'zones': [], 'tables': []})
        mob.update(name=npc['name'], minLevel=npc['minLevel'], maxLevel=npc['maxLevel'],
                   classification=rank_names.get(npc['classification'], 'normal'))
        previous = mob['tables']
        mob['tables'] = []
        corpse_ids = set()
        for method, field in method_fields.items():
            loot_id = int(npc.get(field, 0))
            source_table = sql['tables'][method].get(str(loot_id))
            if not source_table or not source_table['rowCount']:
                continue
            token = (method, loot_id)
            if loot_id not in templates[method]:
                rows = [row.rstrip('|') for row in source_table['packed'].split(';') if row]
                template_ids[token] = {int(row.split('|', 1)[0]) for row in rows}
                template_counts[token] = len(rows)
                templates[method][loot_id] = {
                    'key': 'classic_db_' + method + '_' + str(loot_id),
                    'label': 'Classic DB 2023 · ' + method_names[method], 'method': method,
                    'source': sql['source']['key'], 'provenance': 'classic_reference', 'rateKind': 'reference',
                    'complete': False, 'date': sql['source']['date'], 'note': sql['source']['note'],
                    'packed': ';'.join(rows),
                }
            mob['tables'].append(LuaReference('T.' + method + '[' + str(loot_id) + ']'))
            used_items.update(template_ids[token])
            sql_stats[method + 'Tables'] += 1
            sql_stats[method + 'Edges'] += source_table['rowCount']
            sql_stats[method + 'KnownChances'] += source_table['knownChanceCount']
            if method == 'loot':
                corpse_ids = template_ids[token]
        for old_table in previous:
            old_ids = {int(v.split('|', 1)[0]) for v in old_table['packed'].split(';') if v}
            extra = old_ids - corpse_ids
            if extra:
                old_table.update(key='classic_supplement', label='Classic · aanvullende relaties zonder kans',
                    note='Aanvullende corpse-lootrelaties uit LootInsight 2.18.0 (uitgave 17 oktober 2026); moment van de onderliggende Classic-import onbekend. Apart gehouden van de SQL-basiskansen. Geen bevestiging voor Forever.',
                    packed=';'.join(str(i) for i in sorted(extra)))
                mob['tables'].append(old_table)
                supplemental_stats['tables'] += 1
                supplemental_stats['edges'] += len(extra)
    # SQL metadata is the primary Classic naming source. It never supplies a
    # Forever status; new Forever IDs are added independently below.
    items.update({int(i): meta for i, meta in sql['items'].items()})
    # Terrain map IDs are not UIMapIDs. Their known instance identity can still
    # place all instance trash under a named instance without inventing a floor.
    instance_specs = {}
    for inst in lj['Instances']:
        if inst.get('era') != 'classic':
            continue
        for mid in inst.get('instanceIDs', []):
            instance_specs.setdefault(int(mid), []).append(inst)
    for npc in sql['npcs'].values():
        mob = mobs.get(npc['id'])
        if not mob:
            continue
        for mid in npc.get('worldMapIDs', []):
            specs = instance_specs.get(mid)
            if not specs:
                continue
            if len(specs) == 1:
                key, name = 'instance:' + specs[0]['key'], specs[0]['name']
            else:
                names = [i['name'] for i in specs]
                prefixes = {n.split(':', 1)[0] for n in names}
                if len(prefixes) == 1:
                    name = prefixes.pop()
                elif set(names) == {'Lower Blackrock Spire', 'Upper Blackrock Spire'}:
                    name = 'Blackrock Spire'
                else:
                    continue
                key = 'classic_instance_map:' + str(mid)
            zones[key] = {'id': key, 'name': name, 'provenance': 'classic_reference'}
            if key not in mob['zones']:
                mob['zones'].append(key)
    # Instance membership is useful even for Classic bosses; no curated filtering
    # is applied to their full loot relation table.
    new_edges = 0
    for instance in lj['Instances']:
        known = [boss for boss in instance.get('bosses', []) if boss.get('npc') and boss.get('loot')]
        if not known:
            continue
        forever = instance.get('era') == 'forever'
        key = 'instance:' + instance['key']
        zones[key] = {'id': key, 'name': instance['name'], 'provenance': 'forever_reference' if forever else 'classic_reference'}
        for boss in known:
            npc = int(boss['npc'])
            if npc not in mobs and not forever:
                continue
            mob = mobs.setdefault(npc, {'id': npc, 'name': boss['name'], 'classification': 'worldboss', 'zones': [], 'tables': []})
            if key not in mob['zones']:
                mob['zones'].append(key)
            if str(boss.get('level', '')).isdigit() and 'minLevel' not in mob:
                mob['minLevel'] = mob['maxLevel'] = int(boss['level'])
            if not forever:
                continue
            ids = list(dict.fromkeys(int(i) for i in boss['loot']))
            for i in ids:
                stat = lj['ItemStats']['items'].get(str(i), '').split('|')
                meta = lj['Items'].get(str(i), '').split('|')
                name = stat[0] or meta[0]
                if not name:
                    raise ValueError('Missing preloaded Forever item name: ' + str(i))
                items.setdefault(i, {'id': i, 'name': name})
                if len(stat) > 1 and stat[1].isdigit():
                    items[i]['quality'] = int(stat[1])
            mob['tables'].append({'key': 'forever_' + instance['key'], 'label': 'Bekende Forever-bètadrops',
                'method': 'loot', 'source': 'lootified_forever', 'provenance': 'forever_reference',
                'rateKind': 'reference', 'complete': False, 'date': '2026-10-09',
                'note': 'Bekende drops uit de Forever-bèta. Geen volledige loottabel en geen bevestigde Forever-percentages.',
                'packed': ';'.join(str(i) for i in ids)})
            new_edges += len(ids)
    # Do not ship unused item catalog entries merely to inflate the coverage.
    for mob in mobs.values():
        for tbl in mob['tables']:
            if not isinstance(tbl, LuaReference):
                used_items.update(int(v.split('|', 1)[0]) for v in tbl['packed'].split(';') if v)
    missing = used_items - set(items)
    if missing:
        raise ValueError('Loot items lack prefilled names: ' + repr(sorted(missing)))
    items = {i: meta for i, meta in items.items() if i in used_items}
    mobs = {i: mob for i, mob in mobs.items() if mob['tables']}
    supplemental_stats = Counter()
    for mob in mobs.values():
        for tbl in mob['tables']:
            if not isinstance(tbl, LuaReference) and tbl['source'] == 'lootinsight_classic':
                supplemental_stats['tables'] += 1
                supplemental_stats['edges'] += sum(bool(v) for v in tbl['packed'].split(';'))
    unknown = 'classic:unknown_zone'
    for mob in mobs.values():
        if not mob['zones']:
            mob['zones'] = [unknown]
    if any(unknown in m['zones'] for m in mobs.values()):
        zones[unknown] = {'id': unknown, 'name': 'Locatie onbekend (Classic)', 'provenance': 'classic_reference'}
    for key, zone in list(zones.items()):
        if not any(key in m['zones'] for m in mobs.values()):
            del zones[key]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    header = '-- Generated by Source/build_ricoloot_data.py; see SOURCES_NL.txt and Licenses/.\n-- Classic reference is not Forever verification. Unknown rates stay absent.\nlocal _, RL = ...\nRL.Data={schema=1,compiled=' + quoted(COMPILED) + ',exhaustive=false,sources={},zones={},mobs={},items={}}\nlocal D=RL.Data\nlocal T={loot={},skinning={},pickpocket={}}\n'
    with args.out.open('w', encoding='utf-8', newline='\n') as f:
        f.write(header)
        for key, value in sources.items(): f.write('D.sources[' + quoted(key) + ']=' + lua(value) + '\n')
        for key in sorted(zones, key=lambda x: (isinstance(x,str),str(x))): f.write('D.zones[' + lua(key) + ']=' + lua(zones[key]) + '\n')
        for key in sorted(items): f.write('D.items[' + str(key) + ']=' + lua(items[key]) + '\n')
        for method, entries in templates.items():
            for key in sorted(entries): f.write('T.' + method + '[' + str(key) + ']=' + lua(entries[key]) + '\n')
        for key in sorted(mobs): f.write('D.mobs[' + str(key) + ']=' + lua(mobs[key]) + '\n')
    license_dir = args.out.parent / 'Licenses'; license_dir.mkdir(exist_ok=True)
    for src, name in [
        ('lootinsight-9227335/LootInsight/LICENSE_GPL-3.0.txt', 'GPL-3.0.txt'),
        ('lootinsight-9227335/LootInsight/THIRD_PARTY_LICENSE_cMaNGOS.txt', 'LootInsight-CMaNGOS.txt'),
        ('lootinsight-9227335/LootInsight/PFQUEST_LICENSE.txt', 'pfQuest-MIT.txt'),
        ('lootified-9112707/Lootified/THIRD_PARTY_NOTICES.md', 'Lootified-THIRD_PARTY_NOTICES.md'),
    ]:
        shutil.copyfile(HERE / src, license_dir / name)
    for name in ('LICENSE.md', 'COPYRIGHT.md', 'AUTHORS'):
        shutil.copyfile(sql_dir / name, license_dir / ('CMaNGOS-' + name))
    counts = {'compiled': COMPILED, 'mobs': len(mobs), 'items': len(items), 'zones': len(zones),
        'classicSQL': dict(sql_stats), 'classicAdditional': dict(supplemental_stats),
        'foreverKnownBosses': sum(any(not isinstance(t, LuaReference) and t['provenance']=='forever_reference'for t in m['tables'])for m in mobs.values()),
        'foreverKnownEdges':new_edges,'fileBytes':args.out.stat().st_size,'sha256':hashlib.sha256(args.out.read_bytes()).hexdigest(),
        'unknownZoneMobs':sum(unknown in m['zones']for m in mobs.values())}
    (HERE/'data-coverage.json').write_text(json.dumps(counts,indent=2)+'\n')
    print(json.dumps(counts,indent=2))

if __name__ == '__main__':
    main()
