local addonName, RP = ...
local S = { status = "idle", categories = {} }
RP.Services = S

local catalog = {
    { "mail", "Mailboxes" },
    { "bank", "Banks", "BANKER" },
    { "inn", "Inns & taverns", "INNKEEPER" },
    { "auction", "Auction houses", "AUCTIONEER" },
    { "repair", "Repairs", "REPAIR" },
    { "vendor", "Vendors", "VENDOR" },
    { "trainer", "Trainers", "TRAINER" },
    { "flight", "Flight masters", "FLIGHT_MASTER" },
    { "stable", "Stable masters", "STABLEMASTER" },
    { "pvp", "Battlemasters", "BATTLEMASTER" },
    { "guild", "Guild services", "PETITIONER", "TABARD_DESIGNER" },
    { "barber", "Barbers", "BARBER" },
    { "transmog", "Transmogrifiers", "TRANSMOGRIFIER" },
    { "spirit", "Spirit healers", "SPIRIT_HEALER", "SPIRIT_GUIDE" },
}
local iconPath = "Interface\\AddOns\\" .. addonName .. "\\Media\\Services\\"
for _, row in ipairs(catalog) do
    S.categories[row[1]] = { label = row[2], icon = iconPath .. row[1] }
end

local empty = {}
local unpack = unpack or table.unpack
local band = bit and bit.band or bit32 and bit32.band
local factions = { A = "Alliance", H = "Horde" }

local function Table(value)
    return type(value) == "table" and (not issecretvalue or not issecretvalue(value))
        and (not canaccesstable or canaccesstable(value))
end

local function Read(func, ...)
    if type(func) ~= "function" then return end
    local ok, result = pcall(func, ...)
    if ok and (not issecretvalue or not issecretvalue(result)) then return result end
end

-- QuestieDB publishes these four support tables as text containing numeric assignments.
local function NumericMapping(source)
    if Table(source) then return source end
    local result = {}
    if type(source) == "string" then
        for line in source:gmatch("[^\r\n]+") do
            local area, target = line:match("^%s*%[(%d+)%]%s*=%s*(%d+)%s*[,}]?")
            if area then result[tonumber(area)] = tonumber(target) end
        end
    end
    return result
end

local function ResolveMap(area, direct, aliases, parents, parentAliases, cache)
    if cache[area] ~= nil then return cache[area] end
    local map, current = nil, area
    for _ = 1, 12 do
        if type(current) ~= "number" then break end
        map = aliases[current] or direct[current]
        if map ~= nil then break end
        current = parentAliases[current] or parents[current]
    end
    cache[area] = type(map) == "number" and map > 0 and Read(C_Map and C_Map.GetMapInfo, map) and map or false
    return cache[area]
end

local function QuestieMailboxes()
    local loader = rawget(_G, "QuestieLoader")
    local townsfolk = Table(loader) and Read(loader.ImportModule, loader, "Townsfolk")
    local ids = Table(townsfolk) and Read(townsfolk.GetMailboxes)
    local known = {}
    for _, id in ipairs(Table(ids) and ids or empty) do known[id] = true end
    return known
end

