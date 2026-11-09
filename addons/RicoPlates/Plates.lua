local _, RP = ...
local P = {active = {}, frames = {}, suppressed = {}, hooked = {}, animatedCount = 0, forbiddenCount = 0}
RP.Plates = P
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = RP.Theme.font
local unpack = unpack or table.unpack
local function SafeUnit(unit)
    return not RP.IsSecret(unit) and type(unit) == "string"
end
local function Exists(unit)
    return SafeUnit(unit) and RP.PublicTrue(UnitExists(unit))
end
local function IsObject(unit)
    return UnitIsGameObject and RP.PublicTrue(UnitIsGameObject(unit))
end

local function PublicUnitFlag(getter, ...)
    if type(getter) ~= "function" then return false end
    local ok, value = pcall(getter, ...)
    return ok and RP.PublicTrue(value)
end

function P:NPCKind(unit, baseKind)
    if baseKind ~= "enemy" and baseKind ~= "neutral" then return baseKind end
    if not RP.db.grayTapped and not RP.db.grayTrivial then return baseKind end
    if type(UnitPlayerControlled) == "function" then
        local ok, controlled = pcall(UnitPlayerControlled, unit)
        if not ok or RP.IsSecret(controlled) or RP.PublicTrue(controlled) then return baseKind end
    end
    if RP.db.grayTapped and PublicUnitFlag(UnitIsTapDenied, unit) then
        return "tapped"
    end
    if RP.db.grayTrivial and PublicUnitFlag(UnitIsTrivial, unit) then
        return "trivial"
    end
    return baseKind
end

function P:Classify(unit)
    local player = RP.PublicTrue(UnitIsPlayer(unit))
    if player then
        local selected = RP.PublicTrue(UnitIsUnit(unit, "target"))
        local raid = UnitInRaid(unit)
        if RP.Readable(raid) and raid then return "raid", RP.db.showRaid or selected, true end
        if RP.PublicTrue(UnitInParty(unit)) then return "party", RP.db.showParty or selected, true end
        local faction = UnitFactionGroup(unit)
        local ownFaction = UnitFactionGroup("player")
        if RP.Readable(faction) and RP.Readable(ownFaction) and faction and ownFaction
            and faction ~= "Neutral" and ownFaction ~= "Neutral" and faction ~= ownFaction then
            return "enemy", true, true
        end
        if RP.PublicTrue(UnitCanAttack("player", unit)) then return "enemy", true, true end
        return "friendly", selected, true
    end
    local reaction = UnitReaction(unit, "player")
    if RP.Readable(reaction) and type(reaction) == "number" then
        if reaction <= 3 then return self:NPCKind(unit, "enemy"), true, false, "enemy" end
        if reaction == 4 then return self:NPCKind(unit, "neutral"), true, false, "neutral" end
        return "friendlyNPC", RP.db.showFriendlyNPCs, false
    end
    if RP.PublicTrue(UnitCanAttack("player", unit)) then return self:NPCKind(unit, "enemy"), true, false, "enemy" end
    return "friendlyNPC", RP.db.showFriendlyNPCs, false
end

