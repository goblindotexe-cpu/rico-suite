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
    if not F.db.bagWarning then return end
    local free = GeneralBagSlots()
    if free == nil then return end
    if free > LOW_BAGS then
        self.bagNotice = nil
    elseif self.pole then
        local severity = free == 0 and 2 or 1
        if severity > (self.bagNotice or 0) then
            self.bagNotice = severity
            local message = free == 0 and "Bags full" or ("Bag space low: %d free"):format(free)
            F:Print((severity == 2 and RED or AMBER) .. message .. "|r")
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

    local lureText = not mode and self.baitText or nil
    if lureText and (self.baitState == "low" or self.baitState == "missing") then
        lureText = AMBER .. lureText .. "|r"
    end
    local lureHud = self.lureHud
    if lureHud then
        if lureText ~= self.label then lureHud.text:SetText(lureText or "") end
        self.label = lureText
        lureHud:SetShown(lureText ~= nil)
    end

    -- The catch strip has no countdown and never owns an OnUpdate handler.
    local visible = mode and prompt or lureText and lureHud
    local driver = self.pole and F.db.lureTimer and visible or nil
    if driver ~= self.driver then
        if self.driver then self.driver:SetScript("OnUpdate", nil) end
        self.driver, self.elapsed = driver, 0
        if driver then driver:SetScript("OnUpdate", Tick) end
    end
end

function W:RefreshOptions()
    if not self.lureHud then return end
    self.pole = EquippedPole()
    self:UpdateBags()
    self:UpdateLure()
    self:RefreshRecentCatches()
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

local function AddSmoke(parent, anchor, file, width, height, x, y, opacity)
    local path = "Interface\\AddOns\\" .. F.name .. "\\Media\\" .. file
    local smoke = parent:CreateTexture(nil, "BACKGROUND", nil, -2)
    smoke:SetTexture(path)
    smoke:SetPoint("CENTER", anchor, "CENTER", x, y)
    smoke:SetSize(width, height)
    smoke:SetVertexColor(0.54, 0.70, 0.62, opacity)
    local glow = parent:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetTexture(path)
    glow:SetAllPoints(smoke)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.31, 1, 0.62)
    return glow
end

local function PulseAlpha(group, target, low, high, duration, order)
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetTarget(target)
    alpha:SetOrder(order or 1)
    alpha:SetFromAlpha(low)
    alpha:SetToAlpha(high)
    alpha:SetDuration(duration)
    alpha:SetSmoothing("IN_OUT")
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

    local smokeGlow = AddSmoke(prompt, key, "PromptSmoke.tga", 156, 156, 4, 0, 0.40)

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
    PulseAlpha(pulse, aura, 0.46, 1, 1.45)
    PulseAlpha(pulse, smokeGlow, 0.18, 0.65, 1.45)
    prompt:SetScript("OnShow", function() pulse:Play() end)
    prompt:SetScript("OnHide", function() pulse:Stop() end)
    for _, event in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        prompt:RegisterEvent(event)
    end
    prompt:SetScript("OnEvent", function() W:RefreshPrompt() end)
    self:RefreshPrompt()
end

local RECENT_SLOTS = 10
local SLOT_SIZE, SLOT_GAP = 30, 5
local SLOT_EDGE = { 0.19, 0.28, 0.23, 1 }
local LATEST_EDGE = { 0.23, 0.66, 0.47, 1 }

local function HideCatchTooltip(slot)
    if GameTooltip and GameTooltip:IsOwned(slot) then GameTooltip:Hide() end
end

local function ShowCatchTooltip(slot)
    local tooltip = GameTooltip
    if not tooltip or not slot.itemID then return end
    tooltip:SetOwner(slot, "ANCHOR_TOP")
    local shown = slot.itemLink and F.Call(tooltip.SetHyperlink, tooltip, slot.itemLink)
    if not shown then
        local ok = F.Call(tooltip.SetItemByID, tooltip, slot.itemID)
        if not ok then F.Call(tooltip.SetHyperlink, tooltip, "item:" .. slot.itemID) end
    end
    tooltip:Show()
end

local function CatchName(hud, catch)
    if not catch then return "No catches yet" end
    local getter = C_Item and C_Item.GetItemNameByID or GetItemInfo
    local ok, name = F.Call(getter, catch.id)
    if not ok or not F.PublicString(name) or name == "" then
        local entry = F:GetEntry(catch.id)
        name = catch.link and catch.link:match("%[([^%]]+)%]") or entry and entry.name
    end
    if not name then
        if hud.requestedID ~= catch.id then
            hud.requestedID = catch.id
            F.Call(C_Item and C_Item.RequestLoadItemDataByID, catch.id)
        end
        name = "Item #" .. catch.id
    end
    return catch.count > 1 and (name .. " ×" .. catch.count) or name
