local _, F = ...
local K = {}
F.OneKey = K

local KEY, BUTTON = "F", "RicoFishingCastButton"
local fishingSpells = {131474, 18248, 7732, 7731, 7620}
local channelSpells = {[131476] = true}
for _, id in ipairs(fishingSpells) do channelSpells[id] = true end

local function Locked()
    return InCombatLockdown and InCombatLockdown()
end

local function EquippedPole()
    local ok, item = F.Call(GetInventoryItemID, "player", INVSLOT_MAINHAND or 16)
    if not ok or not F.Number(item) then return false end
    local getter = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local read, _, _, _, _, _, classID, subclassID = F.Call(getter, item)
    return read and F.Number(classID) and F.Number(subclassID) and classID == 2 and subclassID == 20
end

local function SpellName(id)
    local ok, name = F.Call(C_Spell and C_Spell.GetSpellName, id)
    if ok and F.PublicString(name) and name ~= "" then return name end
end

local function FindFishing()
    local known = C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell or IsSpellKnown
    for _, id in ipairs(fishingSpells) do
        local ok, learned = F.Call(known, id)
        if ok and not F.IsSecret(learned) and learned == true then return id end
    end

    -- Forever can put the rank-specific spell in the general spellbook.
    local name = SpellName(7620) or PROFESSIONS_FISHING
    local book = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if not F.PublicString(name) or not book or bank == nil then return end
    local ok, lines = F.Call(book.GetNumSpellBookSkillLines)
    if not ok or not F.Number(lines) then return end
    for line = 1, lines do
        local read, info = F.Call(book.GetSpellBookSkillLineInfo, line)
        if read and type(info) == "table" and F.Number(info.itemIndexOffset) and F.Number(info.numSpellBookItems) then
            for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local gotItem, item = F.Call(book.GetSpellBookItemInfo, index, bank)
                if gotItem and type(item) == "table" and F.Number(item.spellID) and SpellName(item.spellID) == name then
                    return item.spellID
                end
            end
        end
    end
end

local function CVar(name)
    local ok, value = F.Call(C_CVar and C_CVar.GetCVar or GetCVar, name)
    if ok and F.PublicString(value) then return value end
end

local function Set(name, value)
    return F.Call(C_CVar and C_CVar.SetCVar or SetCVar, name, value)
end

function K:AssistInteraction()
    for _, setting in ipairs({{"SoftTargetInteract", "3"}, {"SoftTargetInteractGameObject", "1"}, {"SoftTargetInteractRange", "50"}}) do
        local name, desired = setting[1], setting[2]
        local current = CVar(name)
        local longerRange = name == "SoftTargetInteractRange" and (tonumber(current) or 0) >= 50
        if current and current ~= desired and not longerRange and not self.cvars[name] and Set(name, desired) then
            local actual = CVar(name)
            if actual and actual ~= current then self.cvars[name] = {before = current, applied = actual} end
        end
    end
end

function K:RestoreInteraction()
    for name, state in pairs(self.cvars) do
        local current = CVar(name)
        if current and (current ~= state.applied or (Set(name, state.before) and CVar(name) == state.before)) then
            self.cvars[name] = nil
        end
    end
end

function K:IsFishingSpell(id)
    if not F.Number(id) then return false end
    if id == self.spell or channelSpells[id] then return true end
    local name = self.spellName
    return name ~= nil and SpellName(id) == name
end

function K:IsChanneling()
    local ok, name, _, _, _, _, _, _, id = F.Call(UnitChannelInfo, "player")
    return ok and (self:IsFishingSpell(id) or (self.spellName and F.PublicString(name) and name == self.spellName))
end

function K:MakeBinding()
    if self.owner then return true end
    if not (SetOverrideBindingClick and SetOverrideBinding and ClearOverrideBindings and RegisterStateDriver) then return false end
    local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", function(self, _, down)
        if Locked() then return end
        if down then K.pressed = true; return end
        -- A release from the previous Interact binding must not cast a new line.
        self:SetAttribute("type", K.pressed and K.mode == "cast" and "spell" or nil)
        K.pressed = nil
    end)
    local owner = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    owner:SetAttribute("_onstate-ricofishingcombat", [[
        if newstate == "combat" then self:ClearBindings() end
    ]])
    RegisterStateDriver(owner, "ricofishingcombat", "[combat] combat; idle")
    self.button, self.owner = button, owner
    return true
end

function K:Disarm()
    local hadMode = self.mode ~= nil
    self.mode, self.pressed, self.channelGUID = nil, nil, nil
    if self.owner and not Locked() then ClearOverrideBindings(self.owner) end
    self:RestoreInteraction()
    if hadMode then F:QueueRefresh() end
end

function K:Update(channeling)
    self.setting = F.db.oneKey
    if Locked() or not F.db.oneKey or not EquippedPole() then self:Disarm(); return end
    if not self.spell then
        self.spell = FindFishing()
        self.spellName = self.spell and SpellName(self.spell)
    end
    if not self.spell or not self:MakeBinding() then self:Disarm(); return end
    if channeling == nil then channeling = self:IsChanneling() end
    local mode = channeling and "reel" or "cast"
    if not channeling and self.boundSpell ~= self.spell then
        self.button:SetAttribute("spell", self.spell)
        self.boundSpell = self.spell
    end
    if self.mode == mode then return end
    self.mode, self.pressed = mode, nil
    ClearOverrideBindings(self.owner)
    if channeling then
        self:AssistInteraction()
        SetOverrideBinding(self.owner, true, KEY, "INTERACTTARGET")
    else
        self:RestoreInteraction()
        SetOverrideBindingClick(self.owner, true, KEY, BUTTON, "LeftButton")
    end
    F:QueueRefresh()
end

function K:Loot(window, autoLoot)
    if not window or window.requested or not self.mode or Locked() or F.IsSecret(autoLoot) or autoLoot == true then return end
    local read, count = F.Call(GetNumLootItems)
    if not read or not F.Number(count) or count < 1 or count > 100 then return end
    window.requested = true
    for slot = count, 1, -1 do
        if F.lootWindow ~= window then break end
        local entry = window.slots[slot]
        if not entry or not entry.received then
            local ok, _, name, _, _, _, locked = F.Call(GetLootSlotInfo, slot)
            if ok and F.PublicString(name) and name ~= "" and not F.IsSecret(locked) and not locked then
                F.Call(LootSlot, slot)
            end
        end
    end
end

function K:GetStatus()
    if not F.db.oneKey then return "F fishing is off." end
    if self.mode == "reel" then return "Press F when the bobber splashes." end
    if self.mode == "cast" then return "Press F to cast." end
    return "Equip a fishing pole and learn Fishing to use F."
end

function K:Initialize()
    self.cvars = {}
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "SPELLS_CHANGED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, unit, guid, spell)
        if event == "PLAYER_LOGOUT" or event == "PLAYER_REGEN_DISABLED" then K:Disarm()
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            if unit == "player" and (K:IsFishingSpell(spell) or K:IsChanneling()) then
                K.channelGUID = F.PublicString(guid) and guid or nil
                K:Update(true)
            end
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if unit == "player" and K.mode == "reel"
                and (not K.channelGUID or not F.PublicString(guid) or K.channelGUID == guid) then
                K.channelGUID = nil
                K:Update(false)
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" and unit ~= (INVSLOT_MAINHAND or 16) then return
        elseif event == "SPELLS_CHANGED" then K.spell = nil; K:Update()
        else K:Update() end
    end)
    K:Update()
end
