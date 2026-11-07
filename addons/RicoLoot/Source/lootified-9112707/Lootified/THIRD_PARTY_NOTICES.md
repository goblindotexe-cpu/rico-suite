# Third-party notices

Lootified contains data, fonts and icons from the following projects.

## CMaNGOS classic-db

Quests, prerequisites, rewards, loot tables, drop chances, creatures and spawns are derived from the CMaNGOS classic-db
world database (https://github.com/cmangos/classic-db), licensed under the
GNU General Public License v3. See `LICENSE`.
The German quest titles and objectives, creature, object and item names come from its German locale files.
German item and NPC names that the game itself shows differently, the names of the new Forever items and NPCs, the
dungeon names, the titles and objectives of the new Forever quests and the German reputation and zone names were read
from a German WoW: Forever game client. The German versions of the addon's own texts (dungeon descriptions, quest
locations, source notes) were written for the addon and use these official names and the wording of the German
quest texts.

## The simulator's combat rules

The simulator (`Sim/`) follows Classic's combat rules as the CMaNGOS server reproduces them
(https://github.com/cmangos/mangos-classic, GNU General Public License v2 or later): the attack table (miss, dodge,
glancing blows, crit), armor, rage from damage, energy and pet focus regeneration, the spell hit chance, the target's
resistance from its level, crit damage, the global cooldowns, normalized weapon damage, the attack power shares of the
rogue's and the druid's finishers and of Rake, Seal of Righteousness' damage per swing, Seal of Command's proc rate and
the smaller share of spell power of spells learned before level 20. The armor of a mob
of each level (`creature_template_classlevelstats`) and which poison or imbue spell puts which enchantment on a weapon
(`spell_template`) come from the CMaNGOS classic-db. The damage of a glancing blow follows the weapon
skill panel of the WoW: Forever client. No code of either is part of the addon; the formulas are written anew in
`Sim/Engine.lua` and the spec models.

## WoW: Forever game client

