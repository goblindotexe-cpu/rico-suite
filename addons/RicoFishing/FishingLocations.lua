local _, F = ...
local cache = {}
local MIN_SAMPLE = 20
local FISHFRY_FIELD_NOTES = "https://www.curseforge.com/wow/addons/fishfry-forever/files/9190872"
local FOREVERDB_CATFISH = "https://www.foreverdb.app/en/forever/items/6308/raw-bristle-whisker-catfish"
local documented = {}

local function DocumentSpot(spot, itemIDs, source)
    spot.source, spot.precision = source, "documented_fishing_spot"
    for _, id in ipairs(itemIDs) do
        documented[id] = documented[id] or {}
        table.insert(documented[id], spot)
    end
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

-- Only pins marked Fishing on the Catfish item map. Its percentage is pooled across zones.
for _, spot in ipairs({
    {mapID=1456, zone="Thunder Bluff", x=0.38778812, y=0.60388273},
    {mapID=1454, zone="Orgrimmar", points={{0.69775295, 0.30002296}, {0.69644713, 0.30112582}}},
    {mapID=1442, zone="Stonetalon Mountains", points={
        {0.46230692, 0.62170744}, {0.70310390, 0.52768785}, {0.46204716, 0.61318433},
        {0.46112096, 0.60950005}, {0.46253139, 0.62157202},
    }},
    {mapID=1443, zone="Desolace", points={{0.21450734, 0.73978698}, {0.21446007, 0.74002635}}},
    {mapID=1434, zone="Stranglethorn Vale", x=0.30351150, y=0.29398620},
}) do
    DocumentSpot(spot, {6308}, FOREVERDB_CATFISH)
end

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