local function Texture(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(WHITE)
    if color then t:SetVertexColor(unpack(color)) end
    return t
end

local function Font(parent, size, justify)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(FONT, size, "OUTLINE")
    t:SetJustifyH(justify or "CENTER")
    t:SetTextColor(0.96, 0.98, 1)
    t:SetShadowOffset(0, -1)
    return t
end

local function Edges(parent, thickness)
    local result = {}
    for i = 1, 4 do result[i] = Texture(parent, "OVERLAY") end
    result[1]:SetPoint("TOPLEFT", -thickness, thickness)
    result[1]:SetPoint("TOPRIGHT", thickness, thickness)
    result[1]:SetHeight(thickness)
    result[2]:SetPoint("BOTTOMLEFT", -thickness, -thickness)
    result[2]:SetPoint("BOTTOMRIGHT", thickness, -thickness)
    result[2]:SetHeight(thickness)
    result[3]:SetPoint("TOPLEFT", -thickness, 0)
    result[3]:SetPoint("BOTTOMLEFT", -thickness, 0)
    result[3]:SetWidth(thickness)
    result[4]:SetPoint("TOPRIGHT", thickness, 0)
    result[4]:SetPoint("BOTTOMRIGHT", thickness, 0)
    result[4]:SetWidth(thickness)
    return result
end

local function IronTrim(parent, outerWidth)
    -- Layered black/steel bevels stay crisp at small nameplate sizes.
    local trim = { outer = Edges(parent, outerWidth or 3), metal = Edges(parent, 2), inner = Edges(parent, 1) }
    for _, edge in ipairs(trim.outer) do edge:SetVertexColor(0.012, 0.016, 0.021, 1) end
    for _, edge in ipairs(trim.inner) do edge:SetVertexColor(0.025, 0.032, 0.041, 1) end
    return trim
end

local function PaintIron(trim, selected)
    local colors = selected and {
        {0.36, 0.39, 0.44, 1}, {0.12, 0.14, 0.18, 1},
        {0.25, 0.28, 0.33, 1}, {0.15, 0.18, 0.22, 1},
    } or {
        {0.19, 0.22, 0.26, 1}, {0.055, 0.065, 0.085, 1},
        {0.13, 0.15, 0.19, 1}, {0.08, 0.10, 0.13, 1},
    }
    for i, edge in ipairs(trim.metal) do edge:SetVertexColor(unpack(colors[i])) end
end

function P:CreateIronTrim(parent)
    local trim = IronTrim(parent)
    PaintIron(trim, false)
    return trim
end

function P:PaintBorder(p, selected)
    PaintIron(p.iron, selected)
    PaintIron(p.levelBox.iron, selected)
end

local function Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:EnableMouse(false)
    f.bg = Texture(f, "BACKGROUND", {0.02, 0.03, 0.05, 0.96})
    f.bg:SetAllPoints()
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    return f
end

local function PositionTargetingEye(p)
    local eye = p.targetingEye
    if not eye then return end
    eye:ClearAllPoints()
    if p.base and not p.visible then
        local anchor = p.questBeacon and p.questBeacon:IsShown() and p.questBeacon or p.base
        eye:SetScale(1.35)
        eye:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
    else
        local raidMarker = p.visible and p.raidIcon:IsShown()
        if p.base then eye:SetScale(p:GetScale()) end
        eye:SetPoint("BOTTOM", p.raidIcon, raidMarker and "TOP" or "BOTTOM", 0, 2)
    end
    if eye.castWarning then eye.castWarning:SetScale(eye:GetScale()) end
end

local function EyeStroke(eye, layer, thickness, r, g, b, x1, y1, x2, y2)
    local stroke = eye:CreateLine(nil, layer)
    stroke:SetColorTexture(r, g, b, 1)
    stroke:SetThickness(thickness)
    stroke:SetStartPoint("BOTTOMLEFT", eye, x1, y1)
    stroke:SetEndPoint("BOTTOMLEFT", eye, x2, y2)
    return stroke
end

local function DrawTargetingEye(eye)
    local shape = {{2, 11}, {7, 15}, {14, 18}, {21, 15}, {26, 11}, {21, 7}, {14, 5}, {7, 7}}
    for index, first in ipairs(shape) do
        local last = shape[index % #shape + 1]
        EyeStroke(eye, "BACKGROUND", 4.6, 0.09, 0.01, 0.018, first[1], first[2], last[1], last[2])
        EyeStroke(eye, "ARTWORK", 1.8, 0.90, 0.12, 0.16, first[1], first[2], last[1], last[2])
    end
    EyeStroke(eye, "BORDER", 4, 0.98, 0.77, 0.69, 8, 14, 20, 14)
    EyeStroke(eye, "BORDER", 4, 0.91, 0.54, 0.51, 4, 11, 24, 11)
    EyeStroke(eye, "BORDER", 3, 0.76, 0.35, 0.36, 8, 8, 20, 8)
    EyeStroke(eye, "ARTWORK", 1, 0.65, 0.04, 0.10, 5, 11, 10, 12)
    EyeStroke(eye, "ARTWORK", 1, 0.65, 0.04, 0.10, 19, 10, 23, 12)
    EyeStroke(eye, "ARTWORK", 2, 0.67, 0.05, 0.10, 8, 7, 7, 2)
    EyeStroke(eye, "ARTWORK", 2, 0.79, 0.07, 0.12, 18, 6, 19, 1)
    EyeStroke(eye, "OVERLAY", 2, 0.55, 0.04, 0.08, 12, 14, 16, 14)
    EyeStroke(eye, "OVERLAY", 4, 0.40, 0.02, 0.06, 11, 11, 17, 11)
    EyeStroke(eye, "OVERLAY", 2, 0.55, 0.04, 0.08, 12, 8, 16, 8)
    local pupil = eye:CreateTexture(nil, "OVERLAY", nil, 1)
    pupil:SetColorTexture(0.045, 0.005, 0.012, 1)
    pupil:SetSize(2, 6)
    pupil:SetPoint("CENTER", eye, "BOTTOMLEFT", 14, 11)
    local glint = eye:CreateTexture(nil, "OVERLAY", nil, 2)
    glint:SetColorTexture(1, 0.88, 0.82, 1)
    glint:SetSize(2, 2)
    glint:SetPoint("CENTER", eye, "BOTTOMLEFT", 13, 13)
end

local function BuildTargetingEye(p)
    -- Anchor to Rico's geometry but let the client nameplate own visibility.
    -- A friendly player can have a nameplate even when Rico hides their bar.
    local eye = CreateFrame("Frame", nil, p.base or p.front)
    eye:SetSize(28, 21)
    eye:SetFrameLevel(p.front:GetFrameLevel() + 1)
    eye:EnableMouse(false)
    DrawTargetingEye(eye)
    p.targetingEye = eye
    PositionTargetingEye(p)
    eye:Hide()
    return eye
end

local function BuildCastRing(warning)
    local ring = CreateFrame("Cooldown", nil, warning)
    ring:SetSize(58, 44)
    ring:SetPoint("CENTER", warning, "CENTER", 0, 2)
    ring:EnableMouse(false)
    -- The existing bubble art is an annulus. The client sweeps its visible
    -- portion using the actual cast duration, including restricted timing.
    local texture = RP.media .. "Bubble"
    local track = ring:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture(texture)
    track:SetVertexColor(0.46, 0.12, 0.095, 0.65)
    if ring.SetSwipeTexture then ring:SetSwipeTexture(texture, 1, 1, 1, 1) end
    if ring.SetSwipeColor then ring:SetSwipeColor(1, 0.44, 0.30, 1) end
    if ring.SetDrawSwipe then ring:SetDrawSwipe(true) end
    if ring.SetDrawEdge then ring:SetDrawEdge(false) end
    if ring.SetDrawBling then ring:SetDrawBling(false) end
    if ring.SetReverse then ring:SetReverse(false) end
    if ring.SetHideCountdownNumbers then ring:SetHideCountdownNumbers(true) end
    ring:Hide()
    return ring
end

local function BuildCastWarning(eye)
    local warning = CreateFrame("Frame", nil, eye:GetParent())
    warning:SetSize(eye:GetWidth(), eye:GetHeight())
    warning:SetPoint("CENTER", eye, "CENTER", 0, 0)
    warning:SetScale(eye:GetScale())
    warning:SetFrameLevel(eye:GetFrameLevel() + 2)
    warning:EnableMouse(false)
    warning.ring = BuildCastRing(warning)

    -- The animated child has its own scale, separate from the native alpha gate.
    local pulse = CreateFrame("Frame", nil, warning)
    pulse:SetAllPoints(warning)
    DrawTargetingEye(pulse)
    local animation = pulse:CreateAnimationGroup()
    animation:SetLooping("BOUNCE")
    local scale = animation:CreateAnimation("Scale")
    scale:SetScaleFrom(1.06, 1.06)
    scale:SetScaleTo(1.28, 1.28)
    scale:SetDuration(0.32)
    scale:SetSmoothing("IN_OUT")
    warning.pulse, warning.animation = pulse, animation
    warning:SetScript("OnShow", function() animation:Play() end)
    warning:SetScript("OnHide", function() animation:Stop() end)

    local interrupt = CreateFrame("Frame", nil, warning)
    interrupt:SetSize(10, 15)
    interrupt:SetPoint("LEFT", warning, "RIGHT", 9, 0)
    interrupt:EnableMouse(false)
    interrupt.strokes = {}
    local bolt = {{7, 14, 3, 8}, {3, 8, 7, 8}, {7, 8, 3, 1}}
    for _, segment in ipairs(bolt) do
        EyeStroke(interrupt, "BACKGROUND", 4, 0.06, 0.03, 0.015, unpack(segment))
        local stroke = EyeStroke(interrupt, "ARTWORK", 2, 1, 0.78, 0.35, unpack(segment))
        interrupt.strokes[#interrupt.strokes + 1] = stroke
    end
    interrupt:Hide()
    warning.interrupt = interrupt
    warning:Hide()
    eye.castWarning = warning
    return warning
end

local function ReadCastInfo(unit)
    local castOK, castName, _, castIcon, _, _, _, _, castLocked, _, castBarID = pcall(UnitCastingInfo, unit)
    if castOK and (RP.IsSecret(castName) or castName ~= nil) then
        return castName, castIcon, castLocked, false, nil, castBarID
    end
    local channelOK, channelName, _, channelIcon, _, _, _, channelLocked, _, empowered, _, channelBarID =
        pcall(UnitChannelInfo, unit)
    if channelOK and (RP.IsSecret(channelName) or channelName ~= nil) then
        return channelName, channelIcon, channelLocked, true, nil, channelBarID, empowered
    end
    return nil, nil, nil, nil, castOK and channelOK
end

local function PublicCastID(value)
    if RP.Readable(value) and type(value) == "number" then return value end
end

local function HideCastRing(ring)
    if ring:IsShown() then
        ring:Hide()
        if ring.Clear then pcall(ring.Clear, ring) end
    end
    ring.castBarID, ring.durationGetter = nil, nil
end

local function UpdateCastRing(ring, unit, channel, empowered, castBarID, refreshTiming)
    local getter = UnitCastingDuration
    if channel then
        getter = (RP.PublicTrue(empowered) and UnitEmpoweredChannelDuration) or UnitChannelDuration
    end
    if castBarID and ring.castBarID == castBarID and ring.durationGetter == getter and not refreshTiming then return end
    if type(getter) == "function" and ring.SetCooldownFromDurationObject then
        local ok, duration = pcall(getter, unit)
        if ok and (RP.IsSecret(duration) or duration ~= nil)
            and pcall(ring.SetCooldownFromDurationObject, ring, duration, true) then
            ring.castBarID, ring.durationGetter = castBarID, getter
            ring:Show()
            return
        end
    end
    HideCastRing(ring)
end

local function HideCastWarning(p)
    local warning = p.targetingEye and p.targetingEye.castWarning
    if warning then
        HideCastRing(warning.ring)
        warning.castBarID = nil
        warning.interrupt:Hide()
        warning:Hide()
    end
end

function P:UpdateCastWarning(p, refreshTiming)
    local host = p.base
    if not host or p.preview or p.unitFrame or not RP.db.enabled or not SafeUnit(p.unit)
        or not RP.PublicTrue(host:IsVisible()) or not PublicUnitFlag(UnitCanAttack, "player", p.unit)
        or type(PlayerIsSpellTarget) ~= "function" then
        HideCastWarning(p)
        return
    end
    local ok, aimed = pcall(PlayerIsSpellTarget, p.unit)
    if not ok or (not RP.IsSecret(aimed) and not RP.PublicTrue(aimed)) then
        HideCastWarning(p)
        return
    end
    local name, _, locked, channel, knownIdle, castBarID, empowered = ReadCastInfo(p.unit)
    castBarID = PublicCastID(castBarID)
    if knownIdle or (castBarID and castBarID == p.endedCastBarID) then
        HideCastWarning(p)
        return
    end

    local eye = p.targetingEye or BuildTargetingEye(p)
    local warning = eye.castWarning or BuildCastWarning(eye)
    if RP.IsSecret(aimed) then
        -- Alpha gates are evaluated by WoW without returning secret values to Lua.
        if not warning.SetAlphaFromBoolean or not pcall(warning.SetAlphaFromBoolean, warning, aimed, 1, 0) then
            HideCastWarning(p)
            return
        end
    else
        warning:SetAlpha(1)
    end
    warning.castBarID = castBarID
    UpdateCastRing(warning.ring, p.unit, channel, empowered, castBarID, refreshTiming)

    local interrupt, showInterrupt = warning.interrupt, false
    if RP.db.interruptIndicators ~= false then
        if RP.IsSecret(locked) then
            showInterrupt = interrupt.SetAlphaFromBoolean ~= nil
                and pcall(interrupt.SetAlphaFromBoolean, interrupt, locked, 0, 1)
        elseif (RP.IsSecret(name) or name ~= nil) and (locked == false or locked == 0) then
            interrupt:SetAlpha(1)
            showInterrupt = true
        end
    end
    if showInterrupt then
        local ready = RP.Features and RP.Features:ReadyInterrupt(p.unit)
        for _, stroke in ipairs(interrupt.strokes) do
            if ready then stroke:SetColorTexture(0.38, 1, 0.66, 1)
            else stroke:SetColorTexture(1, 0.78, 0.35, 1) end
        end
    end
    interrupt:SetShown(showInterrupt)
    warning:Show()
end

function P:UpdateTargetingEye(p)
    if p.preview or p.unitFrame then return end
    local host = p.base or p
    local ok, targeting
    if RP.db.enabled and (p.base or p.visible) and RP.PublicTrue(host:IsVisible()) and SafeUnit(p.unit)
        and type(UnitIsUnit) == "function" then
        ok, targeting = pcall(UnitIsUnit, p.unit .. "target", "player")
    end
    if ok and RP.PublicTrue(targeting) then
        local eye = p.targetingEye or BuildTargetingEye(p)
        eye:SetAlpha(1)
        eye:Show()
        return
    end
    if ok and RP.IsSecret(targeting) then
        local eye = p.targetingEye or BuildTargetingEye(p)
        -- The engine can render a restricted comparison without exposing its value to Lua.
        if eye.SetAlphaFromBoolean and pcall(eye.SetAlphaFromBoolean, eye, targeting, 1, 0) then
            eye:Show()
            return
        end
    end
    if p.targetingEye then p.targetingEye:Hide() end
end

local function Distant(p)
    if not p.base or not SafeUnit(p.unit) or PublicUnitFlag(UnitIsUnit, p.unit, "target") then return false end
    if type(UnitDistanceSquared) == "function" then
        local ok, squared, checked = pcall(UnitDistanceSquared, p.unit)
        if ok and RP.PublicTrue(checked) and RP.Readable(squared)
            and type(squared) == "number" and squared >= 0 and squared < math.huge then
            return squared > (p.distant and 28 * 28 or 30 * 30)
        end
    end
    -- Follow-distance is the available general range check for non-group units.
    -- A denied/restricted result is unknown, so keep the normal bar in that case.
    if type(CheckInteractDistance) == "function"
        and (not PublicUnitFlag(InCombatLockdown) or PublicUnitFlag(UnitCanAttack, "player", p.unit)) then
        local ok, inRange = pcall(CheckInteractDistance, p.unit, 4)
        return ok and RP.Readable(inRange) and (inRange == false or inRange == 0)
    end
    return false
end

function P:RefreshTargetingEyes(checkDistance)
    for _, p in pairs(self.active) do
        if checkDistance and p.distant ~= Distant(p) then
            self:Refresh(p)
        else
            self:UpdateTargetingEye(p)
            if checkDistance then self:UpdateCastWarning(p) end
        end
    end
end

local function HealLayer(health)
    local clip = CreateFrame("Frame", nil, health)
    clip:SetFrameLevel(health:GetFrameLevel() + 2)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    return clip
end

local function HealMeter(clip, color)
    local bar = CreateFrame("StatusBar", nil, clip)
    bar:SetFrameLevel(clip:GetFrameLevel())
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(unpack(color))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:EnableMouse(false)
    return bar
end

function P:BuildHealPreview(health, nativePrediction, demo)
    if not demo and (type(CreateUnitHealPredictionCalculator) ~= "function" or type(UnitGetDetailedHealPrediction) ~= "function") then return end

    local fill = health:GetStatusBarTexture()
    local absorbClip = HealLayer(health)
    absorbClip:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, 3)
    absorbClip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
    local absorb = HealMeter(absorbClip, {0.73, 0.38, 1, 0.95})
    absorb:SetReverseFill(true)
    absorb:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    absorb:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")

    -- Start the preview one heal-absorb width before the current HP edge.
    -- Clipping hides that part of the cast and leaves only HP it can restore.
    local start = absorb:GetStatusBarTexture()
    local heal
    if not nativePrediction then
        local missing = HealLayer(health)
        missing:SetPoint("TOPLEFT", fill, "TOPRIGHT")
        missing:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
        heal = HealMeter(missing, {0.39, 1, 0.59, 0.83})
    end
    -- Only the portion of this player's cast beyond full HP reaches the gold cap.
    local overflow = HealLayer(health)
    overflow:SetFrameLevel(health:GetFrameLevel() + 4)
    overflow:SetPoint("TOPLEFT", health, "TOPRIGHT", 0, -1)
    overflow:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 3, 1)
    local overheal = HealMeter(overflow, {1, 0.72, 0.19, 1})
    local meters = heal and {absorb, heal, overheal} or {absorb, overheal}
    for index = 2, #meters do
        meters[index]:SetPoint("TOPLEFT", start, "TOPLEFT")
        meters[index]:SetPoint("BOTTOMLEFT", start, "BOTTOMLEFT")
    end
    local function SetWidth(_, width)
        for _, meter in ipairs(meters) do meter:SetWidth(width) end
    end
    SetWidth(health, health:GetWidth())
    health:HookScript("OnSizeChanged", SetWidth)

    local preview = heal or overheal
    preview.healAbsorb, preview.heal, preview.overheal = absorb, heal, overheal
    return preview
end

local function DisplayHealAmounts(preview, maximum, myHeal, absorb)
    local absorbBar = preview.healAbsorb
    absorbBar:SetMinMaxValues(0, maximum)
    absorbBar:SetValue(absorb)
    absorbBar:SetAlpha(RP.db.healerAbsorbs ~= false and 1 or 0)
    if preview.heal then
        preview.heal:SetMinMaxValues(0, maximum)
        preview.heal:SetValue(myHeal)
    end
    preview.overheal:SetMinMaxValues(0, maximum)
    preview.overheal:SetValue(myHeal)
    preview.overheal:SetAlpha(RP.db.healerOverheal ~= false and 1 or 0)
end

local function DisplayHealPreview(preview, unit, calculator)
    if type(calculator.ResetPredictedValues) == "function" then calculator:ResetPredictedValues() end
    UnitGetDetailedHealPrediction(unit, "player", calculator)
    local maximum = calculator:GetMaximumHealth()
    if type(calculator.GetTotalIncomingHealsFromHealer) == "function" and type(calculator.GetTotalHealAbsorbs) == "function" then
        -- The native bars do the geometry using raw values, even if they are secret.
        DisplayHealAmounts(preview, maximum, calculator:GetTotalIncomingHealsFromHealer(), calculator:GetTotalHealAbsorbs())
    else
        local _, myHeal = calculator:GetIncomingHeals()
        DisplayHealAmounts(preview, maximum, myHeal, 0)
    end
end

function P:UpdateHealPreview(preview, unit)
    if not preview then return end
    if SafeUnit(unit) and not self.healCalculator then
        local ok, calculator = pcall(CreateUnitHealPredictionCalculator)
        if ok then self.healCalculator = calculator end
    end
    if not SafeUnit(unit) or not self.healCalculator or not pcall(DisplayHealPreview, preview, unit, self.healCalculator) then
        DisplayHealAmounts(preview, 1, 0, 0)
    end
end

function P:Build(parent, preview, style)
    local p = CreateFrame("Frame", nil, parent)
    p.preview = preview
    p.style, p.unitFrame = style, style and style.unitFrame or false
    p:SetFrameLevel(parent:GetFrameLevel() + 10)
    p:EnableMouse(false)
    p:SetSize(190, 19)
    p.back = Texture(p, "BACKGROUND", {0.018, 0.024, 0.04, 0.96})
    p.back:SetPoint("TOPLEFT", -3, 3)
    p.back:SetPoint("BOTTOMRIGHT", 3, -3)
    p.health = CreateFrame("StatusBar", nil, p)
    p.health:SetAllPoints()
    p.health:SetStatusBarTexture(WHITE)
    p.health:SetMinMaxValues(0, 100)
    p.health:SetValue(100)
    p.health:EnableMouse(false)
    p.healthBg = Texture(p.health, "BACKGROUND", {0.09, 0.10, 0.14, 1})
    p.healthBg:SetAllPoints()
    if not preview then p.healPreview = self:BuildHealPreview(p.health) end
    p.clip = CreateFrame("Frame", nil, p.health)
    p.clip:SetFrameLevel(p.health:GetFrameLevel() + 1)
    -- Let the UI engine crop the bubbles to the fill. No secret health arithmetic.
    p.clip:SetPoint("TOPLEFT", p.health:GetStatusBarTexture(), "TOPLEFT")
    p.clip:SetPoint("BOTTOMRIGHT", p.health:GetStatusBarTexture(), "BOTTOMRIGHT")
    p.clip:SetClipsChildren(true)
    p.clip:EnableMouse(false)
    -- Native live geometry is cropped by the statusbar fill. No health-value
    -- arithmetic or texture image is used for the liquid effect.
    p.liquid = RP.Theme:Liquid(p.clip, {health = true, manual = true,
        width = 190, height = 19, bubbleCount = RP.db.bubbleCount,
        bubbleScale = RP.db.bubbleScale * 0.55})
    p.liquid:Hide()
    p.topSheen = Texture(p.health, "OVERLAY", {1, 1, 1, 0.16})
    p.topSheen:SetPoint("TOPLEFT")
    p.topSheen:SetPoint("TOPRIGHT")
    p.topSheen:SetHeight(1)
    p.front = CreateFrame("Frame", nil, p)
    p.front:SetAllPoints()
    p.front:SetFrameLevel(p.health:GetFrameLevel() + 3)
    p.front:EnableMouse(false)
    p.iron = IronTrim(p.front)
    p.outline = p.iron.outer
    if not preview and not p.unitFrame then
        -- World player names have their own layer so the HP bar can hide.
        p.nameLayer = CreateFrame("Frame", nil, parent)
        p.nameLayer:SetSize(1, 1)
        p.nameLayer:SetPoint("CENTER", p, "CENTER")
        p.nameLayer:SetFrameLevel(p.front:GetFrameLevel())
        p.nameLayer:EnableMouse(false)
        p.nameLayer:Hide()
    end
    p.name = Font(p.nameLayer or p.front, 12, "CENTER")
    p.name:SetPoint("BOTTOM", p, "TOP", 0, 5)
    p.name:SetWordWrap(false)
    p.healthText = Font(p.front, 11)
    p.healthText:SetAllPoints()
    p.levelBox = CreateFrame("Frame", nil, p.front)
    p.levelBox:SetPoint("RIGHT", p, "LEFT", -6, 0)
    p.levelBox:SetSize(22, 19)
    p.levelBox:EnableMouse(false)
    p.levelBox.bg = Texture(p.levelBox, "BACKGROUND", {0.035, 0.045, 0.060, 1})
    p.levelBox.bg:SetAllPoints()
    p.levelBox.iron = IronTrim(p.levelBox)
    p.level = Font(p.levelBox, 11)
    p.level:SetAllPoints(p.levelBox)
    self:PaintBorder(p, false)
    p.classIcon = Icon(p.front, 20)
    p.factionIcon = Icon(p.front, 23)
    p.quest = CreateFrame("Frame", nil, p.front)
    p.quest:SetSize(19, 19)
    p.quest:EnableMouse(false)
    p.quest.icon = p.quest:CreateTexture(nil, "ARTWORK")
    p.quest.icon:SetSize(19, 19)
    p.quest.icon:SetPoint("LEFT")
    p.quest.text = Font(p.quest, 9, "LEFT")
    p.quest.text:SetPoint("LEFT", p, "RIGHT", 8, 0)
    p.quest.text:SetTextColor(0.55, 1, 0.48)
    p.quest.text:SetWidth(90)
    p.quest.text:SetWordWrap(false)
    p.quest:Hide()
    p.power = CreateFrame("StatusBar", nil, p)
    p.power:SetStatusBarTexture(RP.media .. "Bar")
    p.power:SetMinMaxValues(0, 100)
    p.power:SetValue(100)
    p.power:SetHeight(10)
    p.power:EnableMouse(false)
    p.power.bg = Texture(p.power, "BACKGROUND", {0.02, 0.025, 0.04, 0.95})
    p.power.bg:SetPoint("TOPLEFT", -1, 1)
    p.power.bg:SetPoint("BOTTOMRIGHT", 1, -1)
    p.power.text = Font(p.power, 9)
    p.power.text:SetAllPoints()
    p.power:Hide()
    p.hasPower = false
    p.cast = CreateFrame("StatusBar", nil, p)
    p.cast:SetStatusBarTexture(RP.media .. "Bar")
    p.cast:SetStatusBarColor(0.48, 0.75, 0.95)
    p.cast:SetHeight(12)
    p.cast:EnableMouse(false)
    p.cast.bg = Texture(p.cast, "BACKGROUND", {0.025, 0.03, 0.05, 0.95})
    p.cast.bg:SetAllPoints()
    p.cast.text = Font(p.cast, 9)
    p.cast.text:SetAllPoints()
    p.cast.icon = p.cast:CreateTexture(nil, "ARTWORK")
    p.cast.icon:SetPoint("RIGHT", p.cast, "LEFT", -3, 0)
    p.cast.icon:SetSize(12, 12)
    p.cast:Hide()
    p.castVisible = false
    p.raidIcon = p.front:CreateTexture(nil, "OVERLAY")
    p.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    p.raidIcon:SetSize(20, 20)
    p.raidIcon:SetPoint("BOTTOM", p, "TOP", 0, 23)
    p.raidIcon:Hide()
    p:SetScript("OnHide", function(frame)
        P:StopBubbles(frame)
        if frame.targetingEye then frame.targetingEye:Hide() end
        if RP.Aggro then RP.Aggro:Forget(frame) end
        if RP.Features then RP.Features:CastHidden(frame) end
        if RP.Auras then RP.Auras:Detach(frame) end
        if RP.QuestieIcons then RP.QuestieIcons:Detach(frame) end
        if RP.LootButton then RP.LootButton:Detach(frame) end
    end)
    if RP.LootButton then RP.LootButton:Build(p) end
    if RP.Features then RP.Features:BuildPlate(p) end
    if RP.Aggro then RP.Aggro:BuildPlate(p) end
    self:Layout(p)
    return p
end

function P:Layout(p)
    local d = RP.db
    local style = p.style or d
    local width, height, fontSize = style.width or d.width, style.height or d.height, style.fontSize or d.fontSize
    local wasAnimating = p.animating
    if wasAnimating then self:StopBubbles(p) end
    p:SetSize(width, height)
    local previewHeight = height + math.max(10, fontSize) + fontSize + 14
        + (d.showDebuffs and (d.debuffSize + 4) or 0)
        + (d.showBuffs and (d.buffSize + 4) or 0)
    p:SetScale(p.unitFrame and 1 or (p.preview and math.min(d.scale, 1.05, 220 / width, 70 / previewHeight) or d.scale))
    if p.nameLayer then p.nameLayer:SetScale(p:GetScale()) end
    p.name:SetFont(FONT, fontSize + 1, "OUTLINE")
    p.healthText:SetFont(FONT, fontSize, "OUTLINE")
    p.level:SetFont(FONT, math.max(10, fontSize), "OUTLINE")
    p.levelBox:SetSize(math.max(22, fontSize + 11), height)
    self:PositionQuest(p)
    p.power.text:SetFont(FONT, math.max(9, fontSize - 2), "OUTLINE")
    p.cast.text:SetFont(FONT, math.max(9, fontSize - 2), "OUTLINE")
    p.cast:SetHeight(math.max(12, fontSize))
    p.power:ClearAllPoints()
    p.power:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, p.unitFrame and -2 or -4)
    p.power:SetPoint("TOPRIGHT", p, "BOTTOMRIGHT", 0, p.unitFrame and -2 or -4)
    p.power:SetHeight(style.powerHeight or math.max(10, fontSize))
    if not p.unitFrame then
        p.classIcon:ClearAllPoints()
        p.factionIcon:ClearAllPoints()
        p.factionIcon:SetPoint("BOTTOMRIGHT", p, "TOPLEFT", -36, -5)
        p.classIcon:SetPoint("TOP", p.factionIcon, "BOTTOM", 0, -3)
    end
    p.raidIcon:ClearAllPoints()
    p.raidIcon:SetPoint("BOTTOM", p, "TOP", 0, d.showDebuffs and (fontSize + d.debuffSize + 12) or 23)
    PositionTargetingEye(p)
    p.liquid.width, p.liquid.height = width, height
    p.liquid.bubbleCount = d.bubbleCount
    p.liquid.bubbleScale = d.bubbleScale * 0.55
    self:PositionCast(p)
    if RP.Auras then RP.Auras:Layout(p) end
    if RP.QuestieIcons then RP.QuestieIcons:Layout(p) end
    if RP.LootButton then RP.LootButton:Layout(p) end
    if wasAnimating then self:StartBubbles(p) end
