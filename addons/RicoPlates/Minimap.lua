local _, RP = ...
local M, T = {}, RP.Theme
RP.Minimap = M

local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK = "Textures\\MinimapMask"
local TRIM_WIDTH, TRIM_OVERHANG = 10, 6
local FOOTER_HEIGHT = 36
local SEGMENTS, BUBBLE_POINTS = 18, 12
local TAU = 2 * math.pi
local WHITE = "Interface\\Buttons\\WHITE8X8"
local unpack = unpack or table.unpack

local function IsExternalMinimap()
    if type(LeaPlusDB) == "table" and LeaPlusDB.MinimapModder == "On" then return true end
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if isLoaded then
        for _, name in ipairs({"SexyMap", "Chinchilla", "ForeverSquareMinimap", "TobarisuMap", "MagicMap"}) do
            if isLoaded(name) then return true end
        end
    end
    if type(GetMinimapShape) ~= "function" or GetMinimapShape == M.shape then return false end
    local ok, shape = pcall(GetMinimapShape)
    return ok and type(shape) == "string" and shape ~= "ROUND"
end

local function Preference(key, fallback)
    local read = C_CVar and C_CVar.GetCVarBool or GetCVarBool
    if not read then return fallback end
    local ok, value = pcall(read, key)
    if not ok or type(value) ~= "boolean" then return fallback end
    return value
end

local function ClockText(hours, minutes)
    return ("%02d:%02d"):format(hours, minutes)
end

local function Button(parent, label, width, height, tooltip, click)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(width, height)
    frame:SetFrameLevel(parent:GetFrameLevel() + 3)
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.label:SetPoint("CENTER")
    frame.label:SetFont(T.font, 11, "OUTLINE")
    frame.label:SetText(label)
    frame.label:SetTextColor(unpack(T.colors.text))
    frame:SetScript("OnClick", click)
    frame:SetHighlightTexture(WHITE, "ADD")
    frame:GetHighlightTexture():SetVertexColor(0.12, 0.35, 0.22, 0.45)
    frame:HookScript("OnEnable", function(self) self.label:SetAlpha(1) end)
    frame:HookScript("OnDisable", function(self) self.label:SetAlpha(0.4) end)
    frame:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        tooltip(GameTooltip)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    return frame
end

local function LineOf(text)
    return function(tooltip) tooltip:SetText(text) end
end