end

local function ClearCatchSpark(hud)
    hud.sparkRow, hud.sparkSlot = nil, nil
    hud.spark:Hide()
end

local function PositionCatchSpark(hud, slot)
    if hud.sparkSlot == slot then return end
    hud.sparkSlot = slot
    hud.spark:ClearAllPoints()
    hud.spark:SetPoint("CENTER", slot, "CENTER")
end

function W:RefreshRecentCatches()
    local hud = self.hud
    if not hud then return end
    local log = F.SessionLog
    local catches = log and log:GetRecentCatches()
    local newest = catches and catches[1]
    local previous = hud.newestCatch
    local newRows = hud.catchListReady and newest ~= previous
    hud.catchListReady, hud.newestCatch = true, newest
    local shown = self.pole ~= nil and F.db.recentCatches == true
    hud:SetShown(shown)
    local anchor = shown and hud or F.UI.hud
    if self.lureAnchor ~= anchor then
        self.lureAnchor = anchor
        self.lureHud:ClearAllPoints()
        self.lureHud:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
    end
    if not shown then return end

    local name = CatchName(hud, newest)
    if hud.catchName ~= name then
        hud.catchName = name
        hud.name:SetText(name)
    end
    local wanted = log and log:GetWantedCatch()
    local startSlot, activeSlot
    for index, slot in ipairs(hud.slots) do
        local catch = catches and catches[index]
        if catch == previous then newRows = false end
        local id, link = catch and catch.id, catch and catch.link
        if catch and newRows and id == wanted and not startSlot then
            startSlot, hud.sparkRow = slot, catch
        end
        if catch and catch == hud.sparkRow then activeSlot = slot end
        local changed = slot.itemID ~= id or slot.itemLink ~= link
        if (slot.itemID ~= nil) ~= (id ~= nil) then
            slot.icon:SetShown(id ~= nil)
            slot:EnableMouse(id ~= nil)
            if index == 1 then slot.edge:SetColorTexture(unpack(id and LATEST_EDGE or SLOT_EDGE)) end
        end
        slot.itemID, slot.itemLink = id, link
        if catch then
            local texture = F:GetIcon(id)
            if slot.texture ~= texture then
                slot.texture = texture
                slot.icon:SetTexture(texture)
            end
        end
        local count = catch and catch.count
        if slot.quantity ~= count then
            slot.quantity = count
            slot.count:SetText(count and count > 1 and tostring(count) or "")
        end
        if changed and GameTooltip and GameTooltip:IsOwned(slot) then
            if id then ShowCatchTooltip(slot) else HideCatchTooltip(slot) end
        end
    end
    if startSlot then
        hud.sparkPulse:Stop()
        PositionCatchSpark(hud, startSlot)
        hud.spark:Show()
        hud.sparkPulse:Play()
    elseif activeSlot then
        PositionCatchSpark(hud, activeSlot)
    elseif hud.sparkRow then
        hud.sparkPulse:Stop()
        ClearCatchSpark(hud)
    end
end

local function CatchPixelSize(hud, size)
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        return PixelUtil.GetNearestPixelSize(size, hud:GetEffectiveScale(), 1)
    end
    return size
end

local function LayoutCatchSlots(hud)
    local size, gap = CatchPixelSize(hud, SLOT_SIZE), CatchPixelSize(hud, SLOT_GAP)
    local edge, inset = CatchPixelSize(hud, 1), CatchPixelSize(hud, 2)
    local rowWidth = RECENT_SLOTS * size + (RECENT_SLOTS - 1) * gap
    local start = CatchPixelSize(hud, (hud:GetWidth() - rowWidth) / 2)
    local bottom = CatchPixelSize(hud, 8)
    for index, slot in ipairs(hud.slots) do
        slot:SetSize(size, size)
        slot:ClearAllPoints()
        slot:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", start + (index - 1) * (size + gap), bottom)
        slot.fill:ClearAllPoints()
        slot.fill:SetPoint("TOPLEFT", slot, "TOPLEFT", edge, -edge)
        slot.fill:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -edge, edge)
        slot.icon:SetSize(size - 2 * inset, size - 2 * inset)
    end
