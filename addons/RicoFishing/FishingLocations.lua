local _, F = ...
local cache = {}
local MIN_SAMPLE = 20
local FISHFRY_FIELD_NOTES = "https://www.curseforge.com/wow/addons/fishfry-forever/files/9190872"
local FISHFRY_WHIMSYFIN = "https://www.curseforge.com/wow/addons/fishfry-forever/files/9172375"
local AZSHARA_REPORT = "https://www.wowhead.com/forever/item=6362/raw-rockscale-cod"
local FISHING_SCHOOLS = "https://wowforever.gg/en/professions/fishing/"
local FOREVERDB_ITEMS = "https://www.foreverdb.app/en/forever/items/"
local documented = {}

local function DocumentSpot(spot, itemIDs, source)
    spot.source, spot.precision = source, "documented_fishing_spot"
    for _, id in ipairs(itemIDs) do
        documented[id] = documented[id] or {}
        table.insert(documented[id], spot)
    end
end

local function DocumentItemMap(id, slug, spots)
    local source = FOREVERDB_ITEMS .. id .. "/" .. slug
    local itemIDs = {id}
    for _, spot in ipairs(spots) do DocumentSpot(spot, itemIDs, source) end
end

-- Fishing access coordinates and catches paired in GildedVellum's Forever field notes.
DocumentSpot({mapID=1439, zone="Darkshore", subzone="Southern inland water", x=0.4060, y=0.7400},
    {6291, 6289, 6308}, FISHFRY_FIELD_NOTES)
DocumentSpot({mapID=1439, zone="Darkshore", subzone="Auberdine coast", x=0.3613, y=0.4461},
    {6303, 6361}, FISHFRY_FIELD_NOTES)
DocumentSpot({mapID=1440, zone="Ashenvale", subzone="Astranaar", x=0.3598, y=0.5325},
    {6289, 6308}, FISHFRY_FIELD_NOTES)
DocumentSpot({mapID=1440, zone="Ashenvale", subzone="Mystral Lake", x=0.4891, y=0.6823},
    {6289, 6308}, FISHFRY_FIELD_NOTES)
DocumentSpot({mapID=1440, zone="Ashenvale", subzone="Coastal fishing", x=0.1464, y=0.2178},
    {6361, 6359, 6358}, FISHFRY_FIELD_NOTES)
DocumentSpot({mapID=1420, zone="Tirisfal Glades", subzone="Brightwater Lake shore", x=0.6717, y=0.5099},
    {6299, 6297}, FISHFRY_FIELD_NOTES)
DocumentSpot({mapID=1433, zone="Redridge Mountains", subzone="South of Stonewatch Keep", x=0.6077, y=0.6989},
    {251524}, FISHFRY_WHIMSYFIN)
DocumentSpot({mapID=1433, zone="Redridge Mountains", subzone="Tower of Ilgalar", x=0.7441, y=0.6240},
    {251524}, FISHFRY_WHIMSYFIN)

-- FourteeTwo's own Forever beta catch sample names this shoreline point.
DocumentSpot({mapID=1447, zone="Azshara", subzone="Coast by Eldarath", x=0.520, y=0.683},
    {4603, 6359, 6362, 13422, 13754, 13755}, AZSHARA_REPORT)

-- Published pool positions are useful even though the pool may be inactive on arrival.
DocumentSpot({mapID=1413, zone="The Barrens", subzone="Barrens oases", points={
    {0.4506, 0.2219}, {0.4547, 0.2272}, {0.4467, 0.2357}, {0.4511, 0.2364}, {0.4634, 0.3762},
}}, {6522}, FISHING_SCHOOLS)
DocumentSpot({mapID=1413, zone="The Barrens", subzone="Ratchet coast", points={
    {0.6300, 0.5237}, {0.6299, 0.5275}, {0.6306, 0.5320},
}}, {6358}, FISHING_SCHOOLS)
DocumentSpot({mapID=1424, zone="Hillsbrad Foothills", subzone="Sagefish schools", points={
    {0.6053, 0.3030}, {0.6024, 0.3193}, {0.6166, 0.3219}, {0.6080, 0.3413}, {0.7126, 0.1006},
}}, {21071}, FISHING_SCHOOLS)