local function RingSurface(frame, layer, inset, thickness, r, g, b)
    local edges = {}
    for _, side in ipairs({"TOP", "RIGHT", "BOTTOM", "LEFT"}) do
        local edge = frame:CreateTexture(nil, layer)
        edge:SetColorTexture(r, g, b, 1)
        if side == "TOP" or side == "BOTTOM" then
            local y = side == "TOP" and -inset or inset
            edge:SetPoint(side .. "LEFT", frame, side .. "LEFT", inset, y)
            edge:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", -inset, y)
            edge:SetHeight(thickness)
        else
            local x = side == "LEFT" and inset or -inset
            edge:SetPoint("TOP" .. side, frame, "TOP" .. side, x, -inset)
            edge:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, x, inset)
            edge:SetWidth(thickness)
        end
        edges[#edges + 1] = edge
    end
    return edges
end

local function LiquidLine(frame, width)
    local line = frame:CreateLine(nil, "ARTWORK")
    line:SetBlendMode("ADD")
    line:SetThickness(width)
    return line
end

local function BuildTrim(hud)
    local trim = {waves = {}, bubbles = {}}
    trim.base = RingSurface(hud, "BACKGROUND", 1, TRIM_WIDTH - 1, 0.05, 0.28, 0.15)
    RingSurface(hud, "BORDER", 0, 1, 0.46, 0.38, 0.22)
    RingSurface(hud, "BORDER", TRIM_WIDTH - 1, 1, 0.055, 0.12, 0.09)
    for i = 1, 3 do
        local wave = {}
        for j = 1, SEGMENTS * 4 do
            wave[j] = {glow = LiquidLine(hud, 3.2), core = LiquidLine(hud, 1.15)}
        end
        trim.waves[i] = wave
    end
    for i = 1, 7 do
        local bubble = {}
        for j = 1, BUBBLE_POINTS do bubble[j] = LiquidLine(hud, 0.85) end
        trim.bubbles[i] = bubble
    end
    return trim
end

local function BorderPoint(width, height, side, progress, inset)
    if side == 1 then return inset + (width - 2 * inset) * progress, height - inset end
    if side == 2 then return width - inset, height - inset - (height - 2 * inset) * progress end
    if side == 3 then return width - inset - (width - 2 * inset) * progress, inset end
    return inset, inset + (height - 2 * inset) * progress
end

local function PlaceLine(line, frame, x1, y1, x2, y2)
    line:SetStartPoint("BOTTOMLEFT", frame, x1, y1)
    line:SetEndPoint("BOTTOMLEFT", frame, x2, y2)
end

function M:PaintTrim()
    local width = self.map:GetWidth() + 2 * TRIM_OVERHANG
    local height = self.map:GetHeight() + 2 * TRIM_OVERHANG + FOOTER_HEIGHT
    local lengths = {width, height, width, height}
    local starts = {0, width, width + height, 2 * width + height}
    local perimeter = 2 * (width + height)
    local tint = T.headerTint or T.colors.accent
    local r, g, b = unpack(tint)
    local clock = self.trimClock
    if tint ~= self.trimTint then
        for _, edge in ipairs(self.trim.base) do edge:SetColorTexture(0.025 + r * 0.33, 0.035 + g * 0.33, 0.03 + b * 0.33, 1) end
        self.trimTint = tint
    end

    -- A single phase around the perimeter keeps the wave continuous at each corner.
    for strand, wave in ipairs(self.trim.waves) do
        local firstX, firstY, previousX, previousY
        for j = 0, #wave do
            local x, y, arc
            if j == #wave then x, y, arc = firstX, firstY, TAU
            else
                local side = math.floor(j / SEGMENTS) + 1
                local progress = (j % SEGMENTS) / SEGMENTS
                arc = TAU * (starts[side] + lengths[side] * progress) / perimeter
                local phase = strand * 2.399
                local inset = 4.5 + strand * 0.25 + 1.45 * math.sin(3 * arc + phase - clock * 0.32)
                    + 0.62 * math.sin(7 * arc - phase + clock * 0.27)
                x, y = BorderPoint(width, height, side, progress, inset)
            end
            if j == 0 then firstX, firstY = x, y
            else
                local segment = wave[j]
                local shine = 0.22 + 0.5 * math.sin(5 * arc + strand - clock * 0.5) ^ 4
                segment.glow:SetColorTexture(r, g, b, 0.22)
                segment.core:SetColorTexture(0.40 + r * 0.60, 0.28 + g * 0.72, 0.28 + b * 0.72, shine)
                PlaceLine(segment.glow, self.hud, previousX, previousY, x, y)
                PlaceLine(segment.core, self.hud, previousX, previousY, x, y)
            end
            previousX, previousY = x, y
        end
    end

    for i, bubble in ipairs(self.trim.bubbles) do
        local progress = (clock * (0.045 + i * 0.001) + i * 0.143) % 1
        local distance = progress * perimeter
        local side = distance >= starts[4] and 4 or distance >= starts[3] and 3 or distance >= starts[2] and 2 or 1
        local inset = 5.2 + 0.65 * math.sin(clock * 0.65 + i)
        local x, y = BorderPoint(width, height, side, (distance - starts[side]) / lengths[side], inset)
        local radius = 1.4 + (i % 3) * 0.36
        local alpha = math.min(1, progress * 12, (1 - progress) * 12) * 0.72
        local previousX, previousY = x + radius, y
        for j, line in ipairs(bubble) do
            local angle = TAU * j / BUBBLE_POINTS
            local nextX, nextY = x + radius * math.cos(angle), y + radius * math.sin(angle)
            line:SetColorTexture(0.45 + r * 0.55, 0.45 + g * 0.55, 0.45 + b * 0.55, alpha * (j < 7 and 1 or 0.35))
            PlaceLine(line, self.hud, previousX, previousY, nextX, nextY)
            previousX, previousY = nextX, nextY
        end
    end
end

function M:Build(map)
    if self.hud then return end
    local hud = CreateFrame("Frame", nil, map)
    hud:SetPoint("TOPLEFT", map, "TOPLEFT", -TRIM_OVERHANG, TRIM_OVERHANG)
    hud:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", TRIM_OVERHANG, -TRIM_OVERHANG - FOOTER_HEIGHT)
    hud:SetFrameLevel(map:GetFrameLevel() + 13)
    hud:EnableMouse(false)
    self.trim, self.trimClock = BuildTrim(hud), 0

    local footer = CreateFrame("Frame", nil, hud)
    footer:SetPoint("TOPLEFT", map, "BOTTOMLEFT", TRIM_WIDTH - TRIM_OVERHANG, 1)
    footer:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -TRIM_WIDTH, TRIM_WIDTH)
    footer:SetFrameLevel(hud:GetFrameLevel())
    footer:EnableMouse(false)
    T:Fill(footer, 0.031, 0.069, 0.053)
    local seam = footer:CreateTexture(nil, "BORDER")
    seam:SetColorTexture(0.15, 0.25, 0.18, 1)
    seam:SetPoint("TOPLEFT")
    seam:SetPoint("TOPRIGHT")
    seam:SetHeight(1)

    self.clock = Button(footer, "", 37, 20, function(tooltip)
        tooltip:SetText("Time")
        if M.localText then tooltip:AddLine("Local: " .. M.localText, 0.90, 0.94, 0.93) end
        if M.realmText then tooltip:AddLine("Realm: " .. M.realmText, 0.90, 0.94, 0.93) end
        if TimeManager_Toggle then tooltip:AddLine("Click to open the clock.", 0.55, 0.64, 0.62) end
    end, function() if TimeManager_Toggle then TimeManager_Toggle() end end)
    self.clock:SetPoint("RIGHT", footer, "RIGHT", -2, 0)
    self.clock.label:SetTextColor(unpack(T.colors.mint))
    self.zoomOut = Button(footer, "−", 17, 20, function(tooltip)
        tooltip:SetText("Zoom out")
        if RP.db.minimapOverview then tooltip:AddLine("One more step opens the area overview outdoors.", 0.55, 0.64, 0.62) end
    end, function() M:Zoom(-1) end)
    self.zoomOut:SetPoint("LEFT", footer, "LEFT", 2, 0)
    self.zoomIn = Button(footer, "+", 17, 20, LineOf("Zoom in"), function() M:Zoom(1) end)
    self.zoomIn:SetPoint("LEFT", self.zoomOut, "RIGHT", 0, 0)

    self.location = Button(footer, "", 100, 24, function(tooltip)
        tooltip:SetText(M.locationText or "Location")
        if ToggleWorldMap then tooltip:AddLine("Click to open the world map.", 0.55, 0.64, 0.62) end
    end, function() if ToggleWorldMap then ToggleWorldMap() end end)
    self.location:SetPoint("TOPLEFT", footer, "TOPLEFT", 39, -2)
    self.location:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -39, 2)
    self.location.label:SetFont(T.font, 10, "OUTLINE")
    self.location.label:SetJustifyH("CENTER")
    self.location.label:SetWordWrap(false)
    self.footer = footer
    self.hud = hud
    hud:Hide()