local function BuildIndex(lib, zone, index)
    local direct, aliases = NumericMapping(zone.areaIdToUiMapId), NumericMapping(zone.areaIdToUiMapIdOverride)
    local parents, parentAliases = NumericMapping(zone.subZoneToParentZone), NumericMapping(zone.subZoneToParentZoneOverride)
    local knownMaps, seen = {}, {}
    local function Add(spawns, kinds, name, faction, id, detail)
        if not Table(spawns) then return end
        for area, points in pairs(spawns) do
            local map = ResolveMap(area, direct, aliases, parents, parentAliases, knownMaps)
            if map and Table(points) then
                local entries = index[map]
                if not entries then entries = {}; index[map] = entries end
                for _, point in ipairs(points) do
                    local x, y = point[1], point[2]
                    if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                        for _, kind in ipairs(kinds) do
                            local key = ("%d:%s:%d:%.2f:%.2f"):format(map, kind, id, x, y)
                            if not seen[key] then
                                seen[key] = true
                                entries[#entries + 1] = { map = map, x = x / 100, y = y / 100, kind = kind,
                                    name = name, faction = faction, id = id, detail = detail }
                            end
                        end
                    end
                end
            end
        end
    end

    local npc, objects = lib.Npc, lib.Object
    local flags = lib.Enum and lib.Enum.npcFlags or empty
    local fields = { "name", "subName", "spawns", "friendlyToFaction" }
    if npc and band then
        local ids = npc.GetAllIds()
        for _, id in ipairs(ids) do
            local mask = npc.npcFlags(id)
            if type(mask) == "number" and mask ~= 0 then
                local kinds = {}
                for _, row in ipairs(catalog) do
                    local primary, secondary = flags[row[3]], flags[row[4]]
                    if (primary and band(mask, primary) ~= 0) or (secondary and band(mask, secondary) ~= 0) then
                        kinds[#kinds + 1] = row[1]
                    end
                end
                if #kinds > 0 then
                    local values = npc.GetAll(id, fields)
                    if values then
                        local name, detail, spawns, faction = unpack(values, 1, values.n or #fields)
                        if type(name) == "string" and name ~= "" then
                            Add(spawns, kinds, name, factions[faction], id, detail)
                        end
                    end
                end
            end
            coroutine.yield()
        end
    end

    if objects then
        local known, mailKind = QuestieMailboxes(), { "mail" }
        for _, id in ipairs(objects.GetAllIds()) do
            local name = Read(objects.GetRaw, id, "name") or Read(objects.name, id)
            if known[id] or (type(name) == "string" and name:lower():find("mailbox", 1, true)) then
                Add(objects.spawns(id), mailKind, Read(objects.name, id) or "Mailbox", nil, id)
            end
            coroutine.yield()
        end
    end
end

local function EncodeSelection(selection)
    local selected = {}
    for _, row in ipairs(catalog) do
        if selection[row[1]] then selected[#selected + 1] = row[1] end
    end
    if #selected == 0 then return "off", 0 end
    if #selected == #catalog then return "all", #catalog end
    return table.concat(selected, ","), #selected
end

function S:GetFilter()
    local saved = RP.db and RP.db.serviceMapFilter
    if self.selection and self.selectionSource == saved then return self.filter end
    local selection = {}
    if type(saved) == "string" and saved ~= "all" and saved ~= "off" then
        for id in saved:gmatch("[^,]+") do
            if self.categories[id] then selection[id] = true end
        end
    end
    if saved ~= "off" and not next(selection) then
        for _, row in ipairs(catalog) do selection[row[1]] = true end
    end
    self.selectionSource, self.selection = saved, selection
    self.filter, self.selectedCount = EncodeSelection(selection)
    return self.filter
end

function S:IsFilterSelected(id)
    local filter = self:GetFilter()
    if id == "all" or id == "off" then return id == filter end
    return self.selection[id] == true
end

function S:GetSelectedCount()
    self:GetFilter()
    return self.selectedCount
end

function S:SetFilter(filter)
    if not RP.db or (filter ~= "all" and filter ~= "off" and not self.categories[filter]) then return false end
    local previous = self:GetFilter()
    if self.categories[filter] then
        self.selection[filter] = not self.selection[filter] or nil
        filter = EncodeSelection(self.selection)
    end
    if filter == previous then return true end
    RP.db.serviceMapFilter = filter
    self:GetFilter()
    RP.appliedServiceMapFilter = filter
    if RP.ServicesMap then RP.ServicesMap:Refresh() end
    return true
end

function S:GetStatus()
    return self.status
end

function S:SetStatus(status)
    self.status = status
    if RP.ServicesMenu then RP.ServicesMenu:Refresh() end
end

function S:EnsureIndex()
    if self.status ~= "idle" then return end
    local lib = rawget(_G, "LibQuestieDB")
    if not Table(lib) then self:SetStatus("missing"); return end
    local zones = Table(lib.Support) and Read(lib.Support.Get, "ZoneDB")
    if not Table(zones) or not Table(zones.private) then self:SetStatus("unavailable"); return end

    local index = {}
    self:SetStatus("loading")
    local job = coroutine.create(function() BuildIndex(lib, zones.private, index) end)
    local function Pump()
        if InCombatLockdown and InCombatLockdown() then C_Timer.After(0.25, Pump); return end
        local started = debugprofilestop and debugprofilestop()
        for _ = 1, 192 do
            local ok = coroutine.resume(job)
            if not ok then self:SetStatus("unavailable"); return end
            if coroutine.status(job) == "dead" then
                self.index, self.cache = index, {}
                self:SetStatus("ready")
                if RP.ServicesMap then RP.ServicesMap:Refresh() end
                return
            end
            if started and debugprofilestop() - started >= 1.5 then break end
        end
        C_Timer.After(0, Pump)
    end
    C_Timer.After(0, Pump)
end

function S:GetPoints(map)
    local filter = self:GetFilter()
    if filter == "off" or type(map) ~= "number" then return empty end
    if not self.index then self:EnsureIndex(); return empty end
    local cached = self.cache[map]
    if cached and cached.filter == filter then return cached.points end

    local points = {}
    local miningMap = RP.Mining and RP.Mining.Map
    if miningMap and not self.projector then self.projector = setmetatable({}, { __index = miningMap }) end
    local projector = self.projector
    for origin, entries in pairs(self.index) do
        if origin == map or (projector and projector:WorldSourceAllowed(origin, map)) then
            for _, point in ipairs(entries) do
                if self.selection[point.kind] then
                    if origin == map then
                        points[#points + 1] = point
                    else
                        local x, y = projector:Project(point, map)
                        if x and y then
                            points[#points + 1] = { x = x, y = y, kind = point.kind, name = point.name, id = point.id,
                                faction = point.faction, detail = point.detail, map = map,
                                sourceMap = origin, sourceX = point.x, sourceY = point.y }
                        end
                    end
                end
            end
        end
    end
    self.cache[map] = { filter = filter, points = points }
    return points
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, addon)
    if addon == "QuestieDB" and (S.status == "missing" or S.status == "unavailable") then
        S:SetStatus("idle")
        if RP.ServicesMap then RP.ServicesMap:Refresh() end
    end
end)
