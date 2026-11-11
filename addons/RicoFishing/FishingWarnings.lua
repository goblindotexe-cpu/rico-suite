local _, F = ...
local W = {}
F.Warnings = W

local MAIN_HAND = INVSLOT_MAINHAND or 16
-- Forever's fishing lures share these temporary enchants by skill bonus.
local LURE_BONUS = { [263] = 25, [264] = 50, [265] = 75, [266] = 100 }
local LOW_BAGS = 2
local AMBER, RED = "|cffffba57", "|cffff625c"
local MINT = { 0.52, 1, 0.77 }
local BAIT_COLORS = {
    ready = { 0.76, 0.91, 0.83 },
    low = { 1, 0.74, 0.37 },
    missing = { 1, 0.79, 0.48 },
    unknown = { 0.64, 0.72, 0.69 },
}
local unpack = unpack or table.unpack

local function EquippedPole()
    local ok, itemID = F.Call(GetInventoryItemID, "player", MAIN_HAND)
    if not ok or not F.Number(itemID) then return end
    local getter = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local read, _, _, _, _, _, classID, subclassID = F.Call(getter, itemID)
    if read and F.Number(classID) and F.Number(subclassID) and classID == 2 and subclassID == 20 then
        return itemID
    end
end

local function TemporaryEnchant()
    local getter = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
    if type(getter) == "function" then
        local ok, info = F.Call(getter, MAIN_HAND)
        if not ok or F.IsSecret(info) then return end
        if not info then return false end
        if type(info) ~= "table" or (canaccesstable and not canaccesstable(info)) then return end
        return true, info.remainingTimeMs, info.enchantID
    end
    local ok, active, milliseconds, _, enchantID = F.Call(GetWeaponEnchantInfo)
    if ok and not F.IsSecret(active) then return active, milliseconds, enchantID end
end

local function LureTime()
    local active, milliseconds, enchantID = TemporaryEnchant()
    if active == nil then return end
    if active ~= true then return 0 end
    if not F.Number(enchantID) then return end
    local bonus = LURE_BONUS[enchantID]
    if not bonus then return 0 end
    if not F.Number(milliseconds) then return end
    return math.max(0, math.ceil(milliseconds / 1000)), bonus
end

local function GeneralBagSlots()
    local getter = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    local total = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local ok, free, family = F.Call(getter, bag)
        if not ok or not F.Number(free) or free < 0 or F.IsSecret(family) then return end
        if family == 0 or (bag == 0 and family == nil) then
            total = total + free
        elseif free > 0 and not F.Number(family) then
            return
        end
    end
    return total
end

function W:UpdateBags()
    self.bagText = nil
    if not F.db.bagWarning then return end
    local free = GeneralBagSlots()
    if free == nil then return end
    if free > LOW_BAGS then
        self.bagNotice = nil
    elseif self.pole then
        local severity = free == 0 and 2 or 1
        local message = free == 0 and "Bags full" or ("Bag space low: %d free"):format(free)
        self.bagText = (severity == 2 and RED or AMBER) .. message .. "|r"
        if severity > (self.bagNotice or 0) then
            self.bagNotice = severity
            F:Print(self.bagText)
        end
    end
end

function W:UpdateLure()
    self.baitText, self.baitState = nil, nil
    if not self.pole or not F.db.lureTimer then
        self.lureSeconds = nil
        return
    end

    local seconds, bonus = LureTime()
    if seconds == nil then
        self.baitText, self.baitState = "Bait timer unavailable", "unknown"
        return
    end
    if seconds > 0 then
        self.baitText = ("Bait +%d  %d:%02d"):format(bonus, math.floor(seconds / 60), seconds % 60)
        self.baitState = seconds <= 30 and "low" or "ready"
    else
        self.baitText, self.baitState = "No Bait", "missing"
        if self.lureSeconds and self.lureSeconds > 0 then
            F:Print(AMBER .. "Fishing lure expired.|r")
        end
    end
    self.lureSeconds = seconds
end

local function PromptMode()
    local mode = F.OneKey and F.OneKey.mode
    if not F.db.fishingPrompt or (mode ~= "cast" and mode ~= "reel") then return end
    local hasMount, mounted = F.Call(IsMounted)
    if hasMount and not F.IsSecret(mounted) and mounted == true then return end
    local hasDeath, dead = F.Call(UnitIsDeadOrGhost, "player")
    if hasDeath and not F.IsSecret(dead) and dead == true then return end
    return mode