end

function M:UpdateClock()
    if not self.clock or not self.clock:IsShown() then return end
    local now = date("*t")
    self.localText = ClockText(now.hour, now.min)
    local hour, minute
    if GetGameTime then hour, minute = GetGameTime() end
    self.realmText = RP.Readable(hour) and RP.Readable(minute) and type(hour) == "number"
        and type(minute) == "number" and ClockText(hour, minute) or nil
    local caption = Preference("timeMgrUseLocalTime", true) and self.localText or self.realmText or self.localText
    if caption ~= self.clockText then
        self.clock.label:SetText(caption)
        self.clockText = caption
    end
end

local function ZoneName(getName)
    local name = getName and getName()
    if RP.Readable(name) and type(name) == "string" and name ~= "" then return name end
end

function M:UpdateLocation()
    if not self.active then return end
    local name = ZoneName(GetMinimapZoneText) or ZoneName(GetZoneText)
    self.locationText = name
    self.location.label:SetText(name or "")
end

function M:LayoutLocation()
    if not self.active then return end
    -- Forever draws coordinates itself. Leave its line clear above the location.
    local coordinatesEnabled = Preference("minimapShowPlayerCoords", true)
    local label = self.location.label
    label:ClearAllPoints()
    local left = coordinatesEnabled and "BOTTOMLEFT" or "LEFT"
    local right = coordinatesEnabled and "BOTTOMRIGHT" or "RIGHT"
    label:SetPoint(left, self.location, left, 2, 0)
    label:SetPoint(right, self.location, right, -2, 0)
