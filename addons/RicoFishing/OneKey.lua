local _, F = ...
local K = {}
F.OneKey = K

local DEFAULT_KEY, BUTTON = "F", "RicoFishingCastButton"
local CAST_ACTION = "CLICK " .. BUTTON .. ":LeftButton"
local MODIFIERS = { "ALT", "CTRL", "SHIFT", "META" }
local modifierKeys = {}
for _, name in ipairs(MODIFIERS) do
    modifierKeys[name], modifierKeys["L" .. name], modifierKeys["R" .. name] = true, true, true
end
local fishingSpells = {131474, 18248, 7732, 7731, 7620}
local channelSpells = {[131476] = true}
for _, id in ipairs(fishingSpells) do channelSpells[id] = true end

local function Locked()
    return InCombatLockdown and InCombatLockdown()
end

local function SplitKey(binding)
    local key, found = binding, {}
    while true do
        local prefix, rest = key:match("^(%a+)%-(.+)$")
        if not prefix or (prefix ~= "ALT" and prefix ~= "CTRL" and prefix ~= "SHIFT" and prefix ~= "META") then break end
        found[prefix], key = true, rest
    end
    local modifiers = {}
    for _, name in ipairs(MODIFIERS) do
        if found[name] then modifiers[#modifiers + 1] = name end
    end
    return key, modifiers
end

function K:NormalizeKey(binding)
    if not F.PublicString(binding) or #binding > 64 or binding:find("[%s%c]") then return nil end
    if binding == "" then return "" end
    local key, modifiers = SplitKey(binding:upper())
    if key == "ESCAPE" or key == "UNKNOWN" or key == "BUTTON1" or key == "BUTTON2"
        or modifierKeys[key] or modifierKeys[key:match("^(%a+)%-$")] then return nil end
    local checked, ignored = F.Call(IsKeyPressIgnoredForBinding, key)
    if checked and not F.IsSecret(ignored) and ignored == true then return nil end
    if #modifiers == 0 then return key end
    return table.concat(modifiers, "-") .. "-" .. key
end

function K:GetKey()
    local key = F.db and F.db.fishingKey
    return F.PublicString(key) and key or DEFAULT_KEY
end

function K:GetKeyParts(binding)
    return SplitKey(F.PublicString(binding) and binding or self:GetKey())
end

function K:GetKeyLabel(binding)
    local key = F.PublicString(binding) and binding or self:GetKey()
    if key == "" then return "Unbound" end
    local ok, label = F.Call(GetBindingText, key)
    return ok and F.PublicString(label) and label ~= "" and label or key
end

function K:CaptureKey(input)
    if not F.PublicString(input) or input == "" then return nil end
    local converted, key = F.Call(GetConvertedKeyOrButton, input)
    if not converted or not F.PublicString(key) then
        local button = input:match("^Button(%d+)$")
        key = input == "MiddleButton" and "BUTTON3" or button and "BUTTON" .. button or input
    end
    key = key:upper()
    if key == "ESCAPE" or key == "UNKNOWN" or modifierKeys[key] then return nil end
    local made, chord = F.Call(CreateKeyChordStringUsingMetaKeyState, key)
    if made and F.PublicString(chord) and chord ~= "" then return self:NormalizeKey(chord) end
    local alt = IsAltKeyDown and IsAltKeyDown() and "ALT-" or ""
    local control = IsControlKeyDown and IsControlKeyDown() and "CTRL-" or ""
    local shift = IsShiftKeyDown and IsShiftKeyDown() and "SHIFT-" or ""
    local meta = IsMetaKeyDown and IsMetaKeyDown() and "META-" or ""
    return self:NormalizeKey(alt .. control .. shift .. meta .. key)
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
        if K.scrollKey then
            -- A wheel tick has no physical release. Only its down edge casts.
            self:SetAttribute("type", down and K.mode == "cast" and "spell" or nil)
            return
        end
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

local function Bind(owner, key, mode)
    local ok, result
    local expected
    if mode == "reel" then
        expected = "INTERACTTARGET"
        ok, result = F.Call(SetOverrideBinding, owner, true, key, expected)
    else
        expected = CAST_ACTION
        ok, result = F.Call(SetOverrideBindingClick, owner, true, key, BUTTON, "LeftButton")
    end
    if not ok or result == false then return false end
    local read, action = F.Call(GetBindingAction, key, true)
    return not read or not F.PublicString(action) or action == expected
end

function K:CanBind(key)
    if key == "" then return true end
    if Locked() or not self:MakeBinding() then return false end
    if not self.testOwner then self.testOwner = CreateFrame("Frame") end
    local accepted = Bind(self.testOwner, key, "cast")
    ClearOverrideBindings(self.testOwner)
    return accepted
end

function K:Disarm()
    local hadMode = self.mode ~= nil
    self.mode, self.pressed, self.channelGUID, self.boundKey, self.scrollKey = nil, nil, nil, nil, nil
    if self.owner and not Locked() then ClearOverrideBindings(self.owner) end
    self:RestoreInteraction()
    if hadMode then F:QueueRefresh() end
end

function K:Update(channeling)
    local key = self:GetKey()
    self.setting, self.keySetting = F.db.oneKey, key
    if Locked() or not F.db.oneKey or key == "" or not EquippedPole() then self:Disarm(); return end
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
    if self.mode == mode and self.boundKey == key then return true end
    local base = self:GetKeyParts(key)
    local scrollKey = base == "MOUSEWHEELUP" or base == "MOUSEWHEELDOWN"
    if not channeling then self.button:SetAttribute("useOnKeyDown", scrollKey) end
    ClearOverrideBindings(self.owner)
    self.pressed = nil
    if not Bind(self.owner, key, mode) then
        self:Disarm()
        return false
    end
    self.mode, self.boundKey, self.scrollKey = mode, key, scrollKey
    if channeling then
        self:AssistInteraction()
    else
        self:RestoreInteraction()
    end
    F:QueueRefresh()
    return true
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
    if not F.db.oneKey then return "One-key fishing is off." end
    if self:GetKey() == "" then return "Choose a key in Fishing tools." end
    local label = self:GetKeyLabel()
    if self.mode == "reel" then
        if F.BiteDetector and F.BiteDetector:IsBite() == true then return ("Fish on the line! Press %s to reel in."):format(label) end
        return ("Press %s when the bobber splashes."):format(label)
    end
    if self.mode == "cast" then return ("Press %s to cast."):format(label) end
    return "Learn Fishing and equip a fishing pole."
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
