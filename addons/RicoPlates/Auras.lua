-- Independent buff and debuff rows. Blizzard's public AuraContainer widget
-- owns aura selection and rendering, including restricted combat aura data.
-- RicoPlates styles each button only in its documented creation callback.
local _, RP = ...
local A = { states = {}, pending = {}, queue = {}, head = 1, tail = 0,
    stats = { errors = 0, scans = 0 }, seenErrors = {} }
RP.Auras = A

local BASE_SIZE, BASE_GAP, DEFAULT_MAX, HARD_MAX = 18, 3, 6, 10
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = RP.Theme.font
local ROWS = {
    { key = "debuffs", group = "RicoPlatesDebuffs", filter = "HARMFUL", label = "Debuff",
      enabled = "showDebuffs", size = "debuffSize", maximum = "maxDebuffs", mine = "debuffsMineOnly",
      stateField = "auraState", containerField = "debuffContainer" },
    { key = "buffs", group = "RicoPlatesBuffs", filter = "HELPFUL", label = "Buff",
      enabled = "showBuffs", size = "buffSize", maximum = "maxBuffs", mine = "buffsMineOnly",
      stateField = "buffAuraState", containerField = "buffContainer" },
}

local function Secret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function Public(value)
    if Secret(value) then return nil end
    return value
end

local function Token(unit)
    return not Secret(unit) and type(unit) == "string" and unit ~= ""
end

local function AccessibleTable(value)
    if Secret(value) or type(value) ~= "table" then return false end
    if canaccesstable and not canaccesstable(value) then return false end
    return true
end

local function Enabled(spec)
    return RP.db and RP.db.enabled ~= false and RP.db[spec.enabled] ~= false
end

local function Filter(spec, plate)
    -- The selected HUD target must remain informative even when the optional
    -- world/nameplate filter is set to auras cast by the player only.
    if spec.key == "buffs" and plate and plate.unitFrame and plate.unit == "target"
        and RP.db.targetBuffsAll ~= false then return spec.filter end
    return spec.filter .. (RP.db[spec.mine] and "|PLAYER" or "")
end

function A:Error(stage, message)
    message = Public(message)
    if type(message) ~= "string" then message = "Unreadable API data" end
    message = message:sub(1, 200)
    local key = stage .. ": " .. message
    self.stats.lastError = key
    if not self.seenErrors[key] then
        self.seenErrors[key] = true
        self.stats.errors = self.stats.errors + 1
    end
end

