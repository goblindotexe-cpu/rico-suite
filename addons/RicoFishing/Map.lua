local _, F = ...
local M = { worldFrames = {}, miniFrames = {}, worldCount = 0, miniCount = 0 }
F.Map = M

local WORLD_LIMIT, MINI_LIMIT = 80, 32
local WORLD_SIZE, MINI_SIZE = 20, 16
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Method(object, method, ...)
    return F.Call(object and object[method], object, ...)
end

local function Read(fn, ...)
    local ok, value = F.Call(fn, ...)
    if ok and not F.IsSecret(value) then return value end
end

local function XY(position)
    if F.IsSecret(position) or position == nil then return end
    local ok, x, y = pcall(function()
        if type(position.GetXY) == "function" then return position:GetXY() end
        return position.x, position.y
    end)
    if ok and F.Number(x) and F.Number(y) then return x, y end
end

local function MapInfo(mapID)
    local info = Read(C_Map and C_Map.GetMapInfo, mapID)
    if type(info) == "table" and (not canaccesstable or canaccesstable(info)) then return info end
end

function M:MapUsable(location)
    if not location or not F.Number(location.mapID) or location.mapID < 1 or not C_Map then return false end
    local info = MapInfo(location.mapID)
    if not info or not F.PublicString(info.name) then return false end
    -- On English clients a mismatching zone name identifies a reference that
    -- uses a different map-ID scheme.
    local locale = GetLocale and GetLocale() or "enUS"
    if (locale == "enUS" or locale == "enGB") and location.zone and info.name ~= location.zone then return false end
    return true
end

function M:ValidPoint(x, y)
    return F.Number(x) and F.Number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

function M:CanUsePoint(location, x, y)
    if not (self:ValidPoint(x, y) and F:CanPinFishingLocation(location) and self:MapUsable(location)) then return false end
    if location.x == x and location.y == y then return true end
    for _, point in ipairs(location.points or {}) do
        if (point.x or point[1]) == x and (point.y or point[2]) == y then return true end
    end
    return false
end

local function ClearPin(pin)
    if GameTooltip and GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
    pin:Hide()
    pin.point = nil
end

function M:ClearPins(frames)
    for _, frame in ipairs(frames) do ClearPin(frame) end
end

function M:ShowTooltip(pin)
    local point = pin.point
    if not point or not self.entry or not GameTooltip then return end
    local location = point.location
    local description = F.DescribeFishingLocation and F:DescribeFishingLocation(location)
        or (location.observed and "Forever catch report" or "Wowhead reference")
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.entry.name)
    GameTooltip:AddLine(description, 0.90, 0.75, 0.35, true)
    GameTooltip:AddLine(string.format("%s • %.2f, %.2f", location.zone or "Fishing spot", point.x * 100, point.y * 100), 0.80, 0.85, 0.90)
    local rate = F.FormatFishingRate and F:FormatFishingRate(location)
    if F.PublicString(rate) and rate ~= "" then GameTooltip:AddLine(rate, 0.83, 0.91, 0.88, true) end
    GameTooltip:AddLine("Left-click to place a pin. Right-click for Rico GPS.", 0.35, 0.95, 0.75, true)
    GameTooltip:Show()
end

function M:GetPin(index, mini, parent)
    local frames = mini and self.miniFrames or self.worldFrames
    local frame = frames[index]
    if frame then
        if frame:GetParent() ~= parent then frame:SetParent(parent) end
        return frame
    end
    frame = CreateFrame("Button", nil, parent)
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetAllPoints()
    frame.border:SetTexture(WHITE)
    frame.border:SetVertexColor(0.035, 0.075, 0.055, 0.95)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 1, -1)
    frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame:SetScript("OnEnter", function(self) M:ShowTooltip(self) end)
    frame:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    frame:SetScript("OnClick", function(self, button)
        local point = self.point
        if not point then return end
        if button == "RightButton" then M:StartGPS(M.entry, point.location, point.x, point.y)
        else M:SetWaypoint(M.entry, point.location, point.x, point.y) end
    end)
    frame:Hide()
    frames[index] = frame
    return frame
end

function M:PlacePin(pin, point, parent, anchor, x, y)
    if pin.point ~= point then
        if GameTooltip and GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
        pin.point = point
        pin.icon:SetTexture(self.icon)
        if point.location.observed then pin.icon:SetVertexColor(1, 1, 1)
        else pin.icon:SetVertexColor(1, 0.84, 0.61) end
    end
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", parent, anchor, x, y)
    pin:Show()