end

function M:DockNative(frame, level, point, relative, relativePoint, x, y)
    if not RP.CanUseFrame(frame) then return end
    local original = self.nativeControls[frame]
    if not original then
        original = {level = frame:GetFrameLevel()}
        self.nativeControls[frame] = original
        self.nativeOrder[#self.nativeOrder + 1] = frame
    end
    if point then
        local count = frame:GetNumPoints()
        local a, b, c, d, e = frame:GetPoint(1)
        local docked = count == 1 and a == point and b == relative and c == relativePoint and d == x and e == y
        if not original.points or not docked then
            original.points = {}
            for i = 1, count do original.points[i] = {frame:GetPoint(i)} end
        end
        if not docked then
            frame:ClearAllPoints()
            frame:SetPoint(point, relative, relativePoint, x, y)
        end
    end
    frame:SetFrameLevel(level)
    return true
end

function M:PlaceNativeControls()
    if not self.active or RP:IsInCombat() then return end
    local cluster, map = MinimapCluster, self.map
    if cluster and self.layoutHook ~= cluster and hooksecurefunc then
        for _, method in ipairs({"SetEditModeScale", "SetHeaderUnderneath"}) do
            if type(cluster[method]) == "function" then
                hooksecurefunc(cluster, method, function() M:PlaceNativeControls() end)
            end
        end
        self.layoutHook = cluster
    end
    local level = self.hud:GetFrameLevel() + 4
    local tracking = cluster and cluster.Tracking
    local trackingButton = tracking and tracking.Button
    local trackingButtonLevel = RP.CanUseFrame(trackingButton) and not self.nativeControls[trackingButton]
        and trackingButton:GetFrameLevel()
    self:DockNative(cluster and cluster.DielFrame, level, "CENTER", map, "TOP", 0, 0)
    if self:DockNative(tracking, level, "TOPLEFT", map, "TOPLEFT", 8, -8)
        and self:DockNative(trackingButton, level + 1) and trackingButtonLevel then
        self.nativeControls[trackingButton].level = trackingButtonLevel
    end
    local calendar = GameTimeFrame
    local hasCalendar = self:DockNative(calendar, level, "TOPRIGHT", map, "TOPRIGHT", -8, -8)
    if hasCalendar then self:DockNative(AddonCompartmentFrame, level, "RIGHT", calendar, "LEFT", -4, 0) end
end

function M:RestoreNativeControls()
    for _, frame in ipairs(self.nativeOrder) do
        if RP.CanUseFrame(frame) then
            local original = self.nativeControls[frame]
            if original.points then
                frame:ClearAllPoints()
                for _, point in ipairs(original.points) do frame:SetPoint(unpack(point, 1, 5)) end
            end
            frame:SetFrameLevel(original.level)
        end
    end
end

function M:Mute(region, blockMouse)
    if not RP.CanUseFrame(region) or not region.SetAlpha then return end
    if not self.muted[region] then
        local old = {alpha = region:GetAlpha()}
        if blockMouse and region.IsMouseEnabled then old.mouse = region:IsMouseEnabled() end
        self.muted[region] = old
    end
    region:SetAlpha(0)
    if blockMouse and region.EnableMouse then region:EnableMouse(false) end
end

function M:Unmute(region)
    local old = region and self.muted[region]
    if not old then return end
    region:SetAlpha(old.alpha)
    if old.mouse ~= nil then region:EnableMouse(old.mouse) end
    self.muted[region] = nil
end

function M:RefreshCosmetics()
    self.map:SetMaskTexture(SQUARE_MASK)
    self:Mute(MinimapCompassTexture)
    self:Mute(MinimapCompassTextureUnderlay)
    self:Mute(MinimapBorder)
    self:Mute(self.map.ZoomIn or MinimapZoomIn, true)
    self:Mute(self.map.ZoomOut or MinimapZoomOut, true)
    self:Mute(self.map.ZoomHitArea, true)
    local zoneButton = MinimapCluster and MinimapCluster.ZoneTextButton or MinimapZoneTextButton
    self:Mute(zoneButton, true)
    self:PlaceNativeControls()
    self.clock:SetShown(RP.db.minimapClock)
    if RP.db.minimapClock then self:Mute(TimeManagerClockButton, true)
    else self:Unmute(TimeManagerClockButton) end
    self:UpdateClock()
    self:UpdateLocation()
    self:LayoutLocation()
end

function M:IsOverview()
    return RP.MinimapOverview and RP.MinimapOverview:IsShown()
end

function M:RefreshZoom()
    if not self.active then return end
    local zoom, count = self.map:GetZoom(), self.map:GetZoomLevels()
    if zoom > 0 and self:IsOverview() then RP.MinimapOverview:Hide() end
    self.zoomIn:SetEnabled(self:IsOverview() or zoom < count - 1)
    self.zoomOut:SetEnabled(not self:IsOverview() and (zoom > 0 or (RP.db.minimapOverview and RP.MinimapOverview ~= nil)))
end

function M:Zoom(delta)
    if not self.active or delta == 0 then return end
    local overview, map = RP.MinimapOverview, self.map
    if self:IsOverview() then
        if delta > 0 then overview:Hide() end
    elseif delta < 0 and map:GetZoom() == 0 then
        if RP.db.minimapOverview and overview and not overview:Show(map) then
            local now = GetTime()
            if not self.lastOverviewUnavailable or now - self.lastOverviewUnavailable >= 3 then
                self.lastOverviewUnavailable = now
                RP:Print("The area overview is unavailable here.")
            end
        end
    else
        local nextZoom = map:GetZoom() + (delta > 0 and 1 or -1)
        nextZoom = math.max(0, math.min(map:GetZoomLevels() - 1, nextZoom))
        if nextZoom ~= map:GetZoom() then map:SetZoom(nextZoom) end
    end
    self:RefreshZoom()
end

local function RefreshPins()
    if RicoLauncher and RicoLauncher.PlaceButton then RicoLauncher:PlaceButton() end
    local mining = RicoMining and RicoMining.Map
    if mining and mining.RefreshMini then mining:RefreshMini() end
end

function M:Disable()
    if not self.active then return end
    self.active = false
    local map = self.map
    if RP.MinimapOverview then RP.MinimapOverview:Hide() end
    self.hud:Hide()
    self.hud:SetScript("OnUpdate", nil)
    self:RestoreNativeControls()
    if map:GetScript("OnMouseWheel") == self.wheel then
        map:SetScript("OnMouseWheel", self.previousWheel)
        map:EnableMouseWheel(self.previousWheelEnabled)
    end
    if GetMinimapShape == self.shape then GetMinimapShape = self.previousShape end
    if not self.external then map:SetMaskTexture(self.previousMask) end
    for region in pairs(self.muted) do self:Unmute(region) end
    RefreshPins()
end

function M:UpdateSettings()
    if not self.events or not RP.db or RP:IsInCombat() then return end
    local map = Minimap
    self.external = IsExternalMinimap()
    if not RP.db.enabled or not RP.db.squareMinimap or self.external
        or not RP.CanUseFrame(map) or not map.SetMaskTexture or not map.GetZoom or not map.GetZoomLevels then
        self:Disable()
        return
    end
    if self.active then
        if not RP.db.minimapOverview and self:IsOverview() then RP.MinimapOverview:Hide() end
        self:RefreshCosmetics()
        self:RefreshZoom()
        return
    end

    self.map, self.muted = map, {}
    self.nativeControls, self.nativeOrder = {}, {}
    self:Build(map)
    self.previousMask = (map.GetMaskTexture and map:GetMaskTexture()) or ROUND_MASK
    self.previousShape = GetMinimapShape
    self.previousWheel = map:GetScript("OnMouseWheel")
    self.previousWheelEnabled = not map.IsMouseWheelEnabled or map:IsMouseWheelEnabled()
    GetMinimapShape = self.shape
    map:EnableMouseWheel(true)
    map:SetScript("OnMouseWheel", self.wheel)
    self.active = true
    self:RefreshCosmetics()
    self:RefreshZoom()
    self.hud:Show()
    self:PaintTrim()
    local clockElapsed, mapElapsed, trimElapsed = 0, 0, 0
    self.hud:SetScript("OnUpdate", function(_, elapsed)
        trimElapsed = trimElapsed + elapsed
        if trimElapsed >= 1 / 20 then
            M.trimClock = (M.trimClock + trimElapsed * 2) % 3600
            trimElapsed = 0
            M:PaintTrim()
        end
        clockElapsed = clockElapsed + elapsed
        if clockElapsed >= 1 then clockElapsed = 0; M:UpdateClock() end
        if M:IsOverview() then
            mapElapsed = mapElapsed + elapsed
            if mapElapsed >= 0.12 then
                mapElapsed = 0
                if not RP.MinimapOverview:Refresh() then
                    RP.MinimapOverview:Hide()
                    M:RefreshZoom()
                end
            end
        end
    end)
    RefreshPins()
end

function M:GetStatus()
    if not RP.db.enabled or not RP.db.squareMinimap then return "Rico minimap styling is disabled." end
    if self.external then return "Another addon manages the minimap. Turn off its minimap skin to use Rico's." end
    if self.active then return "Rico square minimap is active." end
    return "Minimap changes apply after combat or when the minimap is available."
end

function M:Initialize()
    if self.events then return end
    self.shape = function() return "SQUARE" end
    if RP.MinimapOverview then RP.MinimapOverview:SetWheelHandler(function(delta) M:Zoom(delta) end) end
    self.wheel = function(_, delta) M:Zoom(delta) end
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "CVAR_UPDATE",
        "MINIMAP_UPDATE_ZOOM", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, value)
        if event == "MINIMAP_UPDATE_ZOOM" then M:RefreshZoom()
        elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then M:UpdateLocation()
        elseif event == "CVAR_UPDATE" then
            local key = type(value) == "string" and value:lower()
            if key == "rotateminimap" then M:UpdateSettings()
            elseif key == "timemgruselocaltime" then M:UpdateClock()
            elseif key == "minimapshowplayercoords" then M:LayoutLocation() end
        elseif event == "ADDON_LOADED" then
            if value == "Blizzard_Minimap" or value == "Blizzard_TimeManager" or IsExternalMinimap() then M:UpdateSettings() end
        else M:UpdateSettings() end
    end)
end
