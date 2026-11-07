-- Badge help and interrupt feedback. Secret game values go only to native
-- display sinks; unknown readiness never becomes an interrupt recommendation.
local _, RP = ...
local F = { active = setmetatable({}, {__mode = "k"}) }
RP.Features = F
local WHITE = "Interface\\Buttons\\WHITE8X8"
local unpack = unpack or table.unpack
local INTERRUPTS = {
    ROGUE = {{1769}, {1768}, {1767}, {1766}},
    WARRIOR = {{6554}, {6552}, {1672}, {1671}, {72}}, MAGE = {{2139}},
    SHAMAN = {{57994}, {8042}, {8044}, {8045}, {8046}, {10412}, {10413}, {10414}, {25454}},
    DRUID = {{106839}, {16979}}, HUNTER = {{147362}, {187707}, {34490}},
    PALADIN = {{96231}}, PRIEST = {{15487}}, WARLOCK = {{19244, true}, {19647, true}, {119910}},
    DEATHKNIGHT = {{47528}}, MONK = {{116705}}, DEMONHUNTER = {{183752}}, EVOKER = {{351338}},
}
local CLASS_NAMES = {WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue",
    PRIEST="Priest", DEATHKNIGHT="Death knight", SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock",
    MONK="Monk", DRUID="Druid", DEMONHUNTER="Demon hunter", EVOKER="Evoker"}