end

function P:PositionCast(p)
    p.cast:ClearAllPoints()
    local anchor = p.hasPower and p.power or p
    p.cast:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    p.cast:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
end

function P:PositionQuest(p)
    p.quest:ClearAllPoints()
    -- Keep the marker beside the level instead of below the HP/resource bars.
    -- The optional text remains to the right of HP so it cannot cover the level.
    local anchor = RP.db.showLevel and p.levelBox or p
    p.quest:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
end

function P:SetPowerVisible(p, visible)
    local changed = p.hasPower ~= visible
    p.hasPower = visible
    p.power:SetShown(visible)
    if not visible then
        p.power.text:SetText("")
        p.power:SetAlpha(1)
    end
    if changed then
        self:PositionCast(p)
        if RP.Auras then RP.Auras:Layout(p) end
    end
end

function P:SetCastVisible(p, visible)
    local changed = p.castVisible ~= visible
    p.castVisible = visible
    p.cast:SetShown(visible)
    if not visible and RP.Features then RP.Features:CastHidden(p) end
    if changed and RP.Auras then RP.Auras:Layout(p) end
end

function P:StopBubbles(p)
    if p.animating and not p.preview and not p.unitFrame then self.animatedCount = math.max(0, self.animatedCount - 1) end
    p.animating = false
    p.liquid:Stop()
    p.liquid:Hide()
