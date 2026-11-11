-- Observed Forever fishing loot, adapted from EG Link (Efficient Games), CC BY 4.0.
-- A row describes a zone and client build, with no open-water or pool breakdown.
-- See SOURCES_NL.txt for collection dates, the exact revision and attribution.
local _, F = ...

local root = "https://raw.githubusercontent.com/JIVESCORP/eg-link-output-wowf/3067c6919046428152f2152fa551f44a8c215d79/data/wowf/"
local sources = {
    ["1.60.1.70790"] = root .. "1.60.1.70790/loot.json",
    ["1.60.1.70862"] = root .. "1.60.1.70862/loot.json",
    ["1.60.1.70888"] = root .. "1.60.1.70888/loot.json",
}

F.CatchRates = {
    [4603] = { -- Raw Spotted Yellowtail
        {mapID = 1434, zone = "Stranglethorn Vale", caught = 2, total = 25, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70862", source = sources["1.60.1.70862"]},
    },
    [6289] = { -- Raw Longjaw Mud Snapper
        {mapID = 1412, zone = "Mulgore", caught = 30, total = 69, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
        {mapID = 1413, zone = "The Barrens", caught = 1, total = 77, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
        {mapID = 1456, zone = "Thunder Bluff", caught = 39, total = 53, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
    },
    [6291] = { -- Raw Brilliant Smallfish
        {mapID = 1412, zone = "Mulgore", caught = 37, total = 69, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
        {mapID = 1456, zone = "Thunder Bluff", caught = 4, total = 53, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
    },
    [6303] = { -- Raw Slitherskin Mackerel
        {mapID = 1411, zone = "Durotar", caught = 46, total = 49, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
        {mapID = 1413, zone = "The Barrens", caught = 7, total = 77, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
    },
    [6308] = { -- Raw Bristle Whisker Catfish
        {mapID = 1424, zone = "Hillsbrad Foothills", caught = 3, total = 7, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70888", source = sources["1.60.1.70888"]},
        {mapID = 1456, zone = "Thunder Bluff", caught = 10, total = 53, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
    },
    [6358] = { -- Oily Blackmouth
        {mapID = 1413, zone = "The Barrens", caught = 31, total = 77, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
        {mapID = 1421, zone = "Silverpine Forest", caught = 6, total = 6, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
        {mapID = 1434, zone = "Stranglethorn Vale", caught = 3, total = 25, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70862", source = sources["1.60.1.70862"]},
    },
    [6359] = { -- Firefin Snapper
        {mapID = 1434, zone = "Stranglethorn Vale", caught = 3, total = 25, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70862", source = sources["1.60.1.70862"]},
        {mapID = 1442, zone = "Stonetalon Mountains", caught = 3, total = 42, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70862", source = sources["1.60.1.70862"]},
    },
    [6361] = { -- Raw Rainbow Fin Albacore
        {mapID = 1413, zone = "The Barrens", caught = 18, total = 77, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
    },
    [6362] = { -- Raw Rockscale Cod
        {mapID = 1434, zone = "Stranglethorn Vale", caught = 17, total = 25, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70862", source = sources["1.60.1.70862"]},
    },
    [6522] = { -- Deviate Fish
        {mapID = 1413, zone = "The Barrens", caught = 7, total = 77, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70790", source = sources["1.60.1.70790"]},
    },
    [21071] = { -- Raw Sagefish
        {mapID = 1424, zone = "Hillsbrad Foothills", caught = 8, total = 9, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70862", source = sources["1.60.1.70862"]},
        {mapID = 1442, zone = "Stonetalon Mountains", caught = 34, total = 42, method = "zone_fishing", scope = "zone",
            build = "1.60.1.70862", source = sources["1.60.1.70862"]},
    },
}
