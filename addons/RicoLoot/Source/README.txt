RicoLoot data reproduction

This directory contains the complete normalized input tables used by the base
Data.lua generator, the generator itself, the source notices and pinned input
URLs/checksums. It deliberately contains no All Rights Reserved addon, no
Wowhead page snapshots, no game artwork and no private observations.

Requirements: Python 3.10 or newer; Python standard library only.

From this addon directory, rebuild the base database with:
    python3 Source/build_ricoloot_data.py

From another directory:
    python3 /path/to/RicoLoot/Source/build_ricoloot_data.py --out /path/to/RicoLoot/Data.lua

DataObserved.lua is separate; rebuilding Data.lua does not replace its distinct
Forever observation cohorts. Its source/attribution is listed in that file and
in the addon's source notices.

Input formats
- lootinsight-data.json: ReferenceData.lua NPC names, packed item relationships,
  item names/qualities and ClassicWorldSpawns.lua's exact NPC-to-map coordinates.
  Derived from the pinned, GPL-3.0 LootInsight release; pfQuest coordinates MIT.
- lootified-data.json: the Lootified 1.2.0 Data tables, exported without its UI,
  modules, simulator or artwork. Classic mob metadata and instance membership
  remain Classic. Only explicitly new Forever instances with known NPC/item IDs
  add a separate dated Forever reference table, with no imported probabilities.
- Outdoor zone IDs come from LootInsight's supplied Classic world spawn IDs.
  The running game resolves their display names with C_Map.GetMapInfo.
- cmangos/classic_reference.json: normalized corpse, skinning and pickpocket
  templates from the pinned Classic 1.12 z2815 snapshot, preserving the real
  creature-template LootId links. The included cmangos/build_reference.py
  shows the SQL parsing and conservative probability resolution. It requires
  the upstream SQL gzip named and hashed in cmangos/snapshot-info.json to
  regenerate this input. The gzip is not necessary to rebuild Data.lua from
  the complete normalized tables already supplied here.

The normalizer isolated upstream Lua data tables in a restricted Lua environment
with no OS, I/O, network, package-loader or WoW APIs. No addon UI code was run.

Transformation rules
- Only the literal 'Only GM can see it' development marker is excluded. Missing
  static spawn coordinates do not exclude a potentially scripted creature.
- SQL probabilities belong exclusively to the dated SQL tables. Their rows are
  not merged with or reattributed to another source's relationship snapshot.
- Additional LootInsight corpse relations are retained in a separate table with
  unknown probability. If the same relationship exists in the SQL table, that
  relationship is already available there and is not duplicated in the extra
  table. This is not proof of equal rates between the two source snapshots.
- Quest, condition, overlap, repeated-roll and dependent-pool cases that the
  conservative resolver cannot establish keep their items but no numeric rate.
- Creature terrain map IDs are used only to identify a known instance. They are
  never presented as live UIMapIDs or converted into guessed zone positions.
- Shared LootIds share one immutable source table in Data.lua. Packed rows are
  decoded by the main addon only when the user opens a table.
- Empty trailing fields are omitted from packed rows; no input values are lost.
- Unknown locations remain 'Locatie onbekend (Classic)'.

See input-manifest.json for every included input's SHA-256 and source URLs.
See ../SOURCES_NL.txt and ../Licenses for the practical data limits and licenses.