end

function P:StartBubbles(p)
    if p.animating or not RP.db.bubbles or not p:IsShown() then return end
    if not p.preview and not p.unitFrame and self.animatedCount >= RP.db.maxAnimatedPlates then return end
    if not p.preview and not p.unitFrame then self.animatedCount = self.animatedCount + 1 end
    p.animating = true
    p.liquid:Start()
end

function P:SetColor(p, kind)
    local color = RP.colors[kind] or RP.colors.enemy
    p.kind = kind
    p.health:SetStatusBarColor(color[1], color[2], color[3], 1)
    p.healthBg:SetVertexColor(color[1] * 0.13 + 0.035, color[2] * 0.13 + 0.035, color[3] * 0.13 + 0.035, 1)
    p.liquid.tint = color
    if p.animating then p.liquid:Paint() end
end

local function PercentText(fontString, unit, power, current, maximum)
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if curve then
        if power and UnitPowerPercent then
            fontString:SetFormattedText("%.0f%%", UnitPowerPercent(unit, nil, false, curve))
            return
        elseif not power and UnitHealthPercent then
            fontString:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve))
            return
        end
    end
    if RP.Readable(current) and RP.Readable(maximum) and type(maximum) == "number" and maximum > 0 then
        fontString:SetFormattedText("%.0f%%", current / maximum * 100)
    else
        fontString:SetText("—")
    end