end

function W:CreateRecentCatches()
    local hud = CreateFrame("Frame", nil, UIParent)
    self.hud = hud
    hud:Hide()
    hud:SetSize(370, 63)
    hud:SetPoint("BOTTOM", F.UI.hud, "TOP", 0, 4)
    hud:SetFrameStrata("MEDIUM")
    hud:SetClampedToScreen(true)
    Metal(hud, 2, 2, 366, 59, 7)
    local glow = AddSmoke(hud, hud, "CatchStripSmoke.tga", 556, 148, 0, 0, 0.36)

    local heading = PromptText(hud, 11, MINT)
    heading:SetPoint("TOPLEFT", 16, -9)
    heading:SetText("Latest catch")
    hud.name = PromptText(hud, 12, { 0.93, 0.98, 0.95 })
    hud.name:SetPoint("LEFT", heading, "RIGHT", 10, 0)
    hud.name:SetWidth(260)
    hud.name:SetJustifyH("LEFT")
    hud.name:SetWordWrap(false)

    hud.slots = {}
    for index = 1, RECENT_SLOTS do
        local slot = CreateFrame("Frame", nil, hud)
        hud.slots[index] = slot
        slot:EnableMouse(false)
        slot.edge = slot:CreateTexture(nil, "BACKGROUND")
        slot.edge:SetAllPoints(slot)
        slot.edge:SetColorTexture(unpack(SLOT_EDGE))
        slot.fill = slot:CreateTexture(nil, "BORDER")
        slot.fill:SetColorTexture(0.027, 0.045, 0.036, 1)
        slot.edge:SetSnapToPixelGrid(true)
        slot.fill:SetSnapToPixelGrid(true)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetPoint("CENTER")
        slot.icon:SetSnapToPixelGrid(true)
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        slot.icon:Hide()
        slot.count = PromptText(slot, 10, { 0.96, 1, 0.97 })
        slot.count:SetPoint("BOTTOMRIGHT", -2, 1)
        slot:SetScript("OnEnter", ShowCatchTooltip)
        slot:SetScript("OnLeave", HideCatchTooltip)
        slot:SetScript("OnHide", HideCatchTooltip)
    end
    LayoutCatchSlots(hud)
    hud:RegisterEvent("UI_SCALE_CHANGED")
    hud:RegisterEvent("DISPLAY_SIZE_CHANGED")
    hud:SetScript("OnEvent", LayoutCatchSlots)

    -- The strip is behind this flash and the slot frames are above it.
    hud.spark = hud:CreateTexture(nil, "OVERLAY", nil, -1)
    hud.spark:SetTexture("Interface\\AddOns\\" .. F.name .. "\\Media\\WantedCatchSpark.tga")
    hud.spark:SetSize(112, 112)
    hud.spark:SetBlendMode("ADD")
    hud.spark:SetVertexColor(1, 0.92, 0.70)
    hud.spark:Hide()
    hud.sparkPulse = hud:CreateAnimationGroup()
    PulseAlpha(hud.sparkPulse, hud.spark, 0.35, 1, 0.14)
    PulseAlpha(hud.sparkPulse, hud.spark, 1, 1, 0.62, 2)
    PulseAlpha(hud.sparkPulse, hud.spark, 1, 0, 0.94, 3)
    hud.sparkPulse:SetScript("OnFinished", function() ClearCatchSpark(hud) end)

    local pulse = hud:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    PulseAlpha(pulse, glow, 0.20, 0.60, 1.65)
    hud:SetScript("OnShow", function() pulse:Play() end)
    hud:SetScript("OnHide", function()
        pulse:Stop()
        hud.sparkPulse:Stop()
        ClearCatchSpark(hud)
        for _, slot in ipairs(hud.slots) do HideCatchTooltip(slot) end
    end)
end

function W:Initialize()
    if self.lureHud then return end
    self:CreateRecentCatches()
    local theme = F.Theme
    local hud = CreateFrame("Frame", nil, UIParent)
    self.lureHud = hud
    hud:Hide()
    hud:SetSize(292, 24)
    hud:SetFrameStrata("MEDIUM")
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
        if event == "BAG_UPDATE_DELAYED" then self:UpdateBags(); return end
        if event == "PLAYER_EQUIPMENT_CHANGED" and slot ~= MAIN_HAND then return end
        self.lureSeconds = nil
        self:RefreshOptions()
    end)
    self:RefreshOptions()
end
