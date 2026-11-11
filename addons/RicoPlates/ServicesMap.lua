local _, RP = ...

local miningMap = RP.Mining and RP.Mining.Map
local P = { worldPins = {}, worldCount = 0, miniPins = {}, freeMiniPins = {} }
RP.ServicesMap = P

local WORLD_SIZE, MINI_SIZE = 16, 14
local HIT_CELLS, PAINT_BATCH, UPDATE_INTERVAL = 32, 200, 0.15

-- Use the same non-interactive canvas layer, cursor hit grid and scaling as mining.
P.WorldLayer = miningMap.WorldLayer
P.ClearWorld = miningMap.ClearWorld
P.WorldScale = miningMap.WorldScale
P.ResizeWorldIcons = miningMap.ResizeWorldIcons
P.WorldCursor = miningMap.WorldCursor
P.FindWorldNode = miningMap.FindWorldNode

local function Read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function Number(value)
    return RP.Readable(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

local function Fraction(value)
    return Number(value) and value >= 0 and value <= 1
end

local function Text(value)
    return RP.Readable(value) and type(value) == "string" and value ~= ""
end

local function XY(position)
    if not RP.Readable(position) or not position then return end
    local x, y = Read(position.GetXY, position)
    if not Number(x) then x, y = position.x, position.y end
    if Number(x) and Number(y) then return x, y end
end

local function Filter()
    return RP.Services and RP.Services:GetFilter() or "off"
end

local function MapPoints(map)
    local services = RP.Services
    local points = services:GetPoints(map) or {}
    local groups, entries = {}, {}
    for _, point in ipairs(points) do
        local category = services.categories[point.kind]
        if category and Fraction(point.x) and Fraction(point.y) and Text(point.name) then
            -- Merchants can offer several services from the same coordinates.
            local key = string.format("%.5f:%.5f", point.x, point.y)
            local entry = groups[key]
            if not entry then
                entry = { x = point.x, y = point.y, category = category, points = {} }
                groups[key] = entry
                entries[#entries + 1] = entry
            end
            entry.points[#entry.points + 1] = point
        end
    end
    return entries
end

local function HideTooltip(pin)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
end

local function ShowTooltip(pin)
    local entry = pin.node
    if not entry or not GameTooltip then return end
    local point = entry.points[1]
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(point.name, 0.47, 1, 0.78)
    GameTooltip:AddLine(entry.category.label .. (Text(point.faction) and " · " .. point.faction or ""), 0.9, 0.92, 0.9)
    if Text(point.detail) then GameTooltip:AddLine(point.detail, 0.7, 0.8, 0.76, true) end
    for index = 2, math.min(#entry.points, 8) do
        local other = entry.points[index]
        local label = RP.Services.categories[other.kind].label
        local details = Text(other.faction) and " · " .. other.faction or ""
        local title = other.name == point.name and label or other.name .. " · " .. label
        GameTooltip:AddLine(title .. details, 0.9, 0.92, 0.9, true)
    end
    if #entry.points > 8 then
        GameTooltip:AddLine(("%d more services here"):format(#entry.points - 8), 0.7, 0.8, 0.76)
    end
    GameTooltip:AddLine(("%.1f, %.1f"):format(entry.x * 100, entry.y * 100), 0.72, 0.82, 0.78)
    GameTooltip:Show()
end

function P:UpdateWorldHover()
    local hover = self.worldHover
    if not hover or self.worldCount == 0 then return end
    local x, y = self:WorldCursor()
    local entry = x and self:FindWorldNode(x, y)
    if not entry then
        HideTooltip(hover)
        hover.node = nil
        hover:Hide()
        return
    end
    hover:ClearAllPoints()
    hover:SetPoint("CENTER", self.worldLayer, "TOPLEFT", x, -y)
    hover:Show()
    local owner = GameTooltip and Read(GameTooltip.GetOwner, GameTooltip)
    local tooltipShown = GameTooltip and GameTooltip:IsShown()
    if (entry ~= hover.node or not tooltipShown) and (not tooltipShown or not owner or owner == hover) then
        hover.node = entry
        ShowTooltip(hover)
    end
end

function P:RefreshWorld()
    self:ClearWorld()
    local mapFrame, filter = WorldMapFrame, Filter()
    if filter == "off" or InCombatLockdown() or not RP.CanUseFrame(mapFrame) or not mapFrame:IsShown() then return end
    local canvas = Read(mapFrame.GetCanvas, mapFrame)
    local map = Read(mapFrame.GetMapID, mapFrame)
    if not RP.CanUseFrame(canvas) or not Number(map) then return end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not Number(width) or not Number(height) or width <= 0 or height <= 0 then return end
    local entries = MapPoints(map)
    if #entries == 0 then return end

    local layer = self:WorldLayer(canvas)
    layer:SetFrameLevel(canvas:GetFrameLevel() + 9)
    self.worldWidth, self.worldHeight = width, height
    local revision, index = self.worldRevision, 1
    local function Paint()
        if self.worldRevision ~= revision then return end
        local currentMap = Read(mapFrame.GetMapID, mapFrame)
        if InCombatLockdown() or not mapFrame:IsShown() or not Number(currentMap) or currentMap ~= map then
            self:ClearWorld()
            return
        end
        local scale = self:WorldScale()
        local last = math.min(#entries, index + PAINT_BATCH - 1)
        for at = index, last do
            local entry = entries[at]
            local point = self.worldPins[at]
            if not point then
                local icon = layer:CreateTexture(nil, "OVERLAY")
                point = { icon = icon }
                self.worldPins[at] = point
            end
            point.node, point.x, point.y = entry, entry.x * width, entry.y * height
            point.icon:SetTexture(entry.category.icon)
            point.icon:SetSize(WORLD_SIZE / scale, WORLD_SIZE / scale)
            point.icon:ClearAllPoints()
            point.icon:SetPoint("CENTER", layer, "TOPLEFT", point.x, -point.y)
            point.icon:Show()
            local key = math.floor(entry.x * HIT_CELLS) .. ":" .. math.floor(entry.y * HIT_CELLS)
            local bucket = self.worldGrid[key] or {}
            bucket[#bucket + 1] = point
            self.worldGrid[key] = bucket
        end
        self.worldCount = last
        index = last + 1
        if index <= #entries then C_Timer.After(0, Paint) end
    end
    Paint()
end

local function WorldPosition(map, x, y)
    if not C_Map or not CreateVector2D then return end
    local instance, position = Read(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    local wx, wy = XY(position)
    if Number(instance) and Number(wx) and Number(wy) then return instance, wx, wy end
end

function P:MiniEntries(map, filter)
    local cache = self.miniCache
    if cache and cache.map == map and cache.filter == filter then return cache.entries end
    local entries = MapPoints(map)
    for _, entry in ipairs(entries) do
        entry.instance, entry.wx, entry.wy = WorldPosition(map, entry.x, entry.y)
    end
    self.miniCache = { map = map, filter = filter, entries = entries }
    return entries
end

function P:ReleaseMiniPin(entry, pin)
    HideTooltip(pin)
    pin:Hide()
    pin.node = nil
    self.miniPins[entry] = nil
    self.freeMiniPins[#self.freeMiniPins + 1] = pin
end

function P:ClearMini()
    for entry, pin in pairs(self.miniPins) do self:ReleaseMiniPin(entry, pin) end
    self.miniView = nil
end

function P:AcquireMiniPin(entry, parent)
    local pin = self.miniPins[entry]
    if pin then return pin end
    pin = table.remove(self.freeMiniPins)
    if not pin then
        pin = CreateFrame("Frame", nil, parent)
        pin:SetSize(MINI_SIZE, MINI_SIZE)
        if pin.SetMouseClickEnabled and pin.SetMouseMotionEnabled then
            pin:SetMouseClickEnabled(false)
            pin:SetMouseMotionEnabled(true)
        else
            pin:EnableMouse(true)
            if pin.SetPropagateMouseClicks then pin:SetPropagateMouseClicks(true) end
            if pin.SetPropagateMouseMotion then pin:SetPropagateMouseMotion(true) end
        end
        pin.icon = pin:CreateTexture(nil, "ARTWORK")
        pin.icon:SetAllPoints(pin)
        pin:SetScript("OnEnter", ShowTooltip)
        pin:SetScript("OnLeave", HideTooltip)
    end
    pin.node = entry
    pin.icon:SetTexture(entry.category.icon)
    self.miniPins[entry] = pin
    return pin
end

function P:RenderMini(parent, visible)
    for entry, pin in pairs(self.miniPins) do
        if not visible[entry] then self:ReleaseMiniPin(entry, pin) end
    end
    for entry, position in pairs(visible) do
        local pin = self:AcquireMiniPin(entry, parent)
        if pin:GetParent() ~= parent then pin:SetParent(parent) end
        pin:SetFrameLevel(parent:GetFrameLevel() + 7)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", parent, "CENTER", position.x, position.y)
        pin:Show()
    end
end

function P:RefreshOverview(overview, filter)
    local view = overview.lastView
    local crop = view and view.crop
    local map = view and view.map
    if not crop or not Number(map) then self:ClearMini(); return end
    if self.miniView and self.miniView.overview == view and self.miniView.filter == filter then return end
    local visible = {}
    local base = view.art.base
    for _, entry in ipairs(self:MiniEntries(map, filter)) do
        local x = (entry.x * base.width - crop.left) * crop.scaleX
        local y = (entry.y * base.height - crop.top) * crop.scaleY
        if x >= 0 and x <= view.width and y >= 0 and y <= view.height then
            visible[entry] = { x = x - view.width / 2, y = view.height / 2 - y }
        end
    end
    self:RenderMini(overview.frame, visible)
    self.miniView = { overview = view, filter = filter }
end

function P:RefreshMini()
    local filter = Filter()
    if filter == "off" or InCombatLockdown() or not RP.CanUseFrame(Minimap) or not Minimap:IsVisible() then
        self:ClearMini()
        return
    end
    local overview = RP.MinimapOverview
    if overview and overview:IsShown() then self:RefreshOverview(overview, filter); return end

    local map = Read(C_Map and C_Map.GetBestMapForUnit, "player")
    local radius = Read(C_Minimap and C_Minimap.GetViewRadius)
    if not Number(map) or not Number(radius) or radius <= 0 then self:ClearMini(); return end
    local px, py, _, instance = Read(UnitPosition, "player")
    if not Number(px) or not Number(py) or not Number(instance) then
        local x, y = XY(Read(C_Map.GetPlayerMapPosition, map, "player"))
        if Fraction(x) and Fraction(y) then instance, px, py = WorldPosition(map, x, y) end
    end
    if not Number(px) or not Number(py) or not Number(instance) then self:ClearMini(); return end
    local width, height = Minimap:GetWidth(), Minimap:GetHeight()
    if not Number(width) or not Number(height) or width <= 0 or height <= 0 then self:ClearMini(); return end

    local facing = 0
    if RP.PublicTrue(Read(GetCVarBool, "rotateMinimap")) and not RP.PublicTrue(Read(C_Minimap.IsRotateMinimapIgnored)) then
        local angle = Read(GetPlayerFacing)
        if Number(angle) then facing = angle end
    end
    local shape = Read(GetMinimapShape)
    local square = RP.Readable(shape) and shape == "SQUARE"
    local previous = self.miniView
    if previous and previous.map == map and previous.filter == filter and previous.radius == radius
        and previous.x == px and previous.y == py and previous.instance == instance and previous.facing == facing
        and previous.width == width and previous.height == height and previous.square == square then return end
    local cos, sin = math.cos(facing), math.sin(facing)
    local visible = {}
    for _, entry in ipairs(self:MiniEntries(map, filter)) do
        if entry.instance == instance then
            local east, north = -(entry.wy - py) / radius, (entry.wx - px) / radius
            local x, y = east * cos + north * sin, -east * sin + north * cos
            if (square and math.abs(x) <= 1 and math.abs(y) <= 1) or (not square and x * x + y * y <= 1) then
                visible[entry] = { x = x * width / 2, y = y * height / 2 }
            end
        end
    end
    self:RenderMini(Minimap, visible)
    self.miniView = { map = map, filter = filter, radius = radius, instance = instance, x = px, y = py,
        width = width, height = height, facing = facing, square = square }
end

function P:HookWorldMap()
    local map = WorldMapFrame
    if self.mapHooked or not RP.CanUseFrame(map) then return end
    self.mapHooked = true
    map:HookScript("OnShow", function() self:RefreshWorld() end)
    map:HookScript("OnHide", function() self:ClearWorld() end)
    if hooksecurefunc and type(map.SetMapID) == "function" then
        hooksecurefunc(map, "SetMapID", function() self:RefreshWorld() end)
    end
    if hooksecurefunc and type(map.OnCanvasScaleChanged) == "function" then
        hooksecurefunc(map, "OnCanvasScaleChanged", function() self:ResizeWorldIcons() end)
    end
    local canvas = Read(map.GetCanvas, map)
    if RP.CanUseFrame(canvas) then canvas:HookScript("OnSizeChanged", function() self:RefreshWorld() end) end
end

local function Tick(frame, elapsed)
    frame.elapsed = frame.elapsed + elapsed
    if frame.elapsed < UPDATE_INTERVAL then return end
    frame.elapsed = 0
    P:RefreshMini()
    P:UpdateWorldHover()
end

function P:Refresh()
    self:HookWorldMap()
    self.miniCache = nil
    self:ClearMini()
    self:RefreshWorld()
    if Filter() ~= "off" and not InCombatLockdown() then
        self:RefreshMini()
        self.worker.elapsed = 0
        self.worker:SetScript("OnUpdate", Tick)
    else
        self.worker:SetScript("OnUpdate", nil)
    end
end

P.worker = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED", "MINIMAP_UPDATE_ZOOM", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    P.worker:RegisterEvent(event)
end
P.worker:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" then return end
    if event == "ZONE_CHANGED" or event == "MINIMAP_UPDATE_ZOOM" then P:RefreshMini() else P:Refresh() end
end)
