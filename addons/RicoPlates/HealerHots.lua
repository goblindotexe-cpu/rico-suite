-- The native container filters and renders real auras, including restricted
-- combat data. No spell name matching, inferred timers or aura scans in Lua.
local _, RP = ...
local H = { records = setmetatable({}, { __mode = "k" }) }
RP.HealerHots = H

local FILTER = "HELPFUL|PLAYER"
local GROUP = "RicoPlatesHealerHots"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local spellRanks = {
    -- Renew, Rejuvenation and Regrowth: all Forever trainer/book ranks.
    {139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315},
    {774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299},
    {8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858},
    -- Wild Growth, Tranquility and Riptide.
    {408120, 1238214, 1238215},
    {740, 8918, 9862, 9863},
    {408521, 1239242, 1239243},
    -- Gnome priest Contingency Plan: the periodic heal, after the ward procs.
    {1277456, 1277457, 1277458, 1277459, 1277460},
}
local spellIDs = {}
for _, ranks in ipairs(spellRanks) do
    for _, spellID in ipairs(ranks) do spellIDs[spellID] = true end
end

local sizes = { compact = 12, standard = 15, unit = 16 }
local limits = { compact = 2, standard = 3, unit = 4 }
local timerOptions

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Enabled(record)
    local db = RP.db
    return db and db.enabled ~= false and db.healerHots ~= false
        and (record.kind == "unit" or db.partyFrames ~= false)
end

local function TimerOptions()
    if timerOptions then return timerOptions end
    local properties = Enum and Enum.DurationTextBindingProperty
    if not properties or not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not CreateColor then return nil end
    local ok, options = pcall(function()
        local curve = C_CurveUtil.CreateColorCurve()
        curve:AddPoint(0, CreateColor(1, 0.43, 0.16))
        curve:AddPoint(1.3, CreateColor(1, 0.74, 0.23))
        curve:AddPoint(2.9, CreateColor(1, 0.86, 0.39))
        curve:AddPoint(3.1, CreateColor(0.97, 1, 0.96))
        return { textColor = { curve = curve, property = properties.RemainingDuration } }
    end)
    if ok then timerOptions = options end
    return timerOptions
end

local function AddRefreshGlow(button)
    if type(button.AddPandemicRegion) ~= "function" then return end
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(GLOW)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.72, 0.20)
    glow:SetPoint("TOPLEFT", -5, 5)
    glow:SetPoint("BOTTOMRIGHT", 5, -5)
    glow:Hide()
    if type(button.AddPandemicActiveAnimation) == "function" then
        local pulse = glow:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local alpha = pulse:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0.4)
        alpha:SetToAlpha(1)
        alpha:SetDuration(0.52)
        pcall(button.AddPandemicActiveAnimation, button, pulse)
    end
    -- Only the engine knows which spells have a refresh carry-over window.
    pcall(button.AddPandemicRegion, button, glow)
end

local function InitializeButton(button, size)
    button:SetSize(size, size)
    -- Let the original unit frame retain its targeting and click-casts.
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(true) end
    if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_TOPRIGHT", 0, 3) end

    local edge = button:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(button)
    edge:SetTexture(WHITE)
    edge:SetVertexColor(0.12, 0.34, 0.22)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button:SetIcon(icon)

    local shade = button:CreateTexture(nil, "ARTWORK", nil, 1)
    shade:SetAllPoints(icon)
    shade:SetTexture(WHITE)
    shade:SetVertexColor(0, 0, 0, 0.30)
    local timer = button:CreateFontString(nil, "OVERLAY")
    timer:SetFont(RP.Theme.font, size <= 12 and 9 or 11, "OUTLINE")
    timer:SetPoint("CENTER", 0, 0)
    timer:SetTextColor(0.97, 1, 0.96)
    local options = TimerOptions()
    if not options or not pcall(button.SetDurationText, button, timer, options) then
        button:SetDurationText(timer)
    end
    AddRefreshGlow(button)
end

local function Build(record)
    local parent, anchor, kind = record.parent, record.anchor, record.kind
    local compact, standalone = kind == "compact", kind == "unit"
    local size = sizes[kind]
    local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    record.container = container
    container:Hide()
    container:SetEnabled(false)
    container:EnableMouse(false)
    container:SetSize(size, size)
    -- Party native buffs use the area below the bars; the dispel badge uses
    -- the top right. A shallow bottom-left lane avoids both.
    local point = standalone and "RIGHT" or "BOTTOMLEFT"
    container:SetPoint(point, anchor, point, standalone and -3 or 3, standalone and 0 or 2)
    container:SetFrameLevel(parent:GetFrameLevel() + 10)
    if container.SetEditModePreviewEnabled then container:SetEditModePreviewEnabled(false) end
    container:SetFlowLayoutAnchorPoint(standalone and "TOPRIGHT" or "BOTTOMLEFT")
    if container.SetFlowLayoutGrowthDirection and AnchorUtil and AnchorUtil.FlowDirection then
        local directions = AnchorUtil.FlowDirection
        container:SetFlowLayoutGrowthDirection(standalone and directions.Left or directions.Right, directions.Up)
    end
    container:SetFlowLayoutMaximumLineSize(math.huge)
    container:AddAuraGroup(GROUP, FILTER, {
        maxFrameCount = limits[kind],
        candidateFilters = { includeSpellIDs = spellIDs },
        sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.ExpirationOnly,
        initializeFrame = function(button) InitializeButton(button, size) end,
        layout = { elementSpacing = compact and 2 or 3, lineSpacing = 0 },
    })
    record.built = true
end

local function HideNative(record)
    if not record.nativeUnit then return end
    local container = record.container
    container:Hide()
    container:SetEnabled(false)
    container:SetUnit("")
    record.nativeUnit = nil
end

local function UpdateNative(record, force)
    local unit = record.unit
    if not unit or not Enabled(record) then HideNative(record); return end
    if not record.built then Build(record) end
    local container = record.container
    if record.nativeUnit ~= unit then
        if record.nativeUnit then HideNative(record) end
        container:SetUnit(unit)
        container:SetEnabled(true)
        container:Show()
        record.nativeUnit = unit
    elseif force and container.UpdateAllAuras then
        container:UpdateAllAuras()
    end
end

local function Update(record, force)
    if record.failed then return end
    local ok, message = pcall(UpdateNative, record, force)
    if not ok then
        -- Keep a malformed or unavailable native widget from disabling a unit
        -- frame. Its creation and failure are isolated to this display.
        record.failed = true
        if record.container then
            pcall(record.container.Hide, record.container)
            pcall(record.container.SetEnabled, record.container, false)
        end
        if Public(message) and type(message) == "string" then H.lastError = message:sub(1, 200) end
    end
end

function H:Attach(owner, unit, parent, anchor, kind, force)
    if not Public(unit) or type(unit) ~= "string" or unit == "" then self:Hide(owner); return end
    if not owner or not parent or not anchor then return end
    kind = sizes[kind] and kind or "unit"
    local record = self.records[owner]
    if not record then
        record = { parent = parent, anchor = anchor, kind = kind }
        self.records[owner] = record
    end
    record.unit = unit
    Update(record, force)
end

function H:Hide(owner)
    local record = self.records[owner]
    if record then
        record.unit = nil
        Update(record)
    end
end

function H:RefreshAll()
    for _, record in pairs(self.records) do Update(record) end
end
