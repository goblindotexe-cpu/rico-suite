# Rico Suite for WoW Forever

Rico Suite brings custom nameplates and unit frames, a loot browser, fishing
tools, mining tools, and a combined inventory to World of Warcraft: Forever.

| Addon | Open in game | Includes |
| --- | --- | --- |
| RicoPlates | `/rp` | Nameplates, cast alerts, party frames, quest guidance, mining, and inventory |
| RicoLoot | `/rl` | Loot tables, local observations, and item goals |
| RicoFishing | `/rf` | Fishing guide, catch tracking, and goals |

## Install and update

In WowUp, select **World of Warcraft: Forever** and choose **Get Addons →
Install from URL**. Paste the [Rico Suite repository](https://github.com/goblindotexe-cpu/rico-suite)
link. Enable **Auto Update** for Rico Suite in **My Addons**. Close WoW before
applying a release.

For a manual installation, download **RicoSuite-forever.zip** from
[Releases](https://github.com/goblindotexe-cpu/rico-suite/releases) and extract
the three folders into your WoW installation's `_forever_/Interface/AddOns`.
The Rico minimap menu opens the suite in game. Use `/ri` for the combined inventory.

## Data and credits

RicoLoot labels its Classic reference and observed Forever loot separately.
The reference describes its source database and can differ from drops on
Forever. The addon records personal observations locally in WoW's
SavedVariables.

The [optional Everloot helper](tools/README.md) refreshes public data on
Windows. It keeps its cache separate so a WowUp release can replace the addon
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