end

local function WorldPosition(mapID, x, y)
    if not (C_Map and CreateVector2D) then return end
    local ok, instance, position = F.Call(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not F.Number(instance) then return end
    local wx, wy = XY(position)
    if wx then return instance, wx, wy end
end

local function Projection(mapID)
    local instance, x, y = WorldPosition(mapID, 0, 0)
    local xInstance, xx, xy = WorldPosition(mapID, 1, 0)
    local yInstance, yx, yy = WorldPosition(mapID, 0, 1)
    if instance and instance == xInstance and instance == yInstance then
        return { instance = instance, x = x, y = y, xx = xx - x, xy = xy - y, yx = yx - x, yy = yy - y }
    end
end

function M:Rebuild(entry)
    self.entry, self.points, self.minimapPoints = entry, {}, {}
    if not entry then return end
    self.icon = F:GetIcon(entry.id)
    local points, seen = self.points, {}
    local locations = F.GetFishingLocations and F:GetFishingLocations(entry) or entry.locations
    local function add(location, x, y)
        if not self:ValidPoint(x, y) then return end
        local key = string.format("%d:%.6f:%.6f", location.mapID, x, y)
        local current = seen[key]
        if current then
            if location.observed and not current.location.observed then current.location = location end
            return
        end
        local point = { location = location, mapID = location.mapID, x = x, y = y }
        seen[key] = point
        points[#points + 1] = point
    end
    for _, location in ipairs(locations or {}) do
        if F:CanPinFishingLocation(location) and self:MapUsable(location) then
            add(location, location.x, location.y)
            for _, point in ipairs(location.points or {}) do
                add(location, point.x or point[1], point.y or point[2])
            end
        end
    end
    local matrices = {}
    for _, point in ipairs(points) do
        local map = point.mapID
        if matrices[map] == nil then matrices[map] = Projection(map) or false end
        local matrix = matrices[map]
        local instance
        if matrix then
            instance = matrix.instance
            point.wx = matrix.x + matrix.xx * point.x + matrix.yx * point.y
            point.wy = matrix.y + matrix.xy * point.x + matrix.yy * point.y
        else
            instance, point.wx, point.wy = WorldPosition(map, point.x, point.y)
        end
        if instance then
            local bucket = self.minimapPoints[instance] or {}
            self.minimapPoints[instance] = bucket
            bucket[#bucket + 1] = point
        end
    end
end

local function IsMapAncestor(map, ancestor)
    for _ = 1, 16 do
        local info = MapInfo(map)
        local parent = info and info.parentMapID
        if not F.Number(parent) or parent == 0 or parent == map then return false end
        if parent == ancestor then return true end
        map = parent
    end
    return false
end

local function ProjectToMap(point, map, rectangles)
    local source = point.mapID
    if source == map then return point.x, point.y end
    if rectangles[source] == nil then
        rectangles[source] = false
        if IsMapAncestor(source, map) then
            local ok, left, right, top, bottom = F.Call(C_Map.GetMapRectOnMap, source, map)
            if ok and F.Number(left) and F.Number(right) and F.Number(top) and F.Number(bottom) and right > left and bottom > top then
                rectangles[source] = { left = left, top = top, width = right - left, height = bottom - top }
            end
        end
    end
    local rect = rectangles[source]
    if rect then return rect.left + rect.width * point.x, rect.top + rect.height * point.y end
end

function M:ResizeWorldPins()
    local scale = Read(WorldMapFrame and WorldMapFrame.GetCanvasScale, WorldMapFrame)
    local size = F.Number(scale) and scale > 0 and WORLD_SIZE / scale or WORLD_SIZE
    for index = 1, self.worldCount do self.worldFrames[index]:SetSize(size, size) end
end

function M:ClearWorld()
    self:ClearPins(self.worldFrames)
    self.worldCount = 0
end

function M:RefreshWorld()
    self:ClearWorld()
    local world = WorldMapFrame
    if not self.entry or not Read(world and world.IsShown, world) then return end
    local canvas = Read(world.GetCanvas, world)
    local map = Read(world.GetMapID, world)
    local width, height = Read(canvas and canvas.GetWidth, canvas), Read(canvas and canvas.GetHeight, canvas)
    if not F.Number(map) or not F.Number(width) or not F.Number(height) or width <= 0 or height <= 0 then return end
    local visible, rectangles = {}, {}
    for _, point in ipairs(self.points) do
        local x, y = ProjectToMap(point, map, rectangles)
        if self:ValidPoint(x, y) then
            visible[#visible + 1] = { point = point, x = x, y = y }
        end
    end
    local level = canvas:GetFrameLevel() + 8
    self.worldCount = math.min(#visible, WORLD_LIMIT)
    for index = 1, self.worldCount do
        -- Sample dense references across the canvas without averaging any coordinates.
        local at = #visible <= WORLD_LIMIT and index or math.floor((index - 1) * (#visible - 1) / (WORLD_LIMIT - 1)) + 1
        local candidate = visible[at]
        local pin = self:GetPin(index, false, canvas)
        pin:SetFrameLevel(level)
        self:PlacePin(pin, candidate.point, canvas, "TOPLEFT", candidate.x * width, -candidate.y * height)
    end
    self:ResizeWorldPins()
end

local function PlayerPosition()
    local ok, x, y, _, instance = F.Call(UnitPosition, "player")
    if ok and F.Number(instance) and F.Number(x) and F.Number(y) then return instance, x, y end
    local map = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    if not F.Number(map) then return end
    x, y = XY(Read(C_Map.GetPlayerMapPosition, map, "player"))
    if x then return WorldPosition(map, x, y) end
end

function M:ClearMini()
    if self.miniView or self.miniCount > 0 then self:ClearPins(self.miniFrames) end
    self.miniView, self.miniCount = nil, 0
end

function M:RefreshMini()
    local map = Minimap
    if not self.entry or not self.minimapPoints or not map or not Read(map.IsVisible, map) then self:ClearMini(); return end
    local instance, px, py = PlayerPosition()
    local radius = Read(C_Minimap and C_Minimap.GetViewRadius)
    local width, height = map:GetWidth(), map:GetHeight()
    local candidates = instance and self.minimapPoints[instance]
    if not candidates or not F.Number(radius) or radius <= 0 or not F.Number(width) or not F.Number(height)
        or width <= MINI_SIZE or height <= MINI_SIZE then self:ClearMini(); return end
    local facing = 0
    if Read(GetCVarBool, "rotateMinimap") == true and Read(C_Minimap.IsRotateMinimapIgnored) ~= true then
        facing = Read(GetPlayerFacing)
    end
    if not F.Number(facing) then self:ClearMini(); return end
    local square = Read(GetMinimapShape) == "SQUARE"
    local level = map:GetFrameLevel() + 7
    local previous = self.miniView
    if previous and previous.map == map and previous.instance == instance and previous.x == px and previous.y == py
        and previous.facing == facing and previous.radius == radius and previous.width == width
        and previous.height == height and previous.square == square and previous.level == level then return end

    self.miniView = { map = map, instance = instance, x = px, y = py, facing = facing, radius = radius,
        width = width, height = height, square = square, level = level }
    local cos, sin = math.cos(facing), math.sin(facing)
    local reachX, reachY = 1 - MINI_SIZE / width, 1 - MINI_SIZE / height
    local visible = {}
    for _, point in ipairs(candidates) do
        local east, north = -(point.wy - py) / radius, (point.wx - px) / radius
        local x, y = east * cos + north * sin, -east * sin + north * cos
        if (square and math.abs(x) <= reachX and math.abs(y) <= reachY)
            or (not square and (x / reachX)^2 + (y / reachY)^2 <= 1) then
            visible[#visible + 1] = { point = point, x = x, y = y, distance = x * x + y * y }
        end
    end
    table.sort(visible, function(a, b) return a.distance < b.distance end)
    self.miniCount = math.min(#visible, MINI_LIMIT)

    -- Keep a visible location attached to the same button as the player moves.
    local desired, existing, free = {}, {}, {}
    for index = 1, self.miniCount do desired[visible[index].point] = true end
    for _, pin in ipairs(self.miniFrames) do
        if pin.point and desired[pin.point] then existing[pin.point] = pin
        else free[#free + 1] = pin end
    end
    for index = 1, self.miniCount do
        local candidate = visible[index]
        local pin = existing[candidate.point] or table.remove(free) or self:GetPin(#self.miniFrames + 1, true, map)
        if pin:GetParent() ~= map then pin:SetParent(map) end
        pin:SetFrameLevel(level)
        pin:SetSize(MINI_SIZE, MINI_SIZE)
        self:PlacePin(pin, candidate.point, map, "CENTER", candidate.x * width / 2, candidate.y * height / 2)
    end
    for _, pin in ipairs(free) do if pin.point then ClearPin(pin) end end
end

local function Tick(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.20 then return end
    self.elapsed = 0
    M:RefreshMini()
end

function M:Refresh()
    self:HookWorldMap()
    local entry = F.db and F.db.pins and F:GetEntry(F.db.selected)
    self:ClearMini()
    self:Rebuild(entry)
    self:RefreshWorld()
    self:RefreshMini()
    if self.worker then
        self.worker.elapsed = 0
        self.worker:SetScript("OnUpdate", entry and next(self.minimapPoints) and Tick or nil)
    end
end

function M:SetWaypoint(entry, location, x, y)
    if not entry or not self:CanUsePoint(location, x, y) then
        F:Print("This fishing spot has no usable coordinates."); return false
    end
    local rule = Enum and Enum.GameRule and Enum.GameRule.WorldMapTrackingPinDisabled
    if C_GameRules and C_GameRules.IsGameRuleActive and rule then
        local got, blocked = F.Call(C_GameRules.IsGameRuleActive, rule)
        if not got or F.IsSecret(blocked) or blocked == true then F:Print("This client does not allow a waypoint here."); return false end
    end
    local allowed, canSet = F.Call(C_Map.CanSetUserWaypointOnMap, location.mapID)
    if not allowed or F.IsSecret(canSet) or canSet ~= true then
        F:Print("This map does not support a native waypoint."); return false
    end
    local point = Read(UiMapPoint and UiMapPoint.CreateFromCoordinates, location.mapID, x, y)
    if not point or Read(C_Map.SetUserWaypoint, point) ~= true then F:Print("WoW could not place the waypoint."); return false end
    if C_SuperTrack then F.Call(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    F:Print(string.format("%s pin at %.2f, %.2f.", entry.name, x * 100, y * 100))
    return true
end

function M:GPSAvailable()
    local routes = RicoPlates and RicoPlates.QuestRoutes
    return routes ~= nil and type(routes.StartFishingSpot) == "function"
end

function M:StartGPS(entry, location, x, y)
    if not entry or not self:CanUsePoint(location, x, y) then
        F:Print("This fishing spot has no usable coordinates."); return false
    end
    if not self:GPSAvailable() then
        F:Print("Enable RicoPlates to use Rico GPS. The Pin button still works."); return false
    end
    local ok, started, message = Method(RicoPlates.QuestRoutes, "StartFishingSpot", location.mapID, x, y, entry.name)
    if ok and F.PublicString(message) then F:Print(message)
    elseif not ok or started ~= true then F:Print("Rico GPS could not start this route.") end
    return ok and started == true
end

function M:OpenZone(location)
    if not self:MapUsable(location) then F:Print("No matching map found in this client."); return false end
    if not WorldMapFrame then return false end
    if ShowUIPanel then F.Call(ShowUIPanel, WorldMapFrame) else Method(WorldMapFrame, "Show") end
    local ok = Method(WorldMapFrame, "SetMapID", location.mapID)
    if ok then self:RefreshWorld() end
    return ok
end

function M:HookWorldMap()
    local world = WorldMapFrame
    if not world or self.mapHooked then return end
    self.mapHooked = true
    world:HookScript("OnShow", function() M:RefreshWorld() end)
    world:HookScript("OnHide", function() M:ClearWorld() end)
    if hooksecurefunc and type(world.SetMapID) == "function" then
        hooksecurefunc(world, "SetMapID", function() M:RefreshWorld() end)
    end
    if hooksecurefunc and type(world.OnCanvasScaleChanged) == "function" then
        hooksecurefunc(world, "OnCanvasScaleChanged", function() M:ResizeWorldPins() end)
    end
    local canvas = Read(world.GetCanvas, world)
    if canvas then canvas:HookScript("OnSizeChanged", function() M:RefreshWorld() end) end
end

function M:GetStatus()
    if not F.db or not F.db.pins then return "Fishing markers: off." end
    return string.format("Fishing markers: %d on the world map, %d nearby on the minimap.", self.worldCount, self.miniCount)
end

function M:Initialize()
    if self.worker then return end
    self.worker = CreateFrame("Frame", nil, Minimap or UIParent)
    self:HookWorldMap()
end