end

function P:UpdateHealth(p)
    if not p.isPlayer and p.baseKind then
        local kind = self:NPCKind(p.unit, p.baseKind)
        if kind ~= p.kind then self:SetColor(p, kind) end
    end
    local current, maximum = UnitHealth(p.unit), UnitHealthMax(p.unit)
    -- Both native widget methods accept restricted/secret numbers directly.
    p.health:SetMinMaxValues(0, maximum)
    local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    p.health:SetValue(current, interpolation)
    self:UpdateHealPreview(p.healPreview, p.unit)
    if RP.db.healthText == "value" then p.healthText:SetFormattedText("%d / %d", current, maximum)
    elseif RP.db.healthText == "percent" then PercentText(p.healthText, p.unit, false, current, maximum)
    else p.healthText:SetText("") end
end

function P:ProbePowerAlphaClamp()
    if self.powerAlphaProbed then return self.powerAlphaClamp end
    self.powerAlphaProbed, self.powerAlphaClamp = true, false
    -- Verify the actual client's native [0,1] clamping once with PUBLIC
    -- constants only. Never inspect the alpha of a secret-valued resource bar.
    local probe = CreateFrame("Frame")
    probe:Hide()
    local ok, supported = pcall(function()
        for _, sample in ipairs({{0, 0}, {1, 1}, {2, 1}}) do
            probe:SetAlpha(sample[1])
            local alpha = probe:GetAlpha()
            if RP.IsSecret(alpha) or type(alpha) ~= "number" or alpha ~= sample[2] then return false end
        end
        return true
    end)
    pcall(probe.SetAlpha, probe, 1)
    self.powerAlphaClamp = ok and supported == true
    return self.powerAlphaClamp
end

local function PublicNumber(value)
    return RP.Readable(value) and type(value) == "number"
end

function P:ApplyPowerCapacity(p, current, maximum, powerType)
    if PublicNumber(maximum) then
        if maximum <= 0 then return false end
        p.power:SetAlpha(1)
        return true
    end
    if not RP.IsSecret(maximum) then return false end

    -- Missing is max-current in the native API. When BOTH inputs are public
    -- zero, capacity is genuinely zero even if UnitPowerMax itself is secret.
    -- A missing/denied/secret value is never treated as zero.
    local missing
    if type(UnitPowerMissing) == "function" then
        local ok, value = pcall(UnitPowerMissing, p.unit, powerType)
        if ok then missing = value end
    end
    local currentPublic, missingPublic = PublicNumber(current), PublicNumber(missing)
    if currentPublic and missingPublic and current == 0 and missing == 0 then return false end

    if self:ProbePowerAlphaClamp() then
        -- Native alpha accepts secrets and clamps positive integer capacity to
        -- 1, while capacity 0 makes the bar, background and text transparent.
        -- The value is never read back, compared or converted by addon Lua.
        local ok = pcall(p.power.SetAlpha, p.power, maximum)
        if ok then return true end
    end
    -- On an unsupported client, retain resources whose positive capacity is
    -- confirmed by public data; do not assume a type flag means max > 0.
    if (currentPublic and current > 0) or (missingPublic and missing > 0) then
        p.power:SetAlpha(1)
        return true
    end
    return false
end

