-- User-selected quest destinations, routed by the terrain-checked SPF bridge.
-- No movement automation, shared-player messages, or straight-line fallback.
local _, RP = ...
local Q = { owner = "RicoPlates", state = "idle", message = "Choose a quest to plan its route." }
RP.QuestRoutes = Q
local function Public(value) return not (RP.IsSecret and RP.IsSecret(value)) end
local function Table(value) return Public(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value)) end
local function Number(value) return Public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge end
local function String(value) return Public(value) and type(value) == "string" end
local function Field(object, key)
    if not Table(object) and not (Public(object) and type(object) == "userdata") then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok and Public(value) then return value end
end
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and Public(value) then return value end
end
local function ProviderRead(label, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then
        Q.lastProviderError = label .. ": " .. (String(value) and value or "Unknown navigation error")
    elseif Public(value) then return value end
end
local function Combat() return Read(InCombatLockdown) == true end
local function ID(value) return Number(value) and value > 0 and value == math.floor(value) and value < 2147483648 end
local function Point(map, x, y)
    return ID(map) and Number(x) and Number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end
local function Enabled() return RP.db and RP.db.enabled ~= false and RP.db.questRoutes ~= false end

function Q:Provider()
    local provider = rawget(_G, "ShortestPathForever")
    local api, bridge = Field(provider, "API"), Field(provider, "RicoRoutes")
    if not Table(api) or Field(api, "version") ~= 1 or type(Field(api, "NavigateRoute")) ~= "function"
        or type(Field(api, "Cancel")) ~= "function" or type(Field(api, "CurrentStop")) ~= "function"
        or type(Field(api, "Active")) ~= "function" then
        return nil, nil, "Navigation is not ready. Use /reload to load RicoPlates navigation."
    end
    if not Table(bridge) or Field(bridge, "version") ~= 1 or Field(bridge, "providerVersion") ~= "v1.22.38"
        or type(Field(bridge, "GetStatus")) ~= "function" or type(Field(bridge, "CanStart")) ~= "function" then
        return nil, nil, "The terrain-verification bridge is missing or unsupported. No route was started."
    end
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local embedded = Field(provider, "RicoEmbedded")
    local hosted = Field(embedded, "host") == "RicoPlates" and Field(embedded, "version") == bridge.providerVersion
    if not hosted and type(metadata) == "function" then
        local version = Read(metadata, "ShortestPathForever", "Version")
        if String(version) and version ~= bridge.providerVersion then
            return nil, nil, "The navigation addon was updated without its compatible terrain-verification bridge."
        end
    end
    return api, bridge
end

local function Questie()
    if RP.db and RP.db.useQuestie == false then return nil end
    local questie = rawget(_G, "Questie")
    local api = Field(questie, "API")
    if Field(api, "isReady") ~= true then return nil end
    local loader = rawget(_G, "QuestieLoader")
    local import = Field(loader, "ImportModule")
    local db, zones = Read(import, loader, "QuestieDB"), Read(import, loader, "ZoneDB")
    if Table(db) and Table(zones) then return db, zones end
end

local function AddSpawns(candidates, spawns, zones)
    if not Table(spawns) then return end
    if not candidates.context then
        local map = Read(C_Map and C_Map.GetBestMapForUnit, "player")
        local position = ID(map) and Read(C_Map and C_Map.GetPlayerMapPosition, map, "player")
        candidates.context = {map=map,x=Field(position,"x"),y=Field(position,"y")}
        candidates.inspected = 0
    end
    local context = candidates.context
    local areas = {}
    local areaCount = 0
    for area, points in pairs(spawns) do
        areaCount = areaCount + 1
        if areaCount > 100 then break end
        if ID(area) and Table(points) then
            local map = Read(Field(zones, "GetUiMapIdByAreaId"), zones, area)
            if ID(map) then areas[#areas+1] = {area=area,map=map,points=points} end
        end
    end
    table.sort(areas, function(a,b)
        if (a.map==context.map) ~= (b.map==context.map) then return a.map==context.map end
        return a.area < b.area
    end)
    for _, area in ipairs(areas) do
        for index = 1, math.min(#area.points, 64) do
                    if candidates.inspected >= 1024 then return end
                    candidates.inspected = candidates.inspected + 1
                    local coordinates = area.points[index]
                    local x, y = Field(coordinates, 1), Field(coordinates, 2)
                    if Number(x) and Number(y) and Point(area.map, x / 100, y / 100) then
                        local point = { map=area.map, x=x/100, y=y/100 }
                        point.rank = area.map == context.map and Number(context.x) and Number(context.y)
                            and ((point.x-context.x)^2 + (point.y-context.y)^2) or (area.map==context.map and 1 or 2)
                        if #candidates < 64 then candidates[#candidates+1] = point
                        else
                            local worst = 1
                            for at=2,#candidates do if candidates[at].rank > candidates[worst].rank then worst=at end end
                            if point.rank < candidates[worst].rank then candidates[worst] = point end
                        end
                    end
        end
    end
end

local function Nearest(candidates)
    local map = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    local position = ID(map) and Read(C_Map and C_Map.GetPlayerMapPosition, map, "player")
    local x, y = Field(position, "x"), Field(position, "y")
    if position and (not Number(x) or not Number(y)) and type(Field(position, "GetXY")) == "function" then
        local ok, px, py = pcall(position.GetXY, position)
        if ok and Number(px) and Number(py) then x, y = px, py end
    end
    local best, score
    for index, candidate in ipairs(candidates) do
        local value = candidate.map == map and Number(x) and Number(y)
            and ((candidate.x - x)^2 + (candidate.y - y)^2) or 2 + index / 1000
        if not score or value < score then best, score = candidate, value end
    end
    return best
end

-- Blizzard's QuestDataProvider uses map POIs and GetNextWaypointForMap too.
-- GetNextWaypoint alone can be empty even while the quest has a visible map pin.
local function NativeDestination(questID, title, complete)
    local api = C_QuestLog or {}
    local waypoint
    local maps, seen = {}, {}
    local function AddMap(map)
        if ID(map) and not seen[map] and #maps < 8 then
            seen[map], maps[#maps + 1] = true, map
        end
    end
    AddMap(Read(GetQuestUiMapID, questID, true))
    if type(api.GetNextWaypoint) == "function" then
        local ok, map, x, y = pcall(api.GetNextWaypoint, questID)
        if ok then
            AddMap(map)
            if Point(map, x, y) then waypoint = {map=map,x=x,y=y,source="Game quest waypoint"} end
        end
    end
    -- An unfinished quest's waypoint can be an intermediate entrance or portal.
    if waypoint and complete ~= true then
        waypoint.title, waypoint.kind = title, "quest"
        return waypoint
    end
    AddMap(Read(C_Map and C_Map.GetBestMapForUnit, "player"))
    AddMap(Read(api.GetMapForQuestPOIs))
    -- Starter micro-maps do not always carry their parent zone's quest markers.
    local index = 1
    while index <= #maps and index <= 8 do
        local info = Read(C_Map and C_Map.GetMapInfo, maps[index])
        AddMap(Field(info, "parentMapID"))
        index = index + 1
    end
    local mapWaypoint, marker
    for _, map in ipairs(maps) do
        local pois = Read(api.GetQuestsOnMap, map)
        if Table(pois) then
            for at = 1, math.min(#pois, 250) do
                local poi = pois[at]
                local x, y = Field(poi, "x"), Field(poi, "y")
                local current = Read(function()
                    return Table(poi) and Public(poi.isQuestStart) and poi.isQuestStart ~= true
                end)
                if current == true and Field(poi, "questID") == questID and Point(map, x, y) then
                    -- POI x/y belong to the queried map, including child-map POIs.
                    marker = marker or {map=map,x=x,y=y,title=title,source="Game quest map marker",kind=complete and "turnin" or "quest"}
                    if complete == true then return marker end
                end
            end
        end
        if not mapWaypoint and type(api.GetNextWaypointForMap) == "function" then
            local ok, x, y = pcall(api.GetNextWaypointForMap, questID, map)
            if ok and Point(map, x, y) then mapWaypoint = {map=map,x=x,y=y,source="Game quest map waypoint"} end
        end
    end
    local result = waypoint or mapWaypoint or marker
    if result then result.title, result.kind = title, complete and "turnin" or "quest"; return result end
end

function Q:ResolveQuest(questID)
    if not ID(questID) then return nil, "Choose a quest from your quest log." end
    local title = Read(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID)
    if not String(title) or title == "" then title = "Quest " .. questID end
    local complete = Read(C_QuestLog and C_QuestLog.IsComplete, questID)
    local db, zones = Questie()
    if db then
        local quest = Read(Field(db, "GetQuest"), questID)
        local candidates = {}
        if Table(quest) then
            if complete == nil then complete = Read(Field(quest, "IsComplete"), quest) == 1 end
            if complete == true then
                local finisher = Field(quest, "Finisher")
                for _, descriptor in ipairs({ {"NPC", "QueryNPCSingle"}, {"GameObject", "QueryObjectSingle"} }) do
                    local ids = Field(finisher, descriptor[1])
                    if Table(ids) then
                        for index = 1, math.min(#ids, 32) do
                            local id = ids[index]
                            if ID(id) then AddSpawns(candidates, Read(Field(db, descriptor[2]), id, "spawns"), zones) end
                            if (candidates.inspected or 0) >= 1024 then break end
                        end
                    end
                end
            else
                local objectives = Field(quest, "Objectives")
                if Table(objectives) then
                    for index = 1, math.min(#objectives, 24) do
                        local objective = objectives[index]
                        if Field(objective, "Completed") == false then
                            local list = Field(objective, "spawnList")
                            if Table(list) then
                                local examined = 0
                                for _, spawn in pairs(list) do
                                    examined = examined + 1
                                    if examined > 32 then break end
                                    AddSpawns(candidates, Field(spawn, "Spawns"), zones)
                                    if (candidates.inspected or 0) >= 1024 then break end
                                end
                            end
                        end
                        if (candidates.inspected or 0) >= 1024 then break end
                    end
                end
            end
        end
        local point = Nearest(candidates)
        if point then point.title, point.source, point.kind = title, "Questie", complete and "turnin" or "quest"; return point end
    end
    local point = NativeDestination(questID, title, complete)
    if point then return point end
    return nil, "The game has no readable location for this quest yet. Questie is optional. Place a map pin and choose Navigate map pin to select a destination yourself."
end

function Q:StartQuest(questID)
    if not Enabled() then return false, "Enable quest routes in RicoPlates settings first." end
    if Combat() then return false, "Finish combat before planning a quest route." end
    if not ID(questID) then questID = Read(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) end
    if not ID(questID) then return false, "Choose a quest from your quest log." end
    local onQuest = Read(C_QuestLog and C_QuestLog.IsOnQuest, questID)
    if onQuest == false then return false, "That quest is no longer in your quest log." end
    local api, bridge, reason = self:Provider()
    if not api then self.state, self.message = "missing_provider", reason; return false, reason end
    local active = ProviderRead("Active", api.Active)
    if type(active) ~= "boolean" then return false, "The navigation provider's ownership state is unavailable." end
    if Read(bridge.CanStart, self.owner) ~= true or (active and not Read(api.CurrentStop, self.owner)) then
        return false, "Another journey is active. Stop it in Shortest Path Forever before starting this quest route."
    end
    local point, message = self:ResolveQuest(questID)
    if not point then self.state, self.message = "missing_destination", message; return false, message end
    local ok = ProviderRead("NavigateRoute", api.NavigateRoute, self.owner, {{map=point.map,x=point.x,y=point.y,title=point.title,kind=point.kind,questID=questID}})
    if ok ~= true then
        self.state, self.message = "no_path", "The navigation provider refused this destination. No route was started."
        return false, self.message
    end
    self.active, self.activeQuestID, self.destination = true, questID, point
    self.state, self.message = "searching", "Checking walkable terrain for the selected quest…"
    return true, self.message
end

function Q:StartMapPin()
    if not Enabled() then return false, "Enable quest routes in RicoPlates settings first." end
    if Combat() then return false, "Finish combat before planning a map-pin route." end
    local api, bridge, reason = self:Provider()
    if not api then return false, reason end
    local active = ProviderRead("Active", api.Active)
    if type(active) ~= "boolean" then return false, "The navigation provider's ownership state is unavailable." end
    if Read(bridge.CanStart, self.owner) ~= true or (active and not Read(api.CurrentStop, self.owner)) then
        return false, "Another journey is active. Stop it before navigating to this map pin."
    end
    local pin = Read(C_Map and C_Map.GetUserWaypoint)
    local position = Field(pin, "position")
    local x, y, map = Field(position, "x"), Field(position, "y"), Field(pin, "uiMapID")
    if position and (not Number(x) or not Number(y)) then
        local method = Field(position, "GetXY")
        if type(method) == "function" then
            local ok, px, py = pcall(method, position)
            if ok and Number(px) and Number(py) then x, y = px, py end
        end
    end
    if not Point(map, x, y) then return false, "Place a map pin first. No pin was assigned to a quest." end
    local point = {map=map,x=x,y=y,title="Map pin",source="Map pin"}
    if ProviderRead("NavigateRoute", api.NavigateRoute, self.owner, {{map=map,x=x,y=y,title=point.title}}) ~= true then
        return false, "The navigation provider refused this map pin. No route was started."
    end
    self.active, self.activeQuestID, self.destination = true, nil, point
    self.state, self.message = "searching", "Checking walkable terrain to your map pin…"
    return true, self.message
end

function Q:Stop()
    local api = self:Provider()
    if not api or not Read(api.CurrentStop, self.owner) then
        self.active, self.activeQuestID, self.destination = false, nil, nil
        self.state, self.message = "idle", "No RicoPlates quest route is active."
        return false, self.message
    end
    if ProviderRead("Cancel", api.Cancel, self.owner) ~= true then return false, "The navigation provider could not stop this route." end
    self.active, self.activeQuestID, self.destination = false, nil, nil
    self.state, self.message = "idle", "Quest route stopped."
    return true, self.message
end

function Q:GetStatus()
    local api, bridge, reason = self:Provider()
    if not api then return {ready=false,state="missing_provider",message=reason,activeQuestID=self.activeQuestID} end
    if not Enabled() then return {ready=false,state="disabled",message="Quest routes are disabled."} end
    if self.active or self.activeQuestID then
        if Read(api.CurrentStop, self.owner) then
            local status = Read(bridge.GetStatus, self.owner)
            if Table(status) and String(status.state) and String(status.message) then
                self.state, self.message = status.state, status.message
                return {ready=true,state=self.state,message=self.message,active=true,verified=status.verified==true,mode=status.mode,
                    activeQuestID=self.activeQuestID,title=self.destination and self.destination.title,source=self.destination and self.destination.source}
            end
            return {ready=false,state="restricted",message="The navigation quality status is unavailable."}
        end
        local ended = Read(api.Ended, self.owner)
        self.active, self.activeQuestID, self.destination = false, nil, nil
        self.state, self.message = "idle", ended == "arrived" and "Quest destination reached." or "RicoPlates no longer owns the active route."
    end
    return {ready=true,state=self.state,message=self.message,active=self.active==true,activeQuestID=self.activeQuestID}
end

function Q:UpdateSettings()
    if not Enabled() then self:Stop() end
end

function Q:GetDiagnostics()
    local function Clean(value, limit)
        if not String(value) then return "unavailable" end
        return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%c]", " "):sub(1, limit or 240)
    end
    local function Flag(value)
        if not Public(value) then return "unavailable" end
        return value == true and "yes" or value == false and "no" or "unavailable"
    end
    local lines = {"Rico navigation diagnostics", "State: " .. Clean(self.state), "Status: " .. Clean(self.message)}
    local point = self.destination
    if Table(point) and Point(point.map, point.x, point.y) then
        lines[#lines + 1] = string.format("Destination: map %d, %.2f%%, %.2f%% (%s)", point.map, point.x * 100, point.y * 100, Clean(point.source, 60))
    else lines[#lines + 1] = "Destination: none" end
    local questie = rawget(_G, "Questie")
    lines[#lines + 1] = "Questie required: no; installed: " .. Flag(Table(questie) == true) .. "; ready: " .. Flag(Field(Field(questie, "API"), "isReady"))
    local api = C_QuestLog or {}
    lines[#lines + 1] = "Native quest locations: waypoint=" .. Flag(type(api.GetNextWaypoint) == "function")
        .. ", map waypoint=" .. Flag(type(api.GetNextWaypointForMap) == "function") .. ", map markers=" .. Flag(type(api.GetQuestsOnMap) == "function")
    local _, bridge, reason = self:Provider()
    if not bridge then lines[#lines + 1] = "Provider: " .. Clean(reason)
    else
        local diagnostics = Read(Field(bridge, "GetDiagnostics"))
        if Table(diagnostics) then
            for _, entry in ipairs({{"Initialized", "initialized"}, {"Journey enabled", "journeyEnabled"}, {"Arrow enabled", "arrowEnabled"},
                {"Map routes enabled", "mapRoutesEnabled"}, {"Player position available", "positionAvailable"}, {"Terrain available", "terrainAvailable"}, {"In combat", "combat"}}) do
                lines[#lines + 1] = entry[1] .. ": " .. Flag(Field(diagnostics, entry[2]))
            end
            if Number(Field(diagnostics, "caughtErrorCount")) and diagnostics.caughtErrorCount > 0 then
                lines[#lines + 1] = "Provider error: " .. Clean(Field(diagnostics, "lastErrorLabel"), 40) .. " - " .. Clean(Field(diagnostics, "lastErrorMessage"), 180)
            end
        else lines[#lines + 1] = "Provider diagnostics: unavailable" end
        local status = Read(Field(bridge, "GetStatus"), self.owner)
        if Table(status) then lines[#lines + 1] = "Route check: " .. Clean(Field(status, "state"), 40) .. " - " .. Clean(Field(status, "message")) end
    end
    if self.lastProviderError then lines[#lines + 1] = "Last navigation call error: " .. Clean(self.lastProviderError) end
    local bounded = {}
    for index = 1, math.min(#lines, 22) do
        local line = lines[index]
        bounded[index] = #line > 110 and (line:sub(1, 107) .. "...") or line
    end
    return table.concat(bounded, "\n")
end

function Q:Initialize()
    if self.initialized then return end
    self.initialized = true
    self.events = CreateFrame("Frame")
    self.events:RegisterEvent("QUEST_REMOVED")
    self.events:SetScript("OnEvent", function(_, _, questID)
        if ID(questID) and questID == Q.activeQuestID then Q:Stop() end
    end)
end
