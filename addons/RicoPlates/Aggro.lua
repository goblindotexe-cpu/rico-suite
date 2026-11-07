-- Actual attackers get a separate, warm perimeter. Hostile health color and
-- threat-table membership alone never imply that the creature is attacking us.
local _, RP = ...
local A = {tracked = setmetatable({}, {__mode = "k"}), active = setmetatable({}, {__mode = "k"})}
RP.Aggro = A
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
local function True(value)
    return RP.Readable(value) and (value == true or value == 1)
end
local function False(value)
    return RP.Readable(value) and (value == false or value == 0)
end
local function Unit(value)
    return RP.Readable(value) and type(value) == "string" and #value < 64
end
local function PublicTrue(fn, ...)
    local ok, value = Call(fn, ...)
    return ok and True(value)
end

function A:TargetsPlayer(unit)
    if not Unit(unit) or not PublicTrue(UnitExists, unit) then return false end
    local ok, player = Call(UnitIsPlayer, unit)
    if not ok or not False(player) then return false end
    if PublicTrue(UnitIsUnit, unit, "player") then return false end
    if not PublicTrue(UnitCanAttack, "player", unit) then return false end
    -- An idle neutral NPC looking at the player is not an aggressor. Restricted
    -- combat or target flags remain unknown, never a positive aggro assertion.
    if not PublicTrue(UnitAffectingCombat, unit) then return false end
    if not PublicTrue(UnitExists, unit .. "target") then return false end
    return PublicTrue(UnitIsUnit, unit .. "target", "player")
end

local function Edge(frame, first, second, horizontal, offset, thickness, r, g, b, alpha)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetTexture(WHITE)
    -- Every stroke points inward. An outward glow can reach the neighboring
    -- level badge even when the badge and health frame have separate anchors.
    local left = first:find("LEFT", 1, true) and offset or -offset
    local top = first:find("TOP", 1, true) and -offset or offset
    local right = second:find("LEFT", 1, true) and offset or -offset
    local bottom = second:find("TOP", 1, true) and -offset or offset
    texture:SetPoint(first, frame, first, left, top)
    texture:SetPoint(second, frame, second, right, bottom)
    if horizontal then texture:SetHeight(thickness) else texture:SetWidth(thickness) end
    texture:SetVertexColor(r, g, b, alpha)
    return texture
end

local function Rim(parent, anchor)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    frame:SetFrameLevel(anchor:GetFrameLevel() + 8)
    frame:EnableMouse(false)
    frame:SetClipsChildren(true)
    local segments = {{"TOPLEFT", "TOPRIGHT", true}, {"BOTTOMLEFT", "BOTTOMRIGHT", true},
        {"TOPLEFT", "BOTTOMLEFT", false}, {"TOPRIGHT", "BOTTOMRIGHT", false}}
    for _, segment in ipairs(segments) do
        Edge(frame, segment[1], segment[2], segment[3], 3, 3, 0.98, 0.12, 0.025, 0.14)
        Edge(frame, segment[1], segment[2], segment[3], 1, 2, 1.00, 0.23, 0.035, 0.48)
        Edge(frame, segment[1], segment[2], segment[3], 0, 1, 1.00, 0.49, 0.12, 1.00)
    end
    -- Short, bright corners preserve a crisp silhouette at small UI scales.
    for _, corner in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
        for _, horizontal in ipairs({true, false}) do
            local texture = frame:CreateTexture(nil, "OVERLAY")
            texture:SetTexture(WHITE)
            texture:SetPoint(corner, frame, corner, 0, 0)
            texture:SetSize(horizontal and 9 or 2, horizontal and 2 or 9)
            texture:SetVertexColor(1.00, 0.69, 0.27, 1)
        end
    end
    frame:Hide()
    return frame
end

function A:BuildPlate(p)
    if p.aggro then return end
    self:Initialize()
    p.aggro = { frame = Rim(p, p), active = false }
end

function A:AttachPortrait(entry)
    local p = entry.plate
    self:BuildPlate(p)
    if not p.aggro.portrait then p.aggro.portrait = Rim(entry.portraitFront, entry.portraitFront) end
    self:LayerPortrait(p)
end

function A:LayerPortrait(p)
    local rim = p.aggro and p.aggro.portrait
    if not rim then return end
    -- HUD level badges sit partly inside the portrait. Keep the entire glow
    -- below their opaque background, metal and text after every layout change.
    local parent = rim:GetParent()
    local level = parent:GetFrameLevel() + 1
    if p.levelBox then level = math.min(level, p.levelBox:GetFrameLevel() - 1) end
    rim:SetFrameLevel(math.max(0, level))
end

function A:Hide(p)
    self.active[p] = nil
    if p.aggro then
        p.aggro.active = false
        p.aggro.frame:Hide()
        if p.aggro.portrait then p.aggro.portrait:Hide() end
    end
    if self.worker and not next(self.active) then self.worker:Hide() end
end

function A:Forget(p)
    self.tracked[p] = nil
    self:Hide(p)
end

function A:Refresh(p)
    if not RP.db or RP.db.aggroIndicator == false or not RP.db.enabled
        or p.preview or not p.visible or not Unit(p.unit) or not p:IsVisible() then
        self:Forget(p)
        return
    end
    self:BuildPlate(p)
    self:LayerPortrait(p)
    self.tracked[p] = true
    if not self:TargetsPlayer(p.unit) then self:Hide(p); return end
    p.aggro.active = true
    self.active[p] = true
    p.aggro.frame:SetAlpha(0.82); p.aggro.frame:Show()
    if p.aggro.portrait then p.aggro.portrait:SetAlpha(0.82); p.aggro.portrait:Show() end
    self.worker:Show()
end

function A:RefreshAll()
    for p in pairs(self.tracked) do self:Refresh(p) end
end

function A:UpdateSettings()
    self:Initialize()
    if not RP.db or RP.db.aggroIndicator == false or not RP.db.enabled then
        for p in pairs(self.tracked) do self:Forget(p) end
        return
    end
    for _, p in pairs(RP.Plates and RP.Plates.active or {}) do self:Refresh(p) end
    for _, entry in pairs(RP.UnitFrames and RP.UnitFrames.frames or {}) do self:Refresh(entry.plate) end
    self:RefreshAll()
end

function A:Initialize()
    if self.worker then return end
    local worker = CreateFrame("Frame")
    self.worker = worker
    worker:Hide()
    worker:SetScript("OnUpdate", function(_, elapsed)
        A.elapsed = (A.elapsed or 0) + elapsed
        A.refreshElapsed = (A.refreshElapsed or 0) + elapsed
        if A.elapsed < 0.05 then return end
        A.elapsed = 0
        local recheck = A.refreshElapsed >= 0.2
        if recheck then A.refreshElapsed = 0 end
        local ok, now = Call(GetTime)
        local valid = ok and RP.Readable(now) and type(now) == "number"
        local alpha = valid and (0.70 + 0.22 * math.sin(now * 4.4)) or 0.82
        local animated, cap = 0, math.min(24, RP.db and RP.db.maxAnimatedPlates or 24)
        for p in pairs(A.active) do
            if recheck then A:Refresh(p) end
            if A.active[p] then
                animated = animated + 1
                local amount = animated <= cap and alpha or 0.82
                p.aggro.frame:SetAlpha(amount)
                if p.aggro.portrait then p.aggro.portrait:SetAlpha(amount) end
            end
        end
    end)
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({"UNIT_TARGET", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
        "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "UNIT_FACTION", "UNIT_FLAGS"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function() A:RefreshAll() end)
end