function P:UpdatePower(p)
    local allowed = RP.db.showPower and (p.unitFrame or p.isPlayer or RP.db.showPowerNPC)
    if not allowed then
        self:SetPowerVisible(p, false); return
    end
    local ok, powerType, powerToken = pcall(UnitPowerType, p.unit)
    if not ok or RP.IsSecret(powerType) or type(powerType) ~= "number" or powerType < 0 then
        self:SetPowerVisible(p, false); return
    end
    local hasResource
    if type(UnitHasPowerType) == "function" then
        local known, value = pcall(UnitHasPowerType, p.unit, powerType)
        if known and RP.Readable(value) and type(value) == "boolean" then hasResource = value end
    end
    if hasResource == false then self:SetPowerVisible(p, false); return end
    local maximum = UnitPowerMax(p.unit, powerType)
    local current = UnitPower(p.unit, powerType)
    if (RP.Readable(current) and type(current) ~= "number")
        or not self:ApplyPowerCapacity(p, current, maximum, powerType) then
        self:SetPowerVisible(p, false); return
    end
    local color = RP.Readable(powerToken) and PowerBarColor and PowerBarColor[powerToken]
    if color then p.power:SetStatusBarColor(color.r, color.g, color.b)
    else p.power:SetStatusBarColor(0.25, 0.55, 1) end
    p.power:SetMinMaxValues(0, maximum)
    p.power:SetValue(current)
    if RP.db.powerText == "value" then p.power.text:SetFormattedText("%d / %d", current, maximum)
    elseif RP.db.powerText == "percent" then PercentText(p.power.text, p.unit, true, current, maximum)
    else p.power.text:SetText("") end
    self:SetPowerVisible(p, true)
end

function P:PaintClassIcon(p, class)
    local icon = p.classIcon
    icon.classToken = class
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        or RP.classIconCoords[class]
    if coords then
        icon.tex:SetTexture(RP.classAtlas)
        icon.tex:SetTexCoord(unpack(coords))
    else
        icon.tex:SetTexture(RP.classIcons[class])
        icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    icon.tex:SetVertexColor(1, 1, 1, 1)
    icon:Show()
end

function P:PaintFactionIcon(p, faction)
    local icon = p.factionIcon
    icon.factionToken = faction
    local loaded = icon.tex:SetTexture(RP.factionIcons[faction])
    if RP.Readable(loaded) and loaded == false then
        icon.tex:SetTexture(RP.factionFallbackIcons[faction])
        icon.tex:SetTexCoord(0, 0.5, 0, 0.6)
    else icon.tex:SetTexCoord(0, 1, 0, 1) end
    icon.tex:SetVertexColor(1, 1, 1, 1)
    icon:Show()
end

function P:UpdateName(p)
    local name = RP:DisplayName(p.unit)
    if RP.IsSecret(name) then p.name:SetText(name) else p.name:SetText(name or "…") end
end

function P:UpdateIdentity(p)
    self:UpdateName(p)
    if RP.db.showLevel then
        local level = UnitLevel(p.unit)
        if RP.Readable(level) and (not level or level <= 0) then p.level:SetText("??")
        else p.level:SetFormattedText("%d", level) end
        p.level:Show(); p.levelBox:Show()
    else p.level:Hide(); p.levelBox:Hide() end
    p.classIcon:Hide(); p.factionIcon:Hide()
    p.classIcon.classToken, p.factionIcon.factionToken = nil, nil
    if not p.isPlayer then return end
    local _, class = UnitClass(p.unit)
    if RP.db.showClass and RP.Readable(class) and class and RP.classIcons[class] then
        self:PaintClassIcon(p, class)
    end
    if RP.db.showFaction and p.kind == "enemy" then
        local faction = UnitFactionGroup(p.unit)
        if RP.Readable(faction) and faction and RP.factionIcons[faction] then
            self:PaintFactionIcon(p, faction)
        end
    end
    if not p.unitFrame then
        if not p.factionIcon:IsShown() then
            p.classIcon:ClearAllPoints()
            p.classIcon:SetPoint("RIGHT", p, "LEFT", -36, 0)
        else
            p.classIcon:ClearAllPoints()
            p.classIcon:SetPoint("TOP", p.factionIcon, "BOTTOM", 0, -3)
        end
    end
end

function P:UpdateTarget(p)
    local selected = RP.db.targetBorder and RP.PublicTrue(UnitIsUnit(p.unit, "target"))
    self:PaintBorder(p, selected)
    local marker = GetRaidTargetIndex and GetRaidTargetIndex(p.unit)
    if RP.Readable(marker) and type(marker) == "number" and marker >= 1 and marker <= 8 then
        local col, row = (marker - 1) % 4, math.floor((marker - 1) / 4)
        p.raidIcon:SetTexCoord(col / 4, (col + 1) / 4, row / 2, (row + 1) / 2)
        p.raidIcon:Show()
    else p.raidIcon:Hide() end
    PositionTargetingEye(p)
end

local questTextures = {kill = "QuestKill", loot = "QuestLoot", quest = "Quest"}

local function BuildQuestBeacon(p)
    local beacon = CreateFrame("Frame", nil, p.base)
    beacon:SetSize(29, 29)
    beacon:SetFrameLevel(p.front:GetFrameLevel() + 1)
    beacon:SetPoint("BOTTOM", p.base, "TOP", 0, 6)
    beacon:EnableMouse(false)
    beacon.icon = beacon:CreateTexture(nil, "ARTWORK")
    beacon.icon:SetAllPoints()
    p.questBeacon = beacon
    return beacon
end

function P:PaintQuest(p, info)
    p.quest:Hide()
    p.quest.text:SetText("")
    if p.questBeacon then p.questBeacon:Hide() end
    if not RP.db.questMarkers or not info or p.isPlayer then
        PositionTargetingEye(p)
        return
    end
    local kind = questTextures[info.kind] and info.kind or "quest"
    local texture = RP.media .. questTextures[kind]
    if p.base and not p.visible then
        local beacon = p.questBeacon or BuildQuestBeacon(p)
        beacon.icon:SetTexture(texture)
        beacon:Show()
        PositionTargetingEye(p)
        return
    end
    p.quest.icon:SetTexture(texture)
    local label = kind:upper()
    if RP.db.questText and type(info.progress) == "string" and RP.Readable(info.progress) then
        label = label .. " " .. info.progress
    end
    p.quest.text:SetShown(RP.db.questText)
    if RP.db.questText then p.quest.text:SetText(label) end
    p.quest.icon:Show()
    p.quest:Show()
    PositionTargetingEye(p)
end

function P:UpdateQuest(unit, info)
    if not SafeUnit(unit) then return end
    local p = self.active[unit]
    if p then self:PaintQuest(p, info) end
end

function P:UpdateCast(p)
    if p.unitFrame and p.unit == "player" then
        self:SetCastVisible(p, false)
        p.cast.text:SetText("")
        p.cast.icon:SetTexture(nil)
        return
    end
    if not RP.db.showCast or not p.cast.SetTimerDuration then self:SetCastVisible(p, false); return end
    local name, icon, locked, channel = ReadCastInfo(p.unit)
    if RP.Readable(name) and name == nil then self:SetCastVisible(p, false); return end
    local getter = channel and UnitChannelDuration or UnitCastingDuration
    if not getter then self:SetCastVisible(p, false); return end
    local duration = getter(p.unit)
    if RP.Readable(duration) and duration == nil then self:SetCastVisible(p, false); return end
    local direction = Enum and Enum.StatusBarTimerDirection
    local timerDirection = direction and (channel and direction.RemainingTime or direction.ElapsedTime)
    local ok = pcall(p.cast.SetTimerDuration, p.cast, duration, nil, timerDirection)
    if not ok then self:SetCastVisible(p, false); return end
    p.cast.text:SetText(name)
    p.cast.icon:SetTexture(icon)
    if RP.PublicTrue(locked) then p.cast:SetStatusBarColor(0.46, 0.49, 0.56)
    else p.cast:SetStatusBarColor(0.38, 0.74, 0.91) end
    self:SetCastVisible(p, true)
    if RP.Features then RP.Features:UpdateCast(p, locked) end
end