-- Only points explicitly marked Fishing on the source item maps.
DocumentItemMap(6308, "raw-bristle-whisker-catfish", {
    {mapID=1456, zone="Thunder Bluff", x=0.38778812, y=0.60388273},
    {mapID=1454, zone="Orgrimmar", points={{0.69775295, 0.30002296}, {0.69644713, 0.30112582}}},
    {mapID=1442, zone="Stonetalon Mountains", points={
        {0.46230692, 0.62170744}, {0.70310390, 0.52768785}, {0.46204716, 0.61318433},
        {0.46112096, 0.60950005}, {0.46253139, 0.62157202},
    }},
    {mapID=1443, zone="Desolace", points={{0.21450734, 0.73978698}, {0.21446007, 0.74002635}}},
    {mapID=1434, zone="Stranglethorn Vale", x=0.30351150, y=0.29398620},
})
DocumentItemMap(6289, "raw-longjaw-mud-snapper", {
    {mapID=1412, zone="Mulgore", x=0.44248754, y=0.64284837},
    {mapID=1456, zone="Thunder Bluff", x=0.38778812, y=0.60388273},
    {mapID=1454, zone="Orgrimmar", points={{0.69775295, 0.30002296}, {0.69644713, 0.30112582}}},
    {mapID=1442, zone="Stonetalon Mountains", points={
        {0.46204716, 0.61318433}, {0.46209961, 0.61367726}, {0.46230692, 0.62170744},
    }},
})
DocumentItemMap(6303, "raw-slitherskin-mackerel", {
    {mapID=1413, zone="The Barrens", x=0.63906288, y=0.38780189},
    {mapID=1439, zone="Darkshore", x=0.35866964, y=0.45053226},
})
DocumentItemMap(4603, "raw-spotted-yellowtail", {
    {mapID=1434, zone="Stranglethorn Vale", x=0.30351150, y=0.29398620},
})
DocumentItemMap(6362, "raw-rockscale-cod", {
    {mapID=1434, zone="Stranglethorn Vale", points={{0.30351150, 0.29398620}, {0.26083678, 0.73132265}}},
})
DocumentItemMap(118, "minor-healing-potion", {
    {mapID=1412, zone="Mulgore", x=0.44248754, y=0.64284837},
})

function F:CanPinFishingLocation(location)
    return location ~= nil and (location.precision == "reported_catch_points" or location.precision == "documented_fishing_spot")
end

function F:GetFishingPoint(location)
    if not self:CanPinFishingLocation(location) then return end
    if self.Map:ValidPoint(location.x, location.y) then return location.x, location.y end
    for _, point in ipairs(location.points or {}) do
        local x, y = point.x or point[1], point.y or point[2]
        if self.Map:ValidPoint(x, y) then return x, y end
    end
end

function F:DescribeFishingLocation(location)
    if location.precision == "reported_catch_points" then return "Wowhead catch report" end
    if location.precision == "documented_fishing_spot" then return "Documented fishing spot" end
    if location.precision == "approximate_1_percent_source_observation_grid" then return "Approximate catch area" end
    if location.observed then return "Forever catch report • area only" end
    if location.rate then return "Forever zone reports" end
    return "Wowhead zone reference"
end

function F:FormatFishingRate(location)
    local rate = location.rate
    if not rate then return end
    local sample = rate.total < MIN_SAMPLE and " • small sample" or ""
    return ("Forever zone %.1f%% (%d/%d)%s"):format(rate.caught / rate.total * 100, rate.caught, rate.total, sample)
end

local function Rank(location)
    local base = F:CanPinFishingLocation(location) and 0 or 3
    if not location.rate then return base + 3 end
    return base + (location.rate.total >= MIN_SAMPLE and 1 or 2)
end

function F:GetFishingLocations(entry)
    if not entry then return {} end
    if cache[entry.id] then return cache[entry.id] end
    local rates = self.CatchRates and self.CatchRates[entry.id] or {}
    local locations, zoneRates, matched, order = {}, {}, {}, {}
    local function Add(location)
        locations[#locations + 1] = location
        order[location] = #locations
    end
    for _, rate in ipairs(rates) do zoneRates[rate.mapID] = rate end
    for _, location in ipairs(entry.locations or {}) do
        local rate = zoneRates[location.mapID]
        if rate then
            local withRate = {}
            for key, value in pairs(location) do withRate[key] = value end
            withRate.rate = rate
            Add(withRate)
            matched[location.mapID] = true
        else
            Add(location)
        end
    end
    for _, spot in ipairs(documented[entry.id] or {}) do
        local location = {}
        for key, value in pairs(spot) do location[key] = value end
        location.rate = zoneRates[spot.mapID]
        matched[spot.mapID] = true
        Add(location)
    end
    for _, rate in ipairs(rates) do
        if not matched[rate.mapID] then
            Add({mapID=rate.mapID,zone=rate.zone,precision="zone_only",rate=rate})
        end
    end
    table.sort(locations, function(a, b)
        local first, second = Rank(a), Rank(b)
        if first ~= second then return first < second end
        if a.rate then
            local ar, br = a.rate.caught / a.rate.total, b.rate.caught / b.rate.total
            if ar ~= br then return ar > br end
            if a.rate.total ~= b.rate.total then return a.rate.total > b.rate.total end
        end
        return order[a] < order[b]
    end)
    cache[entry.id] = locations
    return locations
end
