-- Read the active quest log without changing the player's watch list or selection.
local _, RP = ...
local T = { destinations = {} }
RP.QuestTrackerData = T

local DESTINATION_REFRESH = 10

local function Call(fn, ...)
    if type(fn) == "function" then return pcall(fn, ...) end
    return false
end

local function Read(fn, ...)
    local ok, value = Call(fn, ...)
    if ok and RP.Readable(value) then return value end
end

local function Table(value)
    return RP.Readable(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function Number(value)
    return RP.Readable(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

local function Count(value)
    if Number(value) and value >= 0 and value % 1 == 0 then return value end
end

local function ID(value)
    return Count(value) and value > 0
end

local function Text(value)
    if RP.Readable(value) and type(value) == "string" and value ~= "" then return value end
end

local function Objectives(api, id)
    local result = {}
    local objectives = Read(api.GetQuestObjectives, id)
    if Table(objectives) then
        for _, objective in ipairs(objectives) do
            local text = Table(objective) and Text(objective.text)
            if text then
                result[#result + 1] = {
                    text = text, finished = RP.PublicTrue(objective.finished),
                    fulfilled = Count(objective.numFulfilled), required = Count(objective.numRequired),
                }
            end
        end
    end
    return result
end

local function ReadLog()
    local api = C_QuestLog or {}
    local entries, seen = {}, {}
    local ok, shown, total = Call(api.GetNumQuestLogEntries)
    if not ok or not Count(shown) then return entries, 0 end
    total = Count(total)
    -- Collapsed headers can leave active entries beyond the shown-entry count.
    for index = 1, shown + (total or 0) do
        local got, info = Call(api.GetInfo, index)
        if index > shown and (not got or (RP.Readable(info) and info == nil)) then break end
        if got and Table(info) and RP.Readable(info.isHeader) and not info.isHeader
            and RP.Readable(info.isHidden) and not info.isHidden
            and RP.Readable(info.isInternalOnly) and not info.isInternalOnly then
            local id = info.questID
            if ID(id) and not seen[id] and Read(api.IsOnQuest, id) ~= false then
                seen[id] = true
                entries[#entries + 1] = {
                    id = id, order = index,
                    title = Text(info.title) or Text(Read(api.GetTitleForQuestID, id)) or ("Quest " .. id),
                    complete = RP.PublicTrue(Read(api.IsComplete, id)), objectives = Objectives(api, id),
                }
            end
        end
    end
    return entries, math.max(total or 0, #entries)
end

local function WorldPoint(map, x, y)
    if not ID(map) or not Number(x) or not Number(y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
    local vector = Read(CreateVector2D, x, y)
    if not vector then return end
    local ok, continent, point = Call(C_Map and C_Map.GetWorldPosFromMapPos, map, vector)
    if ok and Number(continent) and Table(point) and Number(point.x) and Number(point.y) then
        return { continent = continent, x = point.x, y = point.y }
    end
end

local function PlayerWorld(map)
    if not ID(map) then return end
    local position = Read(C_Map and C_Map.GetPlayerMapPosition, map, "player")
    if Table(position) then return WorldPoint(map, position.x, position.y) end
end

local function DirectDistance(id)
    local ok, squared, sameContinent = Call(C_QuestLog and C_QuestLog.GetDistanceSqToQuest, id)
    if ok and RP.PublicTrue(sameContinent) and Number(squared) and squared >= 0 then
        return math.sqrt(squared)
    end
end

local function ResolveDestination(id)
    local routes = RP.QuestRoutes
    local point = routes and Read(routes.ResolveQuest, routes, id)
    if Table(point) then
        local world = WorldPoint(point.map, point.x, point.y)
        if world then return world end
    end
    local ok, map, x, y = Call(C_QuestLog and C_QuestLog.GetNextWaypoint, id)
    if ok then return WorldPoint(map, x, y) end
end

function T:Invalidate()
    self.entries = nil
    self.destinations = {}
end

function T:Refresh()
    if not self.entries then self.entries, self.total = ReadLog() end
    local map = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    if not ID(map) then map = nil end
    local now = Read(GetTime)
    if not Number(now) then now = 0 end
    local useQuestie = RP.db and RP.db.useQuestie ~= false
    if self.map ~= map or self.useQuestie ~= useQuestie or not self.refreshAt or now >= self.refreshAt then
        self.map, self.useQuestie, self.refreshAt = map, useQuestie, now + DESTINATION_REFRESH
        self.destinations = {}
    end
    local playerWorld
    for _, entry in ipairs(self.entries) do
        entry.distance = DirectDistance(entry.id)
        if entry.distance == nil then
            if playerWorld == nil then playerWorld = PlayerWorld(map) or false end
            if playerWorld then
                local destination = self.destinations[entry.id]
                if destination == nil then
                    destination = ResolveDestination(entry.id) or false
                    self.destinations[entry.id] = destination
                end
                if destination and destination.continent == playerWorld.continent then
                    local dx, dy = destination.x - playerWorld.x, destination.y - playerWorld.y
                    entry.distance = math.sqrt(dx * dx + dy * dy)
                end
            end
        end
    end
    table.sort(self.entries, function(a, b)
        local first, second = a.distance or math.huge, b.distance or math.huge
        if first == second then return a.order < b.order end
        return first < second
    end)
    return self.entries, self.total
end