function P:Suppress(p, unitFrame)
    local function NonForbidden(frame)
        local ok, forbidden = pcall(function()
            if not RP.Readable(frame) or not frame or type(frame.IsForbidden) ~= "function" then return nil end
            return frame:IsForbidden()
        end)
        return ok and RP.Readable(forbidden) and forbidden == false
    end
    if not NonForbidden(unitFrame) then return false end
    if p.original and p.original ~= unitFrame then self:RestoreOriginal(p) end
    local previous = self.suppressed[unitFrame]
    if previous and previous ~= p then self:RestoreOriginal(previous) end
    if self.suppressed[unitFrame] ~= p then
        p.original = unitFrame
        local alpha = unitFrame:GetAlpha()
        p.originalAlpha = RP.Readable(alpha) and alpha or 1
        self.suppressed[unitFrame] = p
    end
    if not self.hooked[unitFrame] and hooksecurefunc then
        self.hooked[unitFrame] = true
        hooksecurefunc(unitFrame, "SetAlpha", function(frame)
            local owner = P.suppressed[frame]
            if owner and not P.settingAlpha and RP.db.enabled and NonForbidden(frame) then
                P.settingAlpha = true
                pcall(frame.SetAlpha, frame, 0)
                P.settingAlpha = false
            end
        end)
    end
    self.settingAlpha = true
    local ok = pcall(unitFrame.SetAlpha, unitFrame, 0)
    self.settingAlpha = false
    if not ok then return false end
    -- Blizzard's selection/mouseover strip explicitly ignores parent alpha.
    -- Let just this known region inherit the hidden stock frame's alpha while
    -- we own it; leave Blizzard's normal Show/Hide updates in place.
    if not p.originalHighlight then
        local changed, highlight, previousIgnore = pcall(function()
            local region = unitFrame.selectionHighlight
            if not NonForbidden(region) or type(region.IsIgnoringParentAlpha) ~= "function"
                or type(region.SetIgnoreParentAlpha) ~= "function" then return nil end
            local ignoring = region:IsIgnoringParentAlpha()
            if not RP.Readable(ignoring) or type(ignoring) ~= "boolean" then return nil end
            region:SetIgnoreParentAlpha(false)
            local applied = region:IsIgnoringParentAlpha()
            if not RP.Readable(applied) or applied ~= false then return nil end
            return region, ignoring
        end)
        if changed and highlight then p.originalHighlight = {region = highlight, ignoring = previousIgnore} end
    end
    return true
end

function P:RestoreOriginal(p)
    local original = p.original
    if original then
        if self.suppressed[original] == p then
            self.suppressed[original] = nil
            local saved = p.originalHighlight
            if saved then
                pcall(function()
                    local forbidden = original:IsForbidden()
                    if not RP.Readable(forbidden) or forbidden ~= false then return end
                    local region = saved.region
                    local regionForbidden = region:IsForbidden()
                    if not RP.Readable(regionForbidden) or regionForbidden ~= false then return end
                    local current = region:IsIgnoringParentAlpha()
                    -- Preserve a later change made by another addon.
                    if RP.Readable(current) and current == false then region:SetIgnoreParentAlpha(saved.ignoring) end
                end)
            end
            local readable, forbidden = pcall(function() return original:IsForbidden() end)
            if readable and RP.Readable(forbidden) and forbidden == false then
                pcall(original.SetAlpha, original, p.originalAlpha or 1)
            end
        end
        p.original, p.originalAlpha = nil, nil
    end
    p.originalHighlight = nil
end

function P:Refresh(p)
    if not RP.db.enabled or not Exists(p.unit) or IsObject(p.unit) then
        p.visible = false
        if p.nameLayer then p.nameLayer:Hide() end
        if RP.EnemyRange then RP.EnemyRange:Reset(p) end
        if p.targetingEye then p.targetingEye:Hide() end
        HideCastWarning(p)
        self:PaintQuest(p, nil)
        p:Hide()
        return
    end
    local kind, visible, player, baseKind = self:Classify(p.unit)
    p.distant = Distant(p)
    visible = visible and not p.distant
    p.visible, p.isPlayer, p.baseKind = visible, player, baseKind or kind
    self:Layout(p)
    self:SetColor(p, kind)
    if p.nameLayer then p.nameLayer:SetShown(visible or player) end
    if RP.EnemyRange then RP.EnemyRange:Update(p) end
    if self.targetEyeTicker then self.targetEyeTicker:Show() end
    local questInfo
    if RP.Quest and RP.db.questMarkers and not player then questInfo = RP.Quest:GetUnitInfo(p.unit) end
    if not visible then
        if player then self:UpdateName(p) end
        p:Hide()
        self:PaintQuest(p, questInfo)
        self:UpdateTargetingEye(p)
        self:UpdateCastWarning(p)
        return
    end
    self:UpdateIdentity(p)
    self:UpdateHealth(p)
    self:UpdatePower(p)
    self:UpdateTarget(p)
    self:UpdateCast(p)
    self:PaintQuest(p, questInfo)
    p:Show()
    self:UpdateTargetingEye(p)
    self:UpdateCastWarning(p)
    self:StartBubbles(p)
    if RP.Aggro then RP.Aggro:Refresh(p) end
    if RP.Auras then RP.Auras:Attach(p, p.unit) end
    if RP.QuestieIcons then RP.QuestieIcons:Attach(p) end
    if RP.LootButton then RP.LootButton:Refresh(p) end
end

function P:UpdateTargetVisibility()
    -- A selected friendly unit may currently have a hidden custom plate.
    -- Re-evaluate those too, but leave unchanged plates and aura containers
    -- attached so ordinary target switches do not rebuild the whole scene.
    for _, p in pairs(self.active) do
        local distant = Distant(p)
        if p.distant ~= distant then
            self:Refresh(p)
        elseif p.isPlayer then
            local kind, visible = self:Classify(p.unit)
            visible = visible and not distant
            if p.visible ~= visible or p.kind ~= kind then
                self:Refresh(p)
            elseif p.visible then
                self:UpdateTarget(p)
            end
        elseif p.visible then
            self:UpdateTarget(p)
        end
    end
end

function P:Attach(unit, retried)
    if not SafeUnit(unit) or not RP.db.enabled or not Exists(unit) or IsObject(unit) then return end
    if RP.PublicTrue(UnitIsUnit(unit, "player")) then return end
    local base = C_NamePlate.GetNamePlateForUnit(unit)
    if not base then return end
    if not RP.CanUseFrame(base) then self.forbiddenCount = self.forbiddenCount + 1; return end
    local original = base.UnitFrame
    if not original then
        if not retried and C_Timer and C_Timer.After then
            C_Timer.After(0, function() P:Attach(unit, true) end)
        end
        return
    end
    if not RP.CanUseFrame(original) then self.forbiddenCount = self.forbiddenCount + 1; return end
    local p = self.frames[base]
    if not p then p = self:Build(base); self.frames[base] = p end
    if p.unit and p.unit ~= unit then self:Detach(p.unit) end
    if self.active[unit] and self.active[unit] ~= p then self:Detach(unit) end
    p.unit, p.base = unit, base
    p:ClearAllPoints()
    p:SetPoint("CENTER", base, "CENTER", 0, RP.db.verticalOffset)
    self.active[unit] = p
    if not self:Suppress(p, original) then
        self:Detach(unit)
        return
    end
    self:Refresh(p)
end

function P:Detach(unit)
    if not SafeUnit(unit) then return end
    local p = self.active[unit]
    if not p then return end
    self.active[unit] = nil
    if p.nameLayer then p.nameLayer:Hide() end
    if RP.EnemyRange then RP.EnemyRange:Reset(p) end
    if self.targetEyeTicker and not next(self.active) then self.targetEyeTicker:Hide() end
    if p.targetingEye then p.targetingEye:Hide() end
    HideCastWarning(p)
    if p.questBeacon then p.questBeacon:Hide() end
    if RP.Aggro then RP.Aggro:Forget(p) end
    if RP.QuestieIcons then RP.QuestieIcons:Detach(p) end
    if RP.LootButton then RP.LootButton:Detach(p) end
    self:RestoreOriginal(p)
    self:StopBubbles(p)
    self:UpdateHealPreview(p.healPreview)
    if RP.Auras then RP.Auras:Detach(p) end
    p:Hide()
    p.quest:Hide(); p.cast:Hide(); p.power:Hide(); p.power.text:SetText(""); p.power:SetAlpha(1)
    p.classIcon:Hide(); p.factionIcon:Hide(); p.raidIcon:Hide()
    p.unit, p.visible, p.isPlayer, p.hasPower = nil, false, false, false
    p.castVisible, p.distant, p.baseKind = false, false, nil
    p.endedCastBarID = nil
    if RP.Quest then RP.Quest:Forget(unit) end
