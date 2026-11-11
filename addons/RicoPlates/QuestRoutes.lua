-- Quest destinations and circuits routed by the terrain-checked SPF bridge.
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
local function NativeDestination(questID, title, complete, mapMarkers)
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
        local pois = mapMarkers and mapMarkers[map]
        if pois == nil then
            pois = Read(api.GetQuestsOnMap, map)
            if mapMarkers then mapMarkers[map] = Table(pois) and pois or false end
        end
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

function Q:ResolveQuest(questID, mapMarkers)
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
    local point = NativeDestination(questID, title, complete, mapMarkers)
    if point then return point end
    return nil, "The game has no readable location for this quest yet. Questie is optional. Place a map pin and choose Navigate map pin to select a destination yourself."
end

function Q:GetActiveQuests()
    local api = C_QuestLog or {}
    local entries, seen = {}, {}
    if type(api.GetNumQuestLogEntries) ~= "function" then return entries end
    local ok, shown, total = pcall(api.GetNumQuestLogEntries)
    if not ok or not Number(shown) or shown < 0 then return entries end
    local limit = math.min(250, shown + (Number(total) and math.max(0, total) or 0))
    for index = 1, limit do
        local info = Read(api.GetInfo, index)
        if not info and index > shown then break end
        local id = Field(info, "questID")
        if Table(info) and ID(id) and not seen[id] and Public(info.isHeader) and not info.isHeader
            and Public(info.isHidden) and not info.isHidden and Public(info.isInternalOnly) and not info.isInternalOnly
            and Read(api.IsOnQuest, id) ~= false then
            seen[id] = true
            local title = Field(info, "title")
            entries[#entries + 1] = {id=id,title=String(title) and title ~= "" and title or ("Quest " .. id)}
        end
    end
    return entries
end

local function NavigateTo(self, api, questID, point, message)
    local stop = {map=point.map,x=point.x,y=point.y,title=point.title,kind=point.kind,questID=questID}
    if ProviderRead("NavigateRoute", api.NavigateRoute, self.owner, {stop}) ~= true then
        return false, "The navigation provider refused this destination. No route was started."
    end
    self.active, self.activeQuestID, self.destination = true, questID, point
    self.state, self.message = "searching", message
    return true, self.message
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
    local started, message = NavigateTo(self, api, questID, point, "Checking walkable terrain for the selected quest…")
    if started then self:ClearQuestPlan() else self.state, self.message = "no_path", message end
    return started, message
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
    self:ClearQuestPlan()
    return true, self.message
end

function Q:Stop()
    local api = self:Provider()
    if not api or not Read(api.CurrentStop, self.owner) then
        local planned = self.questPlan ~= nil
        self:ClearQuestPlan()
        self.active, self.activeQuestID, self.destination = false, nil, nil
        self.state, self.message = "idle", planned and "Quest route stopped." or "No RicoPlates quest route is active."
        return planned, self.message
    end
    if ProviderRead("Cancel", api.Cancel, self.owner) ~= true then return false, "The navigation provider could not stop this route." end
    self:ClearQuestPlan()
    self.active, self.activeQuestID, self.destination = false, nil, nil
    self.state, self.message = "idle", "Quest route stopped."
    return true, self.message
end

function Q:GetStatus()
    local api, bridge, reason = self:Provider()
    if not api then return {ready=false,state="missing_provider",message=reason,activeQuestID=self.activeQuestID} end
    if not Enabled() then return {ready=false,state="disabled",message="Quest routes are disabled."} end
    local plan = self.questPlan
    if plan then
        return {ready=true,state=self.state,message=self.message,active=true,verified=plan.verified,mode=plan.travelMode,
            activeQuestID=self.activeQuestID,title=self.destination and self.destination.title,source=self.destination and self.destination.source,
            circuit=plan.circuit,circuitIndex=plan.index,circuitCompleted=plan.completed,circuitRemaining=plan.remaining,
            canSkip=plan.circuit and self.activeQuestID ~= nil}
    end
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

local function Coordinates(position)
    local x, y = Field(position, "x"), Field(position, "y")
    if Number(x) and Number(y) then return x, y end
    local method = Field(position, "GetXY")
    if type(method) ~= "function" then return end
    local ok, px, py = pcall(method, position)
    if ok and Number(px) and Number(py) then return px, py end
end

local function WorldPoint(map, x, y)
    local convert = C_Map and C_Map.GetWorldPosFromMapPos
    if type(convert) ~= "function" or not Point(map, x, y) then return end
    local position = Read(CreateVector2D, x, y)
    if not position then return end
    local ok, continent, world = pcall(convert, map, position)
    if not ok or not Number(continent) then return end
    local wx, wy = Coordinates(world)
    if wx then return {continent=continent,x=wx,y=wy} end
end

local function RankDestination(questID, point, map, x, y, playerWorld)
    local world = playerWorld and WorldPoint(point.map, point.x, point.y)
    if world and world.continent == playerWorld.continent then
        return 1, (world.x - playerWorld.x)^2 + (world.y - playerWorld.y)^2
    end
    if point.map == map and Point(map, x, y) then
        local distance = C_QuestLog and C_QuestLog.GetDistanceSqToQuest
        if type(distance) == "function" then
            local ok, squared, sameContinent = pcall(distance, questID)
            if ok and Public(sameContinent) and sameContinent == true and Number(squared) and squared >= 0 then
                return 1, squared
            end
        end
        return 2, (point.x - x)^2 + (point.y - y)^2
    end
    return 3, 0
end

function Q:ChooseNextQuest(api, plan)
    local map = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    local x, y = Coordinates(ID(map) and Read(C_Map and C_Map.GetPlayerMapPosition, map, "player"))
    local world = WorldPoint(map, x, y)
    local candidates, markers, missing = {}, {}, 0
    for order, quest in ipairs(self:GetActiveQuests()) do
        if not plan.excluded[quest.id] then
            local point = self:ResolveQuest(quest.id, markers)
            if point then
                local tier, distance = RankDestination(quest.id, point, map, x, y, world)
                candidates[#candidates + 1] = {id=quest.id,point=point,tier=tier,distance=distance,order=order}
            else missing = missing + 1 end
        end
    end
    table.sort(candidates, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.order < b.order
    end)
    plan.remaining = #candidates
    for _, candidate in ipairs(candidates) do
        local ok = NavigateTo(self, api, candidate.id, candidate.point, "Checking walkable terrain to " .. candidate.point.title .. "…")
        if ok then
            plan.index = plan.index + 1
            plan.dirty, plan.arrived, plan.verified, plan.travelMode = false, false, nil, nil
            plan.waitingForLocation = nil
            return true, self.message
        end
        plan.excluded[candidate.id] = true
        plan.unreachable = plan.unreachable + 1
        plan.remaining = plan.remaining - 1
    end
    if plan.unreachable > 0 then return false, "No verified walking route to the remaining quest destinations." end
    if missing > 0 or plan.index == 0 then return false, "No active quests with a readable destination." end
    return false, ("Quest circuit finished. %d turned in."):format(plan.completed)
end

function Q:ClearQuestPlan()
    if not self.questPlan then return end
    self.questPlan = nil
    if self.events then self.events:SetScript("OnUpdate", nil) end
end

local function CanNavigate(self, api, bridge)
    local active = ProviderRead("Active", api.Active)
    return type(active) == "boolean" and Read(bridge.CanStart, self.owner) == true
        and (not active or Read(api.CurrentStop, self.owner))
end

local function QuestPlanTick(frame, elapsed)
    frame.elapsed = frame.elapsed + elapsed
    if frame.elapsed < 0.5 then return end
    frame.elapsed = 0
    Q:UpdateQuestPlan()
end

function Q:StartQuestPlan(circuit)
    if not Enabled() then return false, "Enable quest routes in RicoPlates settings first." end
    if Combat() then return false, "Finish combat before planning a quest route." end
    local api, bridge, reason = self:Provider()
    if not api then return false, reason end
    if not CanNavigate(self, api, bridge) then return false, "Another journey is active. Stop it before starting quest guidance." end
    local plan = {circuit=circuit,excluded={},index=0,completed=0,unreachable=0}
    local started, message = self:ChooseNextQuest(api, plan)
    if not started then return false, message end
    self:Initialize()
    self.questPlan = plan
    self.events.elapsed = 0
    self.events:SetScript("OnUpdate", QuestPlanTick)
    return true, message
end

function Q:StartNearest() return self:StartQuestPlan(false) end
function Q:StartCircuit() return self:StartQuestPlan(true) end

function Q:FinishQuestPlan(state, message)
    self:ClearQuestPlan()
    self.active, self.activeQuestID, self.destination = false, nil, nil
    self.state, self.message = state, message
    return true, message
end

function Q:AdvanceQuestPlan(api, bridge, reason)
    local plan = self.questPlan
    if Read(api.CurrentStop, self.owner) and ProviderRead("Cancel", api.Cancel, self.owner) ~= true then
        return false, "The navigation provider could not stop this route."
    end
    plan.excluded[self.activeQuestID] = true
    plan.outcome = nil
    if reason == "turned_in" then plan.completed = plan.completed + 1 end
    if reason == "no_path" then plan.unreachable = plan.unreachable + 1 end
    self.active, self.activeQuestID, self.destination = false, nil, nil
    if not plan.circuit and reason ~= "no_path" then
        return self:FinishQuestPlan("idle", reason == "turned_in" and "Quest turned in." or "The quest is no longer active.")
    end
    if not CanNavigate(self, api, bridge) then
        self.state, self.message = "paused", "Waiting for the other journey to finish."
        return true, self.message
    end
    local ok, message = self:ChooseNextQuest(api, plan)
    if ok then return true, message end
    return self:FinishQuestPlan("idle", message)
end

function Q:SkipQuest()
    if not (self.questPlan and self.questPlan.circuit and self.activeQuestID) then return false, "There is no quest to skip." end
    if Combat() then return false, "Finish combat before skipping this quest." end
    local api, bridge, reason = self:Provider()
    if not api then return false, reason end
    return self:AdvanceQuestPlan(api, bridge, "skipped")
end

local function SameStop(a, b)
    return a.map == b.map and a.kind == b.kind and (a.x - b.x)^2 + (a.y - b.y)^2 < 0.000001
end

function Q:UpdateQuestPlan()
    local plan = self.questPlan
    if not plan or not Enabled() or Combat() then return end
    local api, bridge, reason = self:Provider()
    if not api then self:FinishQuestPlan("missing_provider", reason); return end
    local id = self.activeQuestID
    if not id then
        if CanNavigate(self, api, bridge) then
            local ok, message = self:ChooseNextQuest(api, plan)
            if not ok then self:FinishQuestPlan("idle", message) end
        end
        return
    end
    if plan.outcome or Read(C_QuestLog and C_QuestLog.IsOnQuest, id) == false then
        self:AdvanceQuestPlan(api, bridge, plan.outcome or "removed")
        return
    end

    local ownsStop = Read(api.CurrentStop, self.owner)
    local ended = not ownsStop and Read(api.Ended, self.owner)
    if not plan.waitingForLocation and (ended == "cancelled" or ended == "cleared" or ended == "replaced") then
        self:FinishQuestPlan("idle", "Quest route stopped.")
        return
    end
    if plan.dirty and CanNavigate(self, api, bridge) then
        plan.dirty = false
        local point = self:ResolveQuest(id)
        if point and not SameStop(point, self.destination) then
            local started = NavigateTo(self, api, id, point, "Checking walkable terrain to " .. point.title .. "…")
            if started then
                plan.arrived, plan.verified, plan.travelMode = false, nil, nil
                plan.waitingForLocation = nil
                return
            end
            self:AdvanceQuestPlan(api, bridge, "no_path")
            return
        end
        if not point and self.destination.kind ~= "turnin" and Read(C_QuestLog and C_QuestLog.IsComplete, id) == true then
            if ownsStop and ProviderRead("Cancel", api.Cancel, self.owner) ~= true then return end
            plan.waitingForLocation, plan.verified, plan.travelMode = true, nil, nil
            self.state, self.message = "waiting", "Quest objectives complete. Waiting for a readable turn-in location."
            return
        end
    end

    if plan.waitingForLocation then return end
    if ownsStop then
        local status = Read(bridge.GetStatus, self.owner)
        local state, message = Field(status, "state"), Field(status, "message")
        if state == "no_path" then
            self:AdvanceQuestPlan(api, bridge, "no_path")
        elseif String(state) and String(message) then
            self.state, self.message = state, message
            plan.verified, plan.travelMode = Field(status, "verified") == true, Field(status, "mode")
        end
    elseif ended == "arrived" or plan.arrived then
        plan.arrived, plan.verified, plan.travelMode = true, nil, nil
        local turnin = self.destination.kind == "turnin"
        self.state, self.message = "waiting", turnin and "Destination reached. Turn in the quest to continue."
            or "Objective area reached. Finish the objective to continue."
    end
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
    for _, event in ipairs({"QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE",
        "QUEST_POI_UPDATE", "WAYPOINT_UPDATE", "ZONE_CHANGED_NEW_AREA"}) do
        pcall(self.events.RegisterEvent, self.events, event)
    end
    self.events:SetScript("OnEvent", function(_, event, questID)
        local matches = ID(questID) and questID == Q.activeQuestID
        local plan = Q.questPlan
        if plan then
            if matches and event == "QUEST_TURNED_IN" then plan.outcome = "turned_in"
            elseif matches and event == "QUEST_REMOVED" then plan.outcome = plan.outcome or "removed"
            elseif event ~= "QUEST_WATCH_UPDATE" or matches then plan.dirty = true end
        elseif matches and (event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN") then
            Q:Stop()
        end
    end)
end