local RANKS = {
    elite = {"Elite", "A stronger elite creature. The gold crown and frame mark its rank."},
    rareelite = {"Rare elite", "A rare elite creature. Gold trim and a blue crown jewel distinguish it."},
    worldboss = {"Boss", "A boss-rank creature, marked by a gold crown and red jewel."},
    rare = {"Rare", "A rare creature, marked with silver trim and a blue gem."},
    normal = {"Standard unit", "The green crest is the standard portrait decoration."},
}

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
local function Number(value)
    return RP.Readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function PublicTable(value)
    return RP.Readable(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end
local function True(value)
    return RP.Readable(value) and (value == true or value == 1)
end

function F:HideBadgeTooltip(owner)
    if self.tooltip and (not owner or self.tooltip:IsOwned(owner)) then self.tooltip:Hide() end
end

function F:ShowBadgeTooltip(owner, title, detail, entry)
    if not self.tooltip then
        self.tooltip = CreateFrame("GameTooltip", "RicoPlatesBadgeTooltip", UIParent, "GameTooltipTemplate")
        self.tooltip:SetFrameStrata("TOOLTIP")
        self.tooltip:SetClampedToScreen(true)
        self.tooltip:EnableMouse(false)
        RP.Theme:Panel(self.tooltip):SetVertexColor(0.014, 0.022, 0.018, 1)
    end
    if RP.UnitFrames then RP.UnitFrames:HideUnitTooltip() end
    local tooltip = self.tooltip
    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    tooltip:SetText(title, 0.94, 0.88, 0.65)
    tooltip:AddLine(detail, 0.78, 0.85, 0.81, true)
    if entry then
        tooltip:ClearAllPoints()
        tooltip:SetPoint("TOPLEFT", entry.button, "BOTTOMLEFT", 0, -12)
    end
    tooltip:Show()
end

function F:AttachBadges(entry)
    local p = entry.plate
    self:AttachIcon(p.classIcon, "class", entry)
    self:AttachIcon(p.factionIcon, "faction", entry)
    if entry.bezel and entry.bezel.help then return end
    if not entry.bezel then return end
    local help = CreateFrame("Frame", nil, entry.portraitFront)
    help:SetSize(28, 19)
    help:SetPoint("BOTTOM", entry.portraitFront, "TOP", 0, -2)
    help:SetFrameLevel(entry.portraitFront:GetFrameLevel() + 4)
    help:EnableMouse(true)
    if help.SetMouseClickEnabled then help:SetMouseClickEnabled(false) end
    if help.SetMouseMotionEnabled then help:SetMouseMotionEnabled(true) end
    help:SetScript("OnEnter", function(self)
        local info = RANKS[entry.classification or "normal"] or RANKS.normal
        F:ShowBadgeTooltip(self, info[1], info[2], entry)
    end)
    help:SetScript("OnLeave", function(self) F:HideBadgeTooltip(self) end)
    help:SetScript("OnHide", function(self) F:HideBadgeTooltip(self) end)
    entry.bezel.help = help
end

function F:AttachIcon(icon, kind, entry)
    if icon.ricoHelp then icon.ricoHelp.entry = entry or icon.ricoHelp.entry; return end
    icon.ricoHelp = {entry = entry}
    icon:EnableMouse(true)
    if icon.SetMouseClickEnabled then icon:SetMouseClickEnabled(false) end
    if icon.SetMouseMotionEnabled then icon:SetMouseMotionEnabled(true) end
    icon:SetScript("OnEnter", function(self)
        local title, detail
        if kind == "class" then
            local token = self.classToken
            if not token then return end
            title = CLASS_NAMES[token] or token:gsub("_", " ")
            detail = "Character class. The framed symbol identifies this player's class."
        else
            title = self.factionToken
            if not title then return end
            detail = "Character faction: " .. title .. "."
        end
        F:ShowBadgeTooltip(self, title, detail, self.ricoHelp.entry)
    end)
    icon:SetScript("OnLeave", function(self) F:HideBadgeTooltip(self) end)
    icon:SetScript("OnHide", function(self) F:HideBadgeTooltip(self) end)
end

function F:GetInterrupts()
    if self.spells then return self.spells end
    local _, class = UnitClass("player")
    local found = {}
    if RP.Readable(class) and type(class) == "string" then
        for _, entry in ipairs(INTERRUPTS[class] or {}) do
            local id, pet = entry[1], entry[2]
            local known, value
            if C_SpellBook and C_SpellBook.IsSpellKnown then
                local bank = Enum and Enum.SpellBookSpellBank
                known, value = Call(C_SpellBook.IsSpellKnown, id, pet and (bank and bank.Pet or 1) or (bank and bank.Player or 0))
            else known, value = Call(IsSpellKnown, id, pet and true or false) end
            if not known and not pet then known, value = Call(IsPlayerSpell, id) end
            if known and True(value) then found[#found + 1] = id end
        end
    end
    self.spells = found
    return found
end

local function CooldownReady(id)
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, info = Call(C_Spell.GetSpellCharges, id)
        if ok and PublicTable(info) and Number(info.currentCharges) then return info.currentCharges > 0 end
    end
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = Call(C_Spell.GetSpellCooldown, id)
        if not ok or not PublicTable(info) then return false end
        if RP.Readable(info.isEnabled) and info.isEnabled == false then return false end
        if RP.Readable(info.isActive) and type(info.isActive) == "boolean" then return not info.isActive end
        if Number(info.startTime) and Number(info.duration) then
            return info.startTime == 0 or info.duration == 0 or info.startTime + info.duration <= GetTime()
        end
        return false
    end
    local ok, start, duration, enabled = Call(GetSpellCooldown, id)
    return ok and Number(start) and Number(duration) and RP.Readable(enabled) and enabled ~= 0
        and (start == 0 or duration == 0 or start + duration <= GetTime())
end

function F:ReadyInterrupt(unit)
    local ok, attackable = Call(UnitCanAttack, "player", unit)
    if not ok or not True(attackable) then return nil end
    for _, id in ipairs(self:GetInterrupts()) do
        if CooldownReady(id) then
            local usableAPI = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
            local usable, value = Call(usableAPI, id)
            if usable and True(value) then
                local rangeAPI = C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
                local range, inRange = Call(rangeAPI, id, unit)
                if range and True(inRange) then return id end
            end
        end
    end
end

function F:BuildPlate(p)
    self:Initialize()
    self:AttachIcon(p.classIcon, "class")
    self:AttachIcon(p.factionIcon, "faction")
    local ui = CreateFrame("Frame", nil, p.cast)
    ui:SetAllPoints(p.cast)
    ui:SetFrameLevel(p.cast:GetFrameLevel() + 3)
    ui:EnableMouse(false)
    p.interrupt = {frame = ui, edges = {}}
    local function Edge(a, b, horizontal)
        local tex = ui:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(WHITE)
        tex:SetPoint(a, p.cast, a, 0, 0); tex:SetPoint(b, p.cast, b, 0, 0)
        if horizontal then tex:SetHeight(2) else tex:SetWidth(2) end
        tex:SetVertexColor(0.40, 0.95, 0.65, 0.75)
        p.interrupt.edges[#p.interrupt.edges + 1] = tex
    end
    Edge("TOPLEFT", "TOPRIGHT", true); Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false); Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    ui:Hide()
    local shield = CreateFrame("Frame", nil, p.cast)
    shield:SetSize(12, 13)
    shield:SetPoint("LEFT", p.cast, "RIGHT", 4, 0)
    shield:EnableMouse(false)
    for i = 1, 5 do
        local t = shield:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE)
        t:SetPoint("TOP", shield, "TOP", 0, -(i - 1) * 2)
        t:SetSize(i < 3 and 10 or (12 - i * 2), 2)
        t:SetVertexColor(0.67, 0.73, 0.79, 1)
    end
    p.interrupt.shield = shield
    shield:Hide()
end

function F:CastHidden(p)
    self.active[p] = nil
    p.ricoInterruptLocked = nil
    if p.interrupt then p.interrupt.frame:Hide(); p.interrupt.shield:Hide(); p.interrupt.spellID = nil end
    if self.worker and not next(self.active) then self.worker:Hide() end
end

function F:UpdateReady(p)
    local ui = p.interrupt
    if not ui then return end
    ui.frame:Hide(); ui.shield:Hide(); ui.spellID = nil
    if not p.castVisible or (RP.db and RP.db.interruptIndicators == false) then return end
    local locked = p.ricoInterruptLocked
    if ui.shield.SetAlphaFromBoolean then
        local ok = pcall(ui.shield.SetAlphaFromBoolean, ui.shield, locked, 1, 0)
        if ok then ui.shield:Show() end
    elseif RP.PublicTrue(locked) then ui.shield:SetAlpha(1); ui.shield:Show() end
    -- An unreadable interruptibility flag is displayed by the shield's native
    -- boolean sink, but is never treated as an actionable unlocked cast.
    if RP.IsSecret(locked) or RP.PublicTrue(locked) or locked == nil then return end
    local id = self:ReadyInterrupt(p.unit)
    if id then
        ui.spellID = id
        ui.frame:SetAlpha(0.58 + 0.16 * math.sin(GetTime() * 5))
        ui.frame:Show()
    end
end

function F:UpdateCast(p, locked)
    if not p.interrupt then self:BuildPlate(p) end
    p.ricoInterruptLocked = locked
    self.active[p] = true
    self:UpdateReady(p)
    self.worker:Show()
end

function F:Initialize()
    if self.worker then return end
    local worker = CreateFrame("Frame")
    self.worker = worker
    worker:Hide()
    worker:SetScript("OnUpdate", function(_, elapsed)
        F.elapsed = (F.elapsed or 0) + elapsed
        if F.elapsed < 0.15 then return end
        F.elapsed = 0
        for p in pairs(F.active) do
            if p.castVisible and p:IsVisible() then F:UpdateReady(p) else F:CastHidden(p) end
        end
    end)
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({"SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB",
        "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "UPDATE_SHAPESHIFT_FORM", "UNIT_PET", "PLAYER_ENTERING_WORLD"}) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event ~= "SPELL_UPDATE_COOLDOWN" and event ~= "SPELL_UPDATE_USABLE" then F.spells = nil end
        for p in pairs(F.active) do F:UpdateReady(p) end
    end)
end