end

function P:RefreshAll()
    local old = {}
    for unit in pairs(self.active) do old[#old + 1] = unit end
    for _, unit in ipairs(old) do self:Detach(unit) end
    if not RP.db.enabled then return end
    local bases = C_NamePlate.GetNamePlates()
    for _, base in pairs(bases) do
        if RP.CanUseFrame(base) then
            local unit = base.GetUnit and base:GetUnit() or base.namePlateUnitToken
            if not unit and base.UnitFrame and RP.CanUseFrame(base.UnitFrame) then unit = base.UnitFrame.unit end
            if SafeUnit(unit) then self:Attach(unit) end
        end
    end
end

function P:UpdateDemo(p, data)
    self:StopBubbles(p)
    self:Layout(p)
    p.name:SetText(data.name)
    local kind = data.kind
    if kind == "tapped" and not RP.db.grayTapped then kind = data.baseKind or "enemy" end
    if kind == "trivial" and not RP.db.grayTrivial then kind = data.baseKind or "enemy" end
    self:SetColor(p, kind)
    p.health:SetMinMaxValues(0, data.max)
    p.health:SetValue(data.hp)
    if data.heal or data.healAbsorb then
        p.healPreview = p.healPreview or self:BuildHealPreview(p.health, false, true)
        DisplayHealAmounts(p.healPreview, data.max, data.heal or 0, data.healAbsorb or 0)
    else
        self:UpdateHealPreview(p.healPreview)
    end
    if RP.db.healthText == "value" then p.healthText:SetFormattedText("%d / %d", data.hp, data.max)
    elseif RP.db.healthText == "percent" then p.healthText:SetFormattedText("%.0f%%", data.hp / data.max * 100)
    else p.healthText:SetText("") end
    p.level:SetText(data.level or 25)
    p.level:SetShown(RP.db.showLevel)
    p.levelBox:SetShown(RP.db.showLevel)
    p.classIcon:Hide(); p.factionIcon:Hide()
    p.classIcon.classToken, p.factionIcon.factionToken = nil, nil
    if data.class and RP.db.showClass then
        self:PaintClassIcon(p, data.class)
        if not p.unitFrame then
            p.classIcon:ClearAllPoints()
            p.classIcon:SetPoint("RIGHT", p, "LEFT", -36, 0)
        end
    end
    if data.faction and RP.db.showFaction then
        self:PaintFactionIcon(p, data.faction)
        if not p.unitFrame then
            p.classIcon:ClearAllPoints()
            p.classIcon:SetPoint("TOP", p.factionIcon, "BOTTOM", 0, -3)
        end
    end
    p.hasPower = data.power ~= nil and type(data.powerMax) == "number" and data.powerMax > 0 and RP.db.showPower
    if p.hasPower then
        p.power:SetAlpha(1)
        p.power:SetMinMaxValues(0, data.powerMax)
        p.power:SetValue(data.power)
        p.power:SetStatusBarColor(unpack(data.powerColor))
        if RP.db.powerText == "value" then p.power.text:SetFormattedText("%d / %d", data.power, data.powerMax)
        elseif RP.db.powerText == "percent" then p.power.text:SetFormattedText("%.0f%%", data.power / data.powerMax * 100)
        else p.power.text:SetText("") end
        p.power:Show()
    else p.power:Hide() end
    p.isPlayer = data.class ~= nil
    p.castVisible = false
    p.cast:Hide()
    self:PaintQuest(p, data.quest)
    self:PaintBorder(p, false)
    p:Show()
    self:StartBubbles(p)
    if RP.Auras then RP.Auras:Preview(p, data.debuffs, data.buffs) end
end

-- Position of the public cast bar ID in each event's payload after the unit.
local castEnd = {
    UNIT_SPELLCAST_STOP = 3, UNIT_SPELLCAST_FAILED = 3,
    UNIT_SPELLCAST_INTERRUPTED = 4, UNIT_SPELLCAST_CHANNEL_STOP = 4, UNIT_SPELLCAST_EMPOWER_STOP = 5,
}
local castStart = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true,
}
local castTimingUpdate = {
    UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_EMPOWER_UPDATE = true,
}

function P:Initialize()
    self:ProbePowerAlphaClamp()
    local ticker = CreateFrame("Frame")
    self.targetEyeTicker = ticker
    ticker:Hide()
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        -- Some target changes arrive under another unit token or without a
        -- nameplate event. Recheck visible plates without rebuilding them.
        P:RefreshTargetingEyes(true)
    end)
    local f = CreateFrame("Frame")
    self.eventFrame = f
    local events = {
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "RAID_TARGET_UPDATE", "PLAYER_LEVEL_UP", "UNIT_TARGET",
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
        "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_GUILD_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_FLAGS",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    }
    for _, event in ipairs(events) do pcall(f.RegisterEvent, f, event) end
    f:SetScript("OnEvent", function(_, event, unit, ...)
        if event == "NAME_PLATE_UNIT_REMOVED" then P:Detach(unit); return end
        if not RP.db.enabled then return end
        if event == "NAME_PLATE_UNIT_ADDED" then P:Attach(unit); return end
        if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" then P:RefreshAll(); return end
        if event == "PLAYER_LEVEL_UP" then
            if C_Timer and C_Timer.After then C_Timer.After(0, function() P:RefreshAll() end)
            else P:RefreshAll() end
            return
        end
        if event == "PLAYER_TARGET_CHANGED" then P:UpdateTargetVisibility(); return end
        if event == "UNIT_TARGET" then
            local p = SafeUnit(unit) and P.active[unit]
            if p then P:UpdateTargetingEye(p) else P:RefreshTargetingEyes() end
            return
        end
        if event == "RAID_TARGET_UPDATE" then
            for _, p in pairs(P.active) do if p.visible then P:UpdateTarget(p) end end
            return
        end
        if not SafeUnit(unit) then return end
        local p = P.active[unit]
        local spellcast = event:find("UNIT_SPELLCAST", 1, true)
        local healing = event == "UNIT_HEAL_PREDICTION" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
        if not p and (spellcast or healing) then
            local ok, base = pcall(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit)
            local alias = ok and RP.Readable(base) and base and P.frames[base]
            if alias and alias.unit and P.active[alias.unit] == alias then p = alias end
        end
        if spellcast then
            if not p then return end
            local endIndex = castEnd[event]
            if endIndex then
                local endedID = PublicCastID(select(endIndex, ...))
                local warning = p.targetingEye and p.targetingEye.castWarning
                local currentID = warning and warning.castBarID
                if endedID and currentID and endedID ~= currentID then return end
                p.endedCastBarID = endedID or currentID
                HideCastWarning(p)
            else
                if castStart[event] then p.endedCastBarID = nil end
                P:UpdateCastWarning(p, castStart[event] or castTimingUpdate[event])
            end
            if p.visible then P:UpdateCast(p) end
            return
        end
        if not p then return end
        if event == "UNIT_FACTION" or event == "UNIT_FLAGS" or event == "UNIT_LEVEL" then P:Refresh(p); return end
        if not p.visible then
            if p.isPlayer and (event == "UNIT_NAME_UPDATE" or event == "UNIT_GUILD_UPDATE") then P:UpdateName(p) end
            return
        end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then P:UpdateHealth(p)
        elseif healing then P:UpdateHealPreview(p.healPreview, p.unit)
        elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_GUILD_UPDATE" then
            P:UpdateIdentity(p)
            if RP.LootButton then RP.LootButton:Refresh(p) end
        else P:UpdatePower(p) end
    end)
end
