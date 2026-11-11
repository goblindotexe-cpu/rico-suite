local _, RP = ...
local X = { muted = {}, hooked = {} }
RP.ExperienceBar = X

local HEIGHT = 14
local GREEN = { 0.23, 0.83, 0.58 }
local RESTED_BLUE = { 0.19, 0.72, 1.00 }

local function Read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and RP.Readable(value) then return value end
end

local function Number(value)
    return type(value) == "number" and value == value and value < math.huge and value > -math.huge
end

local function InEditMode()
    local manager = EditModeManagerFrame
    return manager and Read(manager.IsShown, manager) == true and Read(manager.IsEditModeActive, manager) == true
end

local function CanMute(region)
    return RP.CanUseFrame(region) and type(region.SetAlpha) == "function"
        and not (region.IsProtected and Read(region.IsProtected, region) ~= false)
end

function X:SyncNative()
    if Read(InCombatLockdown) == true then return end
    local desired = {}
    local manager = StatusTrackingBarManager
    local indices = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    local index = indices and indices.Experience
    if index and RP.CanUseFrame(manager) and self.frame and self.frame:IsShown() then
        for _, container in ipairs(manager.barContainers or {}) do
            local xp = container.bars and container.bars[index]
            if CanMute(container) and CanMute(xp) then
                if not self.hooked[container] and hooksecurefunc then
                    self.hooked[container] = true
                    for _, method in ipairs({ "ApplyPendingBarToShow", "UpdateDividers" }) do
                        if type(container[method]) == "function" then
                            pcall(hooksecurefunc, container, method, function() X:SyncNative() end)
                        end
                    end
                end
                if Read(container.GetShownBar, container) == xp then
                    desired[xp] = true
                    if CanMute(container.BarFrameTexture) then desired[container.BarFrameTexture] = true end
                    local dividers = container.HorizontalDividersPool
                    if dividers and type(dividers.EnumerateActive) == "function" then
                        for divider in dividers:EnumerateActive() do
                            if CanMute(divider) then desired[divider] = true end
                        end
                    end
                end
            end
        end
    end
    for region, alpha in pairs(self.muted) do
        if not desired[region] then
            if CanMute(region) and Read(region.GetAlpha, region) == 0 then region:SetAlpha(alpha) end
            self.muted[region] = nil
        end
    end
    for region in pairs(desired) do
        local alpha = Read(region.GetAlpha, region)
        if Number(alpha) and alpha > 0 then
            self.muted[region] = alpha
            region:SetAlpha(0)
        end
    end
end

local function MakeSegment(frame, tint, base)
    local segment = CreateFrame("Frame", nil, frame)
    segment:EnableMouse(false)
    segment:SetSize(1, HEIGHT - 2)
    segment:SetClipsChildren(true)
    segment:Hide()
    RP.Theme:Fill(segment, base[1], base[2], base[3], 1)
    segment.liquid = RP.Theme:Liquid(segment, { health = true, manual = true, width = 1,
        height = HEIGHT - 2, color = tint, waveScale = 68, segments = 56, bubbleCount = 2, bubbleScale = 0.7 })
    segment.liquid.fps = 16
    segment:SetScript("OnShow", function(self) self.liquid:Start() end)
    segment:SetScript("OnHide", function(self) self.liquid:Stop() end)
    return segment
end

local function SetSegment(segment, x, width)
    if width <= 0 then
        segment:Hide()
        return
    end
    if segment.start ~= x then
        segment.start = x
        segment:SetPoint("BOTTOMLEFT", segment:GetParent(), "BOTTOMLEFT", x, 1)
    end
    if segment.liquid.width ~= width then
        segment:SetWidth(width)
        segment.liquid.width = width
        if segment:IsVisible() then segment.liquid:Paint() end
    end
    segment:Show()
end

local function Amount(value)
    local formatted = Read(BreakUpLargeNumbers, value)
    return type(formatted) == "string" and formatted or ("%d"):format(value)
end

function X:Refresh()
    local frame = self.frame
    if not frame then return end
    local rules = GameRulesUtil
    local show = Read(rules and rules.CanShowExperienceBar)
    local maxXP = Read(UnitXPMax, "player")
    local current = Read(UnitXP, "player")
    local width = frame:GetWidth()
    if not Number(width) or width <= 0 then width = Read(UIParent.GetWidth, UIParent) end
    if (RP.db and RP.db.enabled == false) or InEditMode() or show == false
        or Read(IsXPUserDisabled) == true or Read(rules and rules.IsPlayerAtEffectiveMaxLevel) == true
        or not Number(maxXP) or maxXP <= 0 or not Number(current) or not Number(width) or width <= 0 then
        frame:Hide()
        self:SyncNative()
        return
    end

    current = math.max(0, math.min(current, maxXP))
    local rested = Read(GetXPExhaustion)
    rested = Number(rested) and math.max(0, math.min(rested, maxXP - current)) or 0
    local usable = math.max(0, width - 2)
    local currentWidth = current / maxXP * usable
    SetSegment(frame.gained, 1, currentWidth)
    SetSegment(frame.rested, 1 + currentWidth, rested / maxXP * usable)
    frame.label:SetText(("%.1f%%  ·  %s / %s XP"):format(current / maxXP * 100, Amount(current), Amount(maxXP)))
    frame:Show()
    self:SyncNative()
end

function X:Initialize()
    if self.frame then return end
    local frame = CreateFrame("Frame", "RicoExperienceBar", UIParent)
    self.frame = frame
    frame:Hide()
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(false)
    frame:SetHeight(HEIGHT)
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    RP.Theme:Fill(frame, 0.024, 0.043, 0.047, 0.95)
    RP.Theme:Border(frame)

    frame.gained = MakeSegment(frame, GREEN, { 0.052, 0.252, 0.167 })
    frame.rested = MakeSegment(frame, RESTED_BLUE, { 0.028, 0.218, 0.400 })
    local textLayer = CreateFrame("Frame", nil, frame)
    textLayer:SetAllPoints()
    textLayer:EnableMouse(false)
    textLayer:SetFrameLevel(frame:GetFrameLevel() + 4)
    frame.label = textLayer:CreateFontString(nil, "OVERLAY")
    frame.label:SetFont(RP.Theme.font, 10, "OUTLINE")
    frame.label:SetPoint("CENTER", textLayer, "CENTER", 0, 0)
    frame.label:SetTextColor(0.95, 1, 0.98)
    frame.label:SetShadowColor(0, 0, 0, 1)
    frame.label:SetShadowOffset(1, -1)
    frame:SetScript("OnSizeChanged", function() X:Refresh() end)

    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MAX_LEVEL_UPDATE",
        "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "UPDATE_EXPANSION_LEVEL",
        "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_REGEN_ENABLED", "ADDON_LOADED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, name)
        if event ~= "ADDON_LOADED" or name == "Blizzard_StatusTrackingBar" then X:Refresh() end
    end)
    if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        for _, event in ipairs({ "EditMode.Enter", "EditMode.Exit" }) do
            EventRegistry:RegisterCallback(event, function() X:Refresh() end, X)
        end
    end
    self:Refresh()
end
