local _, F = ...
local cache = {}
local MIN_SAMPLE = 20

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
    if not location.rate then return 3 end
    return location.rate.total >= MIN_SAMPLE and 1 or 2
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