Read from the WoW: Forever game client with the addon's own `/lf collect` (what only the game's server tells): the
item data (names, quality, levels, stats and the class restrictions of the item tooltips), the quests' levels, XP and
money, the English quest titles, quest objectives and NPC names where Forever changed them, the bosses' looks, and the
German and Russian names of the items, quests and NPCs.
From the game client's own tables of build 1.60.1.70205 with the game's hotfixes, read from the installed game with
wow.tools.local (https://github.com/Marlamin/wow.tools.local) in English, German and Russian: the levels, group sizes
and instance maps of the dungeons the game's group finder lists, the bosses of the dungeons and raids whose loot is
not revealed yet (from the game's achievements), the crafted items with their professions, the names of factions,
zones, places, instance maps, dungeon finder entries and reputation standings, the talents and spell names and which
spells belong to each class (for the simulator's list of what it does not play), the share of spell power the damage
of each class spell gets, every rank (`Data/SpellPower.lua`), and Holy Power's numbers per rank
(TraitDefinitionEffectPoints, CurvePoint) with the spells it improves (SpellClassOptions).

## Forever beta quest facts

Levels, rewards, XP, quest givers and the new Forever quests of the beta dungeons were collected from public
sites (wowforevertalent.com, Wowhead Forever, Zockify, Mobalytics, WoW Handbook, quissy.tv, wowforeverbuilds.com,
wowforevertalents.com, Icy Veins, Warcraft Tavern). The facts are restated; no text or data files were copied.
Dungeon entrance coordinates come from the same kind of public guides (WoW Handbook, Warcraft Tavern, Warcraft
Wiki, Wowhead). The IDs of the new Forever places and factions (used to read their German names from the game) are
the ones on their Wowhead Forever pages. Quest giver positions are the CMaNGOS spawn points, converted to map coordinates by the game.

## Dungeon maps

The dungeon maps are Blizzard's own map art, drawn from the World of Warcraft client at run time
(`Interface\WorldMap`). They are Blizzard Entertainment's property and are not included in the addon, except the map
of Wailing Caverns (see below). The floors
of each map and their edges in world coordinates come from the client tables DungeonMap, DungeonMapChunk and
WorldMapArea of World of Warcraft 4.3.4 (build 15595); which floor a boss or entrance is on was found in the
collision models (vmaps) of the same build. Both are taken from the public server data pack
https://github.com/skypeak/Maps-VMaps-DBC. The spots of the bosses and entrances are CMaNGOS classic-db creature
spawns and instance entrances (see above).

### The map of Wailing Caverns

The game client's map of Wailing Caverns is the Cataclysm one, which leaves out the eastern maze that Cataclysm removed
and Forever still has. Lootified shows Blizzard's earlier map of the dungeon instead (Wrath of the Lich King,
`Media/Maps/WailingCaverns`, converted by `pipeline/gen_fan_maps.py`). It is Blizzard Entertainment's artwork and is
not covered by this addon's GPL-3.0 license.

### Maps of the new Forever dungeons

The maps of Hall of Thanes, Ruins of Lordaeron, City of Dalaran (the Underbelly and the city) and Excavation Site:
Wetlands (`Media/Maps`) are by **Santiago Reyes**, from his project *Atlas de Azeroth: Forever*
(https://asguevara433.wixsite.com/srmaps), and are included with his permission. They are his artwork: they are
**not** covered by this addon's GPL-3.0 license and may not be reused outside Lootified without his permission. The
addon shows the credit under each of these maps. Converted to WoW textures (4 x 3 tiles of 128, DXT1) by
`pipeline/gen_fan_maps.py`; the boss and entrance spots on them were placed by hand from the dungeon guides.

## Classic look

The classic look draws some of Blizzard's own interface textures (check boxes, menu marks, drop-downs, list headers,
the close button, the Dungeon Journal's dungeon pictures) and the Friz Quadrata font from the World of Warcraft client
at run time (Russian texts use its Cyrillic version, `Fonts\FRIZQT___CYR.TTF`, in every look). They are Blizzard Entertainment's property and are not included in the addon. `Media/UI/ClassicRing.tga`
is original artwork of this addon (generated by `pipeline/gen_classic_media.py`).

## Barlow fonts

`Media/Fonts/*.ttf` are Barlow, Barlow Semi Condensed and Barlow Condensed by Jeremy Tribby.

Copyright 2017 The Barlow Project Authors (https://github.com/jpt/barlow)

Licensed under the SIL Open Font License, Version 1.1. The full license text is in `Media/Fonts/OFL.txt`.
The fonts are included unmodified.

## Phosphor Icons

The interface icons in `Media/UI/Glyphs.tga` are rendered from Phosphor Icons (https://phosphoricons.com).

MIT License

Copyright (c) 2023 Phosphor Icons

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## game-icons.net

The boss emblems in `Media/UI/Emblems.tga` (shown for bosses without a portrait) are icons from
game-icons.net (https://game-icons.net), licensed under Creative Commons Attribution 3.0
(CC BY 3.0, https://creativecommons.org/licenses/by/3.0/). They were rendered as white silhouettes on a
transparent background and scaled down; nothing else was changed.

- **Lorc** (http://lorcblog.blogspot.com): Crowned skull, Wolf head, Dragon head, Haunting, Fire silhouette,
  Crystal growth, Hood, Swap bag, Scroll unfurled, Anvil impact, Hydra, Visored helm, Bat wing, Daemon skull,
  Robot golem
- **Delapouite** (https://delapouite.com): Golem head, Dwarf face, Ogre, Brute, Kraken tentacle, Rat, Bear head,
  Shambling zombie, Carnivorous plant, Woman elf face
- **Skoll**: Cultist, Open treasure chest, Troll
- **Sbed** (http://opengameart.org/content/95-game-icons): Death skull, Lava
- **Carl Olsen** (https://twitter.com/unstoppableCarl): Spider face
- **Kier Heyl**: Dwarf helmet

