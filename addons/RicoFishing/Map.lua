local _, F = ...
local M = { worldFrames = {}, miniFrames = {}, worldCount = 0, miniCount = 0 }
F.Map = M
local WORLD_LIMIT, MINI_LIMIT = 80, 32

local function Method(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false end
    return pcall(object[method], object, ...)
end

function M:FindLibrary()
    if not LibStub then return end
    for _, suffix in ipairs({"Questie", ""}) do
        local ok, pins = pcall(function() return LibStub("HereBeDragons" .. suffix .. "-Pins-2.0", true) end)
        local got, coordinates = pcall(function() return LibStub("HereBeDragons" .. suffix .. "-2.0", true) end)
        if ok and got and pins and coordinates and type(pins.AddWorldMapIconMap) == "function"
            and type(pins.AddMinimapIconMap) == "function" and type(coordinates.GetWorldCoordinatesFromZone) == "function" then
            return pins, coordinates
        end
    end
end

function M:MapUsable(location)
    if not location or not F.Number(location.mapID) or location.mapID < 1 or not C_Map then return false end
    local ok, info = F.Call(C_Map.GetMapInfo, location.mapID)
    if not ok or F.IsSecret(info) or type(info) ~= "table"
        or (canaccesstable and not canaccesstable(info)) then return false end
    local gotName, name = pcall(function() return info.name end)
    if not gotName or not F.PublicString(name) then return false end
    -- In an English client a mismatching zone name is positive evidence that
    -- a reference uses a different map-ID scheme. Never put its pins there.
    local locale = GetLocale and GetLocale() or "enUS"
    if (locale == "enUS" or locale == "enGB") and location.zone and name ~= location.zone then return false end
    return true
end

function M:Allowed(location)
    return location and (location.observed == true or F.db.reportedPins == true)
end

function M:ValidPoint(x, y)
    return F.Number(x) and F.Number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

function M:Collect(entry, mapID, limit, centerX, centerY)
    local result, cells = {}, {}
    if not entry or not F.Number(mapID) then return result end
    limit = math.max(1, math.min(math.floor(limit or WORLD_LIMIT), WORLD_LIMIT))
    local function add(location, x, y)
        if not M:ValidPoint(x, y) then return end
        -- Keep a real source coordinate as the representative of each area.
        -- Averaging would manufacture a location that nobody reported.
        local key = math.floor(x * 33) .. ":" .. math.floor(y * 33)
        if cells[key] then return end
        cells[key] = true
        result[#result + 1] = { location = location, mapID = mapID, x = x, y = y }
    end
    for _, location in ipairs(entry.locations or {}) do
        if location.mapID == mapID and self:Allowed(location) and self:MapUsable(location) then
            add(location, location.x, location.y)
            for _, point in ipairs(location.points or {}) do
                add(location, point.x or point[1], point.y or point[2])
            end
        end
    end
    local nearest = self:ValidPoint(centerX, centerY)
    if nearest then
        table.sort(result, function(a, b)
            return (a.x - centerX)^2 + (a.y - centerY)^2 < (b.x - centerX)^2 + (b.y - centerY)^2
        end)
    end
    if #result <= limit then return result end
    local selected = {}
    for index = 1, limit do
        local sourceIndex = nearest and index or (limit == 1 and 1 or math.floor((index - 1) * (#result - 1) / (limit - 1)) + 1)
        selected[index] = result[sourceIndex]
    end
    return selected
end

function M:Clear()
    if self.pins then
        Method(self.pins, "RemoveAllWorldMapIcons", self)
        Method(self.pins, "RemoveAllMinimapIcons", self)
    end
    for _, frames in ipairs({self.worldFrames, self.miniFrames}) do
        for _, frame in ipairs(frames) do frame:Hide() end
    end
    self.worldCount, self.miniCount = 0, 0
end

function M:GetPin(index, mini)
    local frames = mini and self.miniFrames or self.worldFrames
    local frame = frames[index]
    if frame then return frame end
    frame = CreateFrame("Button", nil, UIParent)
    frame:SetSize(mini and 16 or 20, mini and 16 or 20)
    frame:EnableMouse(true)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexture("Interface\\Icons\\Trade_Fishing")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame:SetScript("OnEnter", function(self)
        if not self.entry or not self.point or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.entry.name)
        GameTooltip:AddLine(self.point.location.observed and "Forever catch report (beta)" or "Source location; not independently confirmed", 0.9, 0.75, 0.35)
        GameTooltip:AddLine("Fishing area; not a guaranteed spawn", 0.8, 0.85, 0.9)
        GameTooltip:AddLine(string.format("%s • %.1f, %.1f", self.point.location.zone or "Area", self.point.x * 100, self.point.y * 100), 0.8, 0.85, 0.9)
        GameTooltip:AddLine("Click to set a waypoint", 0.35, 0.95, 0.75)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame:SetScript("OnClick", function(self)
        if self.point then M:SetWaypoint(self.entry, self.point.location, self.point.x, self.point.y) end
    end)
    frame:Hide()
    frames[index] = frame
    return frame
end

function M:PlacePins(entry, points, mini)
    local count = 0
    for _, point in ipairs(points) do
        local ok, x, y, instance = Method(self.coordinates, "GetWorldCoordinatesFromZone", point.x, point.y, point.mapID)
        if ok and F.Number(x) and F.Number(y) and F.Number(instance) then
            local pin = self:GetPin(count + 1, mini)
            pin.entry, pin.point = entry, point
            pin.icon:SetTexture(F:GetIcon(entry.id))
            pin.icon:SetVertexColor(1, point.location.observed and 1 or 0.76, point.location.observed and 1 or 0.45)
            local applied
            if mini then applied = Method(self.pins, "AddMinimapIconMap", self, pin, point.mapID, point.x, point.y, false, false)
            else applied = Method(self.pins, "AddWorldMapIconMap", self, pin, point.mapID, point.x, point.y, 0) end
            if applied then count = count + 1 else pin:Hide() end
        end
    end
    return count
end

function M:Refresh()
    self:Clear()
    self.pins, self.coordinates = self:FindLibrary()
    self:HookWorldMap()
    if not F.db or not F.db.pins then return end
    local entry = F:GetEntry(F.db.selected)
    if not entry or not self.pins or not self.coordinates then return end
    local ok, playerMap = F.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    if not ok or not F.Number(playerMap) then playerMap = nil end
    local worldMap = playerMap
    local shown, visible = Method(WorldMapFrame, "IsShown")
    if shown and not F.IsSecret(visible) and visible == true then
        local got, id = Method(WorldMapFrame, "GetMapID")
        if got and F.Number(id) then worldMap = id end
    end
    local centerX, centerY
    if playerMap then
        local got, position = F.Call(C_Map.GetPlayerMapPosition, playerMap, "player")
        if got and not F.IsSecret(position) and position ~= nil then
            local read, x, y = pcall(function() return position:GetXY() end)
            if read and self:ValidPoint(x, y) then centerX, centerY = x, y end
        end
    end
    self.worldCount = self:PlacePins(entry, self:Collect(entry, worldMap, WORLD_LIMIT), false)
    self.miniCount = self:PlacePins(entry, self:Collect(entry, playerMap, MINI_LIMIT, centerX, centerY), true)
end

function M:SetWaypoint(entry, location, x, y)
    if not entry or not self:Allowed(location) or not self:MapUsable(location) or not self:ValidPoint(x, y) then
        F:Print("No permitted, usable coordinates for this point."); return false
    end
    if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule and Enum.GameRule.WorldMapTrackingPinDisabled then
        local got, blocked = F.Call(C_GameRules.IsGameRuleActive, Enum.GameRule.WorldMapTrackingPinDisabled)
        if not got or F.IsSecret(blocked) or blocked == true then F:Print("This client does not allow a waypoint here."); return false end
    end
    local allowed, canSet = F.Call(C_Map.CanSetUserWaypointOnMap, location.mapID)
    if not allowed or F.IsSecret(canSet) or canSet ~= true or not UiMapPoint or not UiMapPoint.CreateFromCoordinates then
        F:Print("This map does not support a native waypoint."); return false
    end
    local created, point = pcall(UiMapPoint.CreateFromCoordinates, location.mapID, x, y)
    if not created or F.IsSecret(point) or point == nil then return false end
    local set, wasSet = F.Call(C_Map.SetUserWaypoint, point)
    if not set or F.IsSecret(wasSet) or wasSet ~= true then F:Print("WoW could not place the waypoint."); return false end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    F:Print(entry.name .. ": waypoint to fishing area " .. (location.zone or tostring(location.mapID)) .. ".")
    return true
end

function M:OpenZone(location)
    if not self:MapUsable(location) then F:Print("No matching map found in this client."); return false end
    if not WorldMapFrame then return false end
    local ok = Method(WorldMapFrame, "SetMapID", location.mapID)
    if ok then
        if ShowUIPanel then pcall(ShowUIPanel, WorldMapFrame) else Method(WorldMapFrame, "Show") end
        self:Refresh()
    end
    return ok
end

function M:HookWorldMap()
    if not WorldMapFrame or self.mapHooked then return end
    self.mapHooked = true
    WorldMapFrame:HookScript("OnShow", function() M:Refresh() end)
    if hooksecurefunc and type(WorldMapFrame.SetMapID) == "function" then
        hooksecurefunc(WorldMapFrame, "SetMapID", function() M:Refresh() end)
    end
end

function M:GetStatus()
    if not F.db.pins then return "Map markers: off" end
    if not self.pins then return "Map: click a location for a native waypoint; minimap markers require Questie or HereBeDragons." end
    return "Map library available | registered area points: " .. self.worldCount .. " map / " .. self.miniCount .. " minimap."
end

function M:Initialize() self:HookWorldMap() end