local function SafeMethod(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false end
    return pcall(object[method], object, ...)
end

local function Dimensions(spec, plate)
    local size = tonumber(RP.db[spec.size]) or BASE_SIZE
    size = math.max(12, math.min(30, size))
    local gap = BASE_GAP * size / BASE_SIZE
    local width = tonumber(plate and plate.style and plate.style.width) or tonumber(RP.db.width) or 190
    local requested = math.floor(tonumber(RP.db[spec.maximum]) or DEFAULT_MAX)
    local limit = math.max(1, math.min(HARD_MAX, requested, math.floor((width + gap) / (size + gap))))
    return size, gap, limit
end

-- All decoration happens before a native aura button acquires its access
-- restrictions. The returned references are retained only for our own fallback
-- and demo frames, never for querying/redecorating native aura buttons later.
local function Decorate(button)
    button:SetSize(BASE_SIZE, BASE_SIZE)
    -- Hover remains active while clicks pass through to the secure unit frame.
    button:EnableMouse(true)
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(true) end
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetTexture(WHITE)
    border:SetVertexColor(0.005, 0.007, 0.01, 1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local highlight = button:CreateTexture(nil, "OVERLAY")
    highlight:SetTexture(WHITE)
    highlight:SetVertexColor(0.65, 0.70, 0.76, 0.22)
    highlight:SetPoint("TOPLEFT", 0, 0)
    highlight:SetPoint("TOPRIGHT", 0, 0)
    highlight:SetHeight(1)

    -- No Lua cooldown script: the native widget animates/counts down itself.
    local cooldown = CreateFrame("Cooldown", nil, button)
    cooldown:SetAllPoints(icon)
    cooldown:EnableMouse(false)
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(false) end
    if cooldown.SetCountdownFont then cooldown:SetCountdownFont("GameFontHighlightSmall") end
    if cooldown.SetSwipeColor then cooldown:SetSwipeColor(0, 0, 0, 0.62) end

    local front = CreateFrame("Frame", nil, button)
    front:SetAllPoints(button)
    front:SetFrameLevel(button:GetFrameLevel() + 3)
    front:EnableMouse(false)
    local count = front:CreateFontString(nil, "OVERLAY")
    count:SetFont(FONT, 9, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    count:SetTextColor(1, 1, 1, 1)
    count:SetJustifyH("RIGHT")
    return { frame = button, icon = icon, cooldown = cooldown, count = count }
end

local function InitializeNativeButton(button)
    local parts = Decorate(button)
    -- Public, supported inbound methods. The engine controls all subsequent
    -- icon/count/duration assignments; no secret aura data enters this addon.
    button:SetIcon(parts.icon)
    button:SetApplicationCount(parts.count)
    button:SetDurationCooldown(parts.cooldown)
    -- Use the native tooltip implementation: restricted aura identity stays
    -- entirely inside Blizzard's AuraButton instead of entering addon Lua.
    if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_TOPRIGHT", 0, 4) end
    if button.SetHideTooltipInCombat then button:SetHideTooltipInCombat(false) end
end

function A:CreateNative(state)
    if self.nativeAvailable == false then return false end
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local ok, info = pcall(C_XMLUtil.GetTemplateInfo, "CustomAuraContainerTemplate")
        if ok and not Secret(info) and info == nil then
            self.nativeAvailable = false
            return false
        end
    end
    local created
    local ok, result = pcall(function()
        local container = CreateFrame("AuraContainer", nil, state.row, "CustomAuraContainerTemplate")
        created = container
        if type(container.AddAuraGroup) ~= "function" or type(container.SetUnit) ~= "function"
            or type(container.SetEnabled) ~= "function" then
            container:Hide()
            return nil
        end
        container:Hide()
        container:EnableMouse(false)
        container:SetEnabled(false)
        container:SetSize(1, BASE_SIZE)
        container:SetPoint("BOTTOMLEFT", state.row, "BOTTOMLEFT", 0, 0)
        if container.SetEditModePreviewEnabled then container:SetEditModePreviewEnabled(false) end
        container:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
        if container.SetFlowLayoutGrowthDirection and AnchorUtil and AnchorUtil.FlowDirection then
            container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
        end
        container:SetFlowLayoutMaximumLineSize(math.huge)
        container:AddAuraGroup(state.spec.group, Filter(state.spec, state.plate), {
            maxFrameCount = state.limit,
            initializeFrame = InitializeNativeButton,
            layout = { elementSpacing = BASE_GAP, lineSpacing = 0 },
        })
        return container
    end)
    if not ok or not result then
        if created then SafeMethod(created, "SetEnabled", false); SafeMethod(created, "Hide") end
        self.nativeAvailable = false
        if not ok then self:Error("Native aura display", result) end
        return false
    end
    self.nativeAvailable = true
    state.container, state.mode = result, "native"
    state.nativeFilter, state.nativeLimit = Filter(state.spec, state.plate), state.limit
    state.plate[state.spec.containerField] = result
    return true
end

function A:Ensure(plate, spec, preview)
    local rows = self.states[plate]
    if not rows then rows = {}; self.states[plate] = rows end
    local state = rows[spec.key]
    if state then
        if not preview and state.mode == "preview" then
            self:ClearOwnIcons(state)
            state.mode = "api"
            self:CreateNative(state)
            self:LayoutState(state)
        end
        return state
    end
    local row = CreateFrame("Frame", nil, plate.front or plate)
    row:EnableMouse(false)
    row:Hide()
    state = { plate = plate, spec = spec, row = row, icons = {}, mode = preview and "preview" or "api" }
    rows[spec.key] = state
    plate[spec.key], plate[spec.stateField] = row, state
    row:SetScript("OnEvent", function(_, event)
        if event == "UNIT_AURA" then A:UpdateState(state) end
    end)
    self:LayoutState(state)
    if not preview then self:CreateNative(state); self:LayoutState(state) end
    return state
end

function A:LayoutState(state)
    local plate, spec = state.plate, state.spec
    local size, gap, limit = Dimensions(spec, plate)
    local sizeChanged, limitChanged = state.size ~= size, state.limit ~= limit
    local filter = Filter(spec, plate)
    local filterChanged = state.filter ~= filter
    state.size, state.gap, state.limit = size, gap, limit
    state.filter = filter
    local point, anchor, relative, y
    if spec.key == "buffs" then
        -- These are addon-owned public flags, not native aura/cast visibility.
        anchor = Public(plate.castVisible) == true and plate.cast
            or (Public(plate.hasPower) == true and plate.power) or plate
        point, relative, y = "TOPLEFT", "BOTTOMLEFT", -4
    else
        anchor = plate.name or plate
        point, relative = "BOTTOMLEFT", "TOPLEFT"
        y = plate.name and 4 or ((RP.db.fontSize or 11) + 10)
    end
    if state.anchor ~= anchor or state.anchorY ~= y or state.anchorPoint ~= point then
        state.row:ClearAllPoints()
        state.row:SetPoint(point, anchor, relative, 0, y)
        state.anchor, state.anchorY, state.anchorPoint = anchor, y, point
    end
    if sizeChanged or limitChanged then
        state.row:SetSize(limit * (size + gap) - gap, size)
    end
    if state.container then
        -- Never read the native container's secret size, children, visibility,
        -- or text. Our fixed row is independent of its dynamic native layout.
        local scale = size / BASE_SIZE
        if state.nativeScale ~= scale then
            local ok, err = SafeMethod(state.container, "SetScale", scale)
            if ok then state.nativeScale = scale else self:Error(spec.label .. " scale", err) end
        end
        if state.nativeLimit ~= limit then
            local ok, err = SafeMethod(state.container, "SetAuraGroupMaxFrameCount", spec.group, limit)
            if ok then state.nativeLimit = limit else self:Error("Count " .. spec.key, err) end
        end
        if state.nativeFilter ~= filter then
            local ok, err = SafeMethod(state.container, "SetAuraGroupFilterString", spec.group, filter)
            if ok then state.nativeFilter = filter else self:Error(spec.label .. "filter", err) end
        end
    end
    if sizeChanged or limitChanged then
        for i, parts in ipairs(state.icons) do
            if sizeChanged then
                parts.frame:SetScale(size / BASE_SIZE)
                parts.frame:ClearAllPoints()
                parts.frame:SetPoint("BOTTOMLEFT", state.row, "BOTTOMLEFT", (i - 1) * (BASE_SIZE + BASE_GAP), 0)
            end
            if i > limit then parts.frame:Hide() end
        end
    end
    if not state.container and state.active and (limitChanged or filterChanged) then self:Queue(state) end
end

function A:Layout(plate)
    local rows = self.states[plate]
    if not rows then return end
    for _, spec in ipairs(ROWS) do
        local state = rows[spec.key]
        if state then
            if not Enabled(spec) then self:DetachState(state) end
            self:LayoutState(state)
        end
    end
end

function A:ClearOwnIcons(state)
    for _, parts in ipairs(state.icons) do
        parts.frame:Hide()
        parts.icon:SetTexture(nil)
        parts.count:SetText("")
        parts.auraInstanceID, parts.auraIndex, parts.preview = nil, nil, nil
        if parts.cooldown.Clear then parts.cooldown:Clear() end
    end
    state.visibleCount = 0
end

function A:OwnIcon(state, index)
    local parts = state.icons[index]
    if not parts then
        parts = Decorate(CreateFrame("Frame", nil, state.row))
        state.icons[index] = parts
        parts.frame:SetScale(state.size / BASE_SIZE)
        parts.frame:SetPoint("BOTTOMLEFT", state.row, "BOTTOMLEFT", (index - 1) * (BASE_SIZE + BASE_GAP), 0)
        local function HideTooltip(self)
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end
        parts.frame:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT", 0, 4)
            local shown = false
            if not parts.preview and Token(state.unit) then
                if type(parts.auraInstanceID) == "number" and GameTooltip.SetUnitAuraByAuraInstanceID then
                    shown = pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, state.unit, parts.auraInstanceID)
                elseif type(parts.auraIndex) == "number" and GameTooltip.SetUnitAura then
                    shown = pcall(GameTooltip.SetUnitAura, GameTooltip, state.unit, parts.auraIndex, state.filter)
                end
            end
            if shown then GameTooltip:Show()
            elseif parts.preview then
                GameTooltip:SetText("Preview " .. state.spec.label:lower())
                GameTooltip:AddLine("Example values used by the options preview.", 0.72, 0.78, 0.75)
                GameTooltip:Show()
            else GameTooltip:Hide() end
        end)
        parts.frame:SetScript("OnLeave", HideTooltip)
        parts.frame:SetScript("OnHide", HideTooltip)
    end
    return parts
end

function A:SetOwnDisplay(state, parts, data, preview)
    parts.icon:SetTexture(data.icon)
    parts.count:SetText("")
    if parts.cooldown.Clear then parts.cooldown:Clear() end
    local api = C_UnitAuras
    local instanceID = Public(data.auraInstanceID)
    parts.auraInstanceID, parts.preview = instanceID, preview and true or false
    local hasInstance = not preview and type(instanceID) == "number"
    local countApplied = false
    if hasInstance and api and api.GetAuraApplicationDisplayCount then
        local ok, count = pcall(api.GetAuraApplicationDisplayCount, state.unit, instanceID, 2, 99)
        if ok then parts.count:SetText(count); countApplied = true
        else self:Error(state.spec.label .. " stacks", count) end
    end
    if not countApplied then
        local applications = data.applications
        if Secret(applications) then parts.count:SetFormattedText("%d", applications)
        elseif type(applications) == "number" and applications > 1 then parts.count:SetText(applications) end
    end
    local durationApplied = false
    if hasInstance and api and api.GetAuraDuration and parts.cooldown.SetCooldownFromDurationObject then
        local ok, duration = pcall(api.GetAuraDuration, state.unit, instanceID)
        if ok then
            if Secret(duration) or duration ~= nil then
                local applied, err = pcall(parts.cooldown.SetCooldownFromDurationObject, parts.cooldown, duration)
                durationApplied = applied
                if not applied then self:Error(state.spec.label .. " duration", err) end
            end
        else self:Error(state.spec.label .. " duration", duration) end
    end
    if not durationApplied then
        local duration, expiration, rate = Public(data.duration), Public(data.expirationTime), Public(data.timeMod)
        if preview and type(duration) == "number" then
            expiration = GetTime() + (tonumber(data.remaining) or duration)
        end
        if type(duration) == "number" and duration > 0 and type(expiration) == "number" then
            if type(rate) ~= "number" then rate = 1 end
            if parts.cooldown.SetCooldownFromExpirationTime then
                parts.cooldown:SetCooldownFromExpirationTime(expiration, duration, rate)
            elseif parts.cooldown.SetCooldown then
                parts.cooldown:SetCooldown(expiration - duration, duration, rate)
            end
        end
    end
    parts.frame:Show()
end

function A:ScanFallback(state)
    self.stats.scans = self.stats.scans + 1
    local api = C_UnitAuras
    if not api then error("C_UnitAuras is unavailable") end
    local list = {}
    if type(api.GetUnitAuras) == "function" then
        list = api.GetUnitAuras(state.unit, state.filter, state.limit)
        if not AccessibleTable(list) then error("Aura list is not accessible to addon code") end
    elseif type(api.GetAuraDataByIndex) == "function" then
        for i = 1, state.limit do
            local data = api.GetAuraDataByIndex(state.unit, i, state.filter)
            if Secret(data) then error("Aura data is not accessible to addon code") end
            if data == nil then break end
            list[#list + 1] = data
        end
    else
        error("No supported aura API is available")
    end
    self:ClearOwnIcons(state)
    local count = math.min(#list, state.limit)
    for i = 1, count do
        local data = list[i]
        if not AccessibleTable(data) then error("Aura data is not accessible to addon code") end
        local parts = self:OwnIcon(state, i)
        parts.auraIndex = i
        self:SetOwnDisplay(state, parts, data, false)
    end
    state.visibleCount = count
end

function A:Queue(state)
    if self.pending[state] or state.blocked or not state.active or not Enabled(state.spec) then return end
    self.tail = self.tail + 1
    self.queue[self.tail], self.pending[state] = state, true
    self.worker:Show()
end

function A:UpdateState(state)
    if not state.active or not Enabled(state.spec) then return end
    if state.container then
        local ok, err = SafeMethod(state.container, "UpdateAllAuras")
        if not ok then self:Error(state.spec.label .. " refresh", err) end
    else
        self:Queue(state)
    end
end

function A:Update(plate)
    local rows = self.states[plate]
    if not rows then return end
    for _, spec in ipairs(ROWS) do
        local state = rows[spec.key]
        if state then self:UpdateState(state) end
    end
end

function A:AttachState(state, unit)
    local wasAttached = state.active and state.unit == unit
    if state.active and state.unit ~= unit then self:DetachState(state) end
    state.unit, state.active = unit, true
    self:LayoutState(state)
    state.row:Show()
    if state.container then
        if not wasAttached then
            -- Empty string is the supported cleared token; SetUnit(nil) is not.
            local ok, err = SafeMethod(state.container, "SetUnit", unit)
            if ok then ok, err = SafeMethod(state.container, "SetEnabled", true) end
            if not ok then
                self:Error(state.spec.label .. " binding", err)
                self:DetachState(state)
                return
            end
            SafeMethod(state.container, "Show")
        end
    elseif not wasAttached then
        state.blocked = false
        state.row:RegisterUnitEvent("UNIT_AURA", unit)
        self:Queue(state)
    end
end

function A:Attach(plate, unit)
    if not RP.db or RP.db.enabled == false or not Token(unit) then self:Detach(plate); return end
    if not self.initialized then self:Initialize() end
    for _, spec in ipairs(ROWS) do
        if Enabled(spec) then
            self:AttachState(self:Ensure(plate, spec, false), unit)
        else
            local rows = self.states[plate]
            if rows and rows[spec.key] then self:DetachState(rows[spec.key]) end
        end
    end
end

function A:DetachState(state)
    local wasAttached = state.active or state.unit ~= nil
    state.active, state.blocked = false, false
    self.pending[state] = nil
    state.row:UnregisterEvent("UNIT_AURA")
    state.row:Hide()
    if state.container then
        if wasAttached then
            SafeMethod(state.container, "SetEnabled", false)
            SafeMethod(state.container, "SetUnit", "")
            SafeMethod(state.container, "Hide")
        end
    end
    self:ClearOwnIcons(state)
    state.unit = nil
end

function A:Detach(plate)
    local rows = self.states[plate]
    if not rows then return end
    for _, spec in ipairs(ROWS) do
        if rows[spec.key] then self:DetachState(rows[spec.key]) end
    end
end

function A:PreviewState(plate, spec, samples)
    local state = self:Ensure(plate, spec, true)
    if state.active then self:DetachState(state) end
    self:LayoutState(state)
    self:ClearOwnIcons(state)
    if not Enabled(spec) or type(samples) ~= "table" then state.row:Hide(); return end
    local count = math.min(#samples, state.limit)
    for i = 1, count do self:SetOwnDisplay(state, self:OwnIcon(state, i), samples[i], true) end
    state.visibleCount = count
    state.row:SetShown(count > 0)
end

function A:Preview(plate, debuffSamples, buffSamples)
    self:PreviewState(plate, ROWS[1], debuffSamples)
    self:PreviewState(plate, ROWS[2], buffSamples)
end

function A:GetStatus()
    local native, fallback, blocked = 0, 0, 0
    local counts = { debuffs = 0, buffs = 0 }
    for _, rows in pairs(self.states) do
        for key, state in pairs(rows) do
            if state.active then
                counts[key] = counts[key] + 1
                if state.container then native = native + 1
                elseif state.blocked then blocked = blocked + 1
                else fallback = fallback + 1 end
            end
        end
    end
    local mode = self.nativeAvailable == true and "native client display" or "C_UnitAuras fallback"
    return "Auras: " .. mode .. " | rows: debuffs " .. counts.debuffs .. ", buffs " .. counts.buffs
        .. " | native " .. native .. ", fallback " .. fallback
        .. ", restricted " .. blocked .. " | messages " .. self.stats.errors
end

function A:Initialize()
    if self.initialized then return end
    self.initialized = true
    local loader = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if loader and not (InCombatLockdown and InCombatLockdown()) then
        pcall(loader, "Blizzard_AuraContainer")
    end
    local worker = CreateFrame("Frame")
    self.worker = worker
    worker:Hide()
    worker:SetScript("OnUpdate", function(_, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 0.04 then return end
        self.elapsed = 0
        local processed, dequeued = 0, 0
        local start = debugprofilestop and debugprofilestop()
        while self.head <= self.tail and processed < 2 and dequeued < 20 do
            local state = self.queue[self.head]
            self.queue[self.head], self.head = nil, self.head + 1
            dequeued = dequeued + 1
            if self.pending[state] then
                self.pending[state] = nil
                if state.active and not state.container and not state.blocked and Enabled(state.spec) then
                    local ok, err = pcall(self.ScanFallback, self, state)
                    if not ok then
                        self:ClearOwnIcons(state)
                        state.blocked = true
                        self:Error(state.spec.label .. "-API", err)
                    end
                    processed = processed + 1
                    if start and debugprofilestop() - start >= 0.8 then break end
                end
            end
        end
        if self.head > self.tail then
            self.head, self.tail = 1, 0
            worker:Hide()
        end
    end)
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function()
        -- Native containers already own their event subscriptions. Only retry
        -- the fallback at genuine restriction/context transitions, never idle.
        for _, rows in pairs(self.states) do
            for _, state in pairs(rows) do
                if state.active and not state.container then state.blocked = false; self:Queue(state) end
            end
        end
    end)
end