end

local function Tick(_, elapsed)
    W.elapsed = (W.elapsed or 0) + elapsed
    if W.elapsed < 0.25 then return end
    W.elapsed = 0
    W:UpdateLure()
    W:RefreshPrompt()
end

local SHORT_MODIFIER = { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift", META = "Meta" }
local KEY_FONT_SIZES = { 28, 19, 14, 11, 9 }

local function UpdatePromptKey(prompt, binding)
    local base, modifiers = F.OneKey:GetKeyParts(binding)
    local key = F.OneKey:GetKeyLabel(base)
    local modifierLabels = {}
    for _, modifier in ipairs(modifiers) do
        local label = SHORT_MODIFIER[modifier]
        modifierLabels[#modifierLabels + 1] = #modifiers > 2 and label:sub(1, 1) or label
    end
    local modifierText = table.concat(modifierLabels, "+")
    local letter = prompt.keyLetter
    letter:SetText(key)
    for _, size in ipairs(KEY_FONT_SIZES) do
        letter:SetFont(F.Theme.font, size, "OUTLINE")
        if letter:GetUnboundedStringWidth() <= 38 then break end
    end
    letter:ClearAllPoints()
    letter:SetPoint("CENTER", 0, modifierText ~= "" and -5 or -1.5)
    prompt.keyModifiers:SetText(modifierText)
    prompt.keyModifiers:SetShown(modifierText ~= "")
end

function W:RefreshPrompt()
    if not F.db then return end
    local prompt = self.prompt
    local mode = prompt and PromptMode()
    if mode then
        local binding = F.db.fishingKey or "F"
        if prompt.binding ~= binding then
            prompt.binding = binding
            UpdatePromptKey(prompt, binding)
        end
        if prompt.mode ~= mode then
            prompt.mode = mode
            prompt.action:SetText(mode == "reel" and "Reel at splash" or "Cast line")
            prompt.action:SetTextColor(unpack(mode == "reel" and MINT or { 0.95, 0.99, 0.97 }))
        end
        if prompt.baitText ~= self.baitText then
            prompt.baitText = self.baitText
            prompt.bait:SetText(self.baitText or "")
        end
        if prompt.baitState ~= self.baitState then
            prompt.baitState = self.baitState
            local color = BAIT_COLORS[self.baitState] or BAIT_COLORS.ready
            prompt.bait:SetTextColor(unpack(color))
            prompt.baitMark:SetVertexColor(unpack(color))
        end
        local hasBaitStatus = self.baitText ~= nil
        if prompt.baitShown ~= hasBaitStatus then
            prompt.baitShown = hasBaitStatus
            prompt.bait:SetShown(hasBaitStatus)
            prompt.baitMark:SetShown(hasBaitStatus)
            prompt.action:ClearAllPoints()
            prompt.action:SetPoint("LEFT", 59, hasBaitStatus and 7 or 0)
        end
    end
    if prompt then prompt:SetShown(mode ~= nil) end

    local lureText = not mode and self.baitText
    if lureText and (self.baitState == "low" or self.baitState == "missing") then
        lureText = AMBER .. lureText .. "|r"
    end
    local bagText = self.pole and self.bagText
    local label = lureText and bagText and (lureText .. "  •  " .. bagText) or lureText or bagText
    if self.hud then
        if label ~= self.label then self.hud.text:SetText(label or "") end
        self.label = label
        self.hud:SetShown(label ~= nil)
    end

    -- One visible frame owns the countdown, even if a bag warning is also up.
    local visible = mode and prompt or label and self.hud
    local driver = self.pole and F.db.lureTimer and visible or nil
    if driver ~= self.driver then
        if self.driver then self.driver:SetScript("OnUpdate", nil) end
        self.driver, self.elapsed = driver, 0
        if driver then driver:SetScript("OnUpdate", Tick) end
    end
end

function W:RefreshOptions()
    if not self.hud then return end
    self.pole = EquippedPole()
    self:UpdateBags()
    self:UpdateLure()
    self:RefreshPrompt()
end

local function Rect(parent, layer, x, y, width, height, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(r, g, b, a)
    texture:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    texture:SetSize(width, height)
    return texture
end

local function CutFill(parent, layer, x, y, width, height, cut, r, g, b)
    Rect(parent, layer, x, y + cut, width, height - 2 * cut, r, g, b, 1)
    local top = Rect(parent, layer, x, y + height - cut, width, cut, r, g, b, 1)
    top:SetVertexOffset(UPPER_LEFT_VERTEX or 1, cut, 0)
    top:SetVertexOffset(UPPER_RIGHT_VERTEX or 3, -cut, 0)
    local bottom = Rect(parent, layer, x, y, width, cut, r, g, b, 1)
    bottom:SetVertexOffset(LOWER_LEFT_VERTEX or 2, cut, 0)
    bottom:SetVertexOffset(LOWER_RIGHT_VERTEX or 4, -cut, 0)
end

local function CutOutline(parent, x, y, width, height, cut, thickness, colors, additive)
    local points = {
        { x + cut, y + height }, { x + width - cut, y + height },
        { x + width, y + height - cut }, { x + width, y + cut },
        { x + width - cut, y }, { x + cut, y },
        { x, y + cut }, { x, y + height - cut },
    }
    for i, point in ipairs(points) do
        local nextPoint = points[i % #points + 1]
        local line = parent:CreateLine(nil, "ARTWORK")
        line:SetStartPoint("BOTTOMLEFT", parent, point[1], point[2])
        line:SetEndPoint("BOTTOMLEFT", parent, nextPoint[1], nextPoint[2])
        line:SetThickness(thickness)
        line:SetColorTexture(unpack(colors[(i >= 3 and i <= 6) and 2 or 1]))
        if additive then line:SetBlendMode("ADD") end
    end
end

local function Metal(parent, x, y, width, height, cut)
    CutFill(parent, "BACKGROUND", x, y, width, height, cut, 0.12, 0.18, 0.15)
    CutFill(parent, "BORDER", x + 2, y + 2, width - 4, height - 4, cut - 1, 0.025, 0.042, 0.035)
    Rect(parent, "BORDER", x + 3, y + height - cut - 2, width - 6, 2, 0.09, 0.15, 0.12, 0.82)
    Rect(parent, "BORDER", x + 3, y + cut, width - 6, 2, 0.008, 0.016, 0.012, 1)
    CutOutline(parent, x, y, width, height, cut, 2.4, {
        { 0.23, 0.31, 0.28, 1 }, { 0.065, 0.099, 0.082, 1 },
    })
    CutOutline(parent, x + 2, y + 2, width - 4, height - 4, cut - 1, 1.1, {
        { 0.34, 0.51, 0.41, 0.88 }, { 0.14, 0.26, 0.19, 0.91 },
    })
end

local function PromptText(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(F.Theme.font, size, "OUTLINE")
    text:SetTextColor(unpack(color))
    text:SetShadowColor(0, 0, 0, 0.95)
    text:SetShadowOffset(1, -1)
    return text
end

function W:CreatePrompt()
    if self.prompt then return end
    local prompt = CreateFrame("Frame", nil, UIParent)
    self.prompt = prompt
    prompt:Hide()
    prompt:SetSize(186, 56)
    prompt:SetPoint("LEFT", UIParent, "CENTER", 112, -42)
    prompt:SetFrameStrata("MEDIUM")
    prompt:SetClampedToScreen(true)
    prompt:EnableMouse(false)

    Metal(prompt, 36, 7, 147, 42, 6)
    Rect(prompt, "BORDER", 59, 11, 110, 1, 0.17, 0.35, 0.25, 0.53)
    prompt.action = PromptText(prompt, 14, { 0.95, 0.99, 0.97 })
    prompt.bait = PromptText(prompt, 11, BAIT_COLORS.ready)
    prompt.bait:SetPoint("LEFT", 68, -9)
    prompt.baitMark = Rect(prompt, "ARTWORK", 59, 17, 4, 4, 1, 1, 1, 1)
    prompt.baitMark:SetRotation(math.pi / 4)

    local key = CreateFrame("Frame", nil, prompt)
    key:SetPoint("LEFT", 1, 0)
    key:SetSize(51, 52)
    key:EnableMouse(false)

    local smokePath = "Interface\\AddOns\\" .. F.name .. "\\Media\\PromptSmoke.tga"
    local smoke = prompt:CreateTexture(nil, "BACKGROUND", nil, -2)
    smoke:SetTexture(smokePath)
    smoke:SetPoint("CENTER", key, "CENTER", 4, 0)
    smoke:SetSize(156, 156)
    smoke:SetVertexColor(0.54, 0.70, 0.62, 0.40)
    local smokeGlow = prompt:CreateTexture(nil, "BACKGROUND", nil, -1)
    smokeGlow:SetTexture(smokePath)
    smokeGlow:SetAllPoints(smoke)
    smokeGlow:SetBlendMode("ADD")
    smokeGlow:SetVertexColor(0.31, 1, 0.62)

    Metal(key, 1, 2, 49, 48, 9)
    CutOutline(key, 5, 6, 41, 40, 6, 1, {
        { 0.38, 0.79, 0.56, 0.83 }, { 0.17, 0.36, 0.25, 0.88 },
    })
    Rect(key, "BORDER", 10, 11, 31, 30, 0.03, 0.073, 0.052, 0.72)
    Rect(key, "BORDER", 12, 39, 27, 1, 0.18, 0.36, 0.25, 0.7)
    prompt.keyLetter = PromptText(key, 28, { 0.91, 1, 0.95 })
    prompt.keyLetter:SetJustifyH("CENTER")
    prompt.keyLetter:SetWidth(38)
    prompt.keyLetter:SetWordWrap(true)
    prompt.keyLetter:SetNonSpaceWrap(true)
    prompt.keyLetter:SetMaxLines(3)
    prompt.keyModifiers = PromptText(key, 8, MINT)
    prompt.keyModifiers:SetPoint("CENTER", 0, 13)

    local aura = CreateFrame("Frame", nil, key)
    aura:SetAllPoints(key)
    aura:EnableMouse(false)
    CutOutline(aura, 2, 3, 47, 46, 8, 1.3, {
        { 0.53, 1, 0.74, 0.97 }, { 0.29, 0.86, 0.55, 0.74 },
    }, true)
    for _, x in ipairs({ 8, 43 }) do
        local rivet = Rect(aura, "OVERLAY", x - 1.5, 25, 3, 3, 0.66, 1, 0.78, 0.95)
        rivet:SetRotation(math.pi / 4)
        rivet:SetBlendMode("ADD")
    end
    local pulse = prompt:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetTarget(aura)
    alpha:SetOrder(1)
    alpha:SetFromAlpha(0.46)
    alpha:SetToAlpha(1)
    alpha:SetDuration(1.45)
    alpha:SetSmoothing("IN_OUT")
    local glowAlpha = pulse:CreateAnimation("Alpha")
    glowAlpha:SetTarget(smokeGlow)
    glowAlpha:SetOrder(1)
    glowAlpha:SetFromAlpha(0.18)
    glowAlpha:SetToAlpha(0.65)
    glowAlpha:SetDuration(1.45)
    glowAlpha:SetSmoothing("IN_OUT")
    prompt:SetScript("OnShow", function() pulse:Play() end)
    prompt:SetScript("OnHide", function() pulse:Stop() end)
    for _, event in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        prompt:RegisterEvent(event)
    end
    prompt:SetScript("OnEvent", function() W:RefreshPrompt() end)
    self:RefreshPrompt()
end

function W:Initialize()
    if self.hud then return end
    local theme = F.Theme
    local hud = CreateFrame("Frame", nil, UIParent)
    self.hud = hud
    hud:SetSize(292, 24)
    hud:SetFrameStrata("MEDIUM")
    hud:SetPoint("BOTTOM", F.UI.hud, "TOP", 0, 4)
    hud:SetClampedToScreen(true)
    theme:Panel(hud)
    hud.text = hud:CreateFontString(nil, "OVERLAY")
    hud.text:SetFont(theme.font, 11, "")
    hud.text:SetPoint("CENTER")
    hud.text:SetTextColor(0.90, 0.94, 0.93)

    hud:RegisterEvent("PLAYER_ENTERING_WORLD")
    hud:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    hud:RegisterEvent("BAG_UPDATE_DELAYED")
    hud:SetScript("OnEvent", function(_, event, slot)
        if event == "PLAYER_EQUIPMENT_CHANGED" and slot ~= MAIN_HAND then return end
        if event ~= "BAG_UPDATE_DELAYED" then self.lureSeconds = nil end
        self:RefreshOptions()
    end)
    self:RefreshOptions()
end
