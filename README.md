# Rico Suite for WoW Forever

Rico Suite brings custom nameplates and unit frames, a loot browser, fishing
tools, mining tools, and a combined inventory to World of Warcraft: Forever.

| Addon | Open in game | Includes |
| --- | --- | --- |
| RicoPlates | `/rp` | Nameplates, cast alerts, healing previews, party frames, square minimap, quest guidance, mining, and inventory |
| RicoLoot | `/rl` | Loot tables, local observations, and item goals |
| RicoFishing | `/rf` | One-Key Fishing on **F**, per-character catch log, fishing guide, and goals |

## Install and update

1. Download **RicoSuite-forever.zip** from
   [Releases](https://github.com/goblindotexe-cpu/rico-suite/releases).
2. Close WoW and extract the three folders into your WoW installation's
   `_forever_/Interface/AddOns`.
3. Start WoW and open the Rico minimap menu. Use `/ri` for the combined inventory.

To update, repeat the first two steps with the latest release.

For One-Key Fishing, equip a fishing pole. Press **F** to cast, press **F** at
the splash to reel in and collect the catch, then press **F** to cast again.
Open `/rf log` to browse the current and previous sessions. Open `/rp minimap`
to configure the square minimap, clock, and additional area overview.

## Data and credits

RicoLoot labels its Classic reference and observed Forever loot separately.
The reference describes its source database and can differ from drops on
Forever. The addon records personal observations locally in WoW's
SavedVariables.

The [optional Everloot helper](tools/README.md) refreshes public data on
Windows. It keeps its cache separate so addon releases can replace the addon
files without losing the latest downloaded snapshot.

License and source notices live with the components they cover. RicoPlates
includes Shortest Path Forever, and its mining reference includes GatherMate2
Data. See the notices in the RicoPlates folder. RicoFishing includes a
GatherLite notice. RicoLoot's source notes document the imported Classic and
Forever loot sources and the corresponding build inputs.

Data from [Everloot](https://everloot.app), CC BY-SA 4.0.

## Build

Run `python package_release.py` from the repository root. The build writes
`dist/RicoSuite-forever.zip`. Stable tags in the format `vMAJOR.MINOR.PATCH`
build and publish the bundle through GitHub Actions. The project website
source lives in `docs/`.
