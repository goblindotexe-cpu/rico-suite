local _, RP = ...
-- Exact Forever UI: Blizzard_UnitFrame/Mainline/{Player,Target,Pet}Frame.xml.
-- AuraContainer:IsEnabled/SetEnabled are public inbound methods. SetAlpha is
-- AllowedWhenTainted (SimpleRegionAPIDocumentation); mouse setters are protected.
local N = { states = {}, alphaOwners = {}, hooked = {} }
RP.NativeFrames = N
local units = {"player", "target", "pet"}
local globals = {player = "PlayerFrame", target = "TargetFrame", pet = "PetFrame"}

local function Public(value)
    return not RP.IsSecret(value)
end

local function Usable(object)
    if not Public(object) or object == nil then return false end
    local ok, forbidden = pcall(function() return object:IsForbidden() end)
    return ok and Public(forbidden) and forbidden == false
end

local function Field(object, key)
    if not Usable(object) then error("Native frame inaccessible", 0) end
    local ok, value = pcall(function() return object[key] end)
    if not ok or not Public(value) then error("Native field inaccessible: " .. key, 0) end
    return value
end

local function Required(object, label)
    if not Usable(object) then error("Native frame missing or inaccessible: " .. label, 0) end
    return object
end

local function Read(object, getter, valueType)
    if not Usable(object) then return false end
    local ok, value = pcall(function() return object[getter](object) end)
    if not ok or not Public(value) or type(value) ~= valueType then return false end
    if valueType == "number" and (value ~= value or value < 0 or value > 1) then return false end
    return true, value
end

local function Locked()
    if type(InCombatLockdown) ~= "function" then return true end
    local ok, combat = pcall(InCombatLockdown)
    return not ok or not Public(combat) or combat == true or combat == 1
end

local function Add(plan, object, getter, setter, value, label)
    Required(object, label)
    if type(Field(object, setter)) ~= "function" then error("Native function missing: " .. setter, 0) end
    local ok, current = Read(object, getter, type(value))
    if not ok then error("Native state not public: " .. label, 0) end
    for _, entry in ipairs(plan.entries) do
        if entry.object == object and entry.getter == getter then return end
    end
    plan.entries[#plan.entries + 1] = {
        object = object, getter = getter, setter = setter, value = value,
        before = current, label = label,
    }
end

local function Mouse(plan, object, label)
    Add(plan, object, "IsMouseClickEnabled", "SetMouseClickEnabled", false, label .. " clicks")
    Add(plan, object, "IsMouseMotionEnabled", "SetMouseMotionEnabled", false, label .. " mouse")
end

local function Preserve(plan, object, label)
    if not Public(object) then error("Native frame not public: " .. label, 0) end
    if object ~= nil then
        Add(plan, object, "IsIgnoringParentAlpha", "SetIgnoreParentAlpha", true, label)
    end
end

local function BuildClassResourcePlan(token)
    local player = Required(_G.PlayerFrame, "PlayerFrame")
    local bar = Field(player, "classPowerBar")
    local plan = { root = player, entries = {} }
    -- No native bar, or a different native class mechanism: leave it alone.
    if bar ~= nil then
        Required(bar, "Class resource")
        if Field(bar, "powerToken") == token then
            Mouse(plan, bar, "Class resource")
            Add(plan, bar, "GetAlpha", "SetAlpha", 0, "Class resource")
        end
    end
    -- Camelot additionally places its native combo circle on TargetFrame.
    -- If only our player HUD is enabled, that native target stays visible;
    -- suppress the known circle too while our player fallback owns combo.
    local combo = _G.ComboFrame
    if token == "COMBO_POINTS" and not Public(combo) then error("ComboFrame not public", 0) end
    if token == "COMBO_POINTS" and combo ~= nil then
        Required(combo, "ComboFrame")
        local ok, parent = pcall(function() return combo:GetParent() end)
        if not ok or not Public(parent) then error("ComboFrame parent inaccessible", 0) end
        if parent == Required(_G.TargetFrame, "TargetFrame") then
            Mouse(plan, combo, "ComboFrame")
            Add(plan, combo, "GetAlpha", "SetAlpha", 0, "ComboFrame")
            -- ComboFrame starts at alpha 0, then fades in when points appear.
            -- Restore that later public native alpha, not a stale initial 0.
            plan.entries[#plan.entries].followNativeAlpha = true
        end
    end
    return plan
end

local function BuildPlan(unit)
    if unit == "classResources" then return BuildClassResourcePlan(N.classResourceToken) end
    local root = Required(_G[globals[unit]], globals[unit])
    local plan = {root = root, entries = {}}
    Mouse(plan, root, globals[unit])
    if unit == "pet" then
        -- Pet visuals are direct children/regions, unlike the two other roots.
        Preserve(plan, _G.PetFrameHappiness, "PetFrameHappiness")
        local auras = Field(root, "AuraFrameContainer")
        if auras ~= nil then
            Add(plan, auras, "IsShown", "SetShown", false, "Pet auras")
        end
        local health, mana = _G.PetFrameHealthBar, _G.PetFrameManaBar
        if not Public(health) or not Public(mana) then error("Native pet bar not public", 0) end
        if health ~= nil then Mouse(plan, health, "Pet HP") end
        if mana ~= nil then Mouse(plan, mana, "Pet resource") end
        Add(plan, root, "GetAlpha", "SetAlpha", 0, "PetFrame")
        return plan
    end

    local prefix = unit == "player" and "PlayerFrame" or "TargetFrame"
    local content = Required(Field(root, prefix .. "Content"), prefix .. "Content")
    local main = Required(Field(content, prefix .. "ContentMain"), prefix .. "ContentMain")
    local context = Field(content, prefix .. "ContentContextual")
    local healthArea = Field(main, "HealthBarsContainer")
    if healthArea ~= nil then
        local health = Field(healthArea, "HealthBar")
        if health ~= nil then Mouse(plan, health, prefix .. " HP") end
    end

    if unit == "player" then
        -- Keep native secondary resources and playtime controls operational.
        -- Direct-root children are outside this plan. Class resources have a
        -- separate exact-token ownership plan after their replacement paints.
        Preserve(plan, Field(main, "AlternatePowerBarArea"), "Secondary player resource")
        if context ~= nil then Preserve(plan, Field(context, "PlayerPlayTime"), "Playtime notification") end
        local manaArea = Field(main, "ManaBarArea")
        if manaArea ~= nil then
            local mana = Field(manaArea, "ManaBar")
            if mana ~= nil then Mouse(plan, mana, "Player resource") end
        end
    else
        -- Keep these exact native children functional while the original target
        -- artwork and spellbar disappear. Never reparent the ToT or spellbar.
        Preserve(plan, Field(root, "totFrame"), "Target of target")
        Preserve(plan, Field(root, "powerBarAlt"), "Secondary target resource")
        local mana = Field(main, "ManaBar")
        if mana ~= nil then Mouse(plan, mana, "Target resource") end
        -- Public native facade: disable frame assignment, not private buttons.
        -- Native ConfigureAuraContainer never re-enables this flag.
        local auras = context and Field(context, "Auras")
        if auras ~= nil then Add(plan, auras, "IsEnabled", "SetEnabled", false, "Target auras") end
    end
    if unit == "player" then
        -- The player's castbar, pet and totems stay native. Class resources
        -- are handled separately, only after a matching replacement paints.
        local art = Required(Field(root, "PlayerFrameContainer"), "PlayerFrameContainer")
        Add(plan, art, "GetAlpha", "SetAlpha", 0, "PlayerFrame artwork")
        Add(plan, content, "GetAlpha", "SetAlpha", 0, "PlayerFrame content")
    else
        Add(plan, root, "GetAlpha", "SetAlpha", 0, "TargetFrame")
    end
    return plan
end

function N:HookAlpha(object)
    if self.hooked[object] then return true end
    if type(hooksecurefunc) ~= "function" then return false end
    local ok = pcall(hooksecurefunc, object, "SetAlpha", function(frame, alpha)
        if N.alphaOwners[frame] and not N.settingAlpha and Usable(frame) then
            local state = N.states[N.alphaOwners[frame]]
            if state and Public(alpha) and type(alpha) == "number" and alpha >= 0 and alpha <= 1 then
                for _, entry in ipairs(state.entries) do
                    if entry.followNativeAlpha and entry.object == frame then entry.before = alpha end
                end
            end
            -- SetAlpha is an AllowedWhenTainted native sink, not protected
            -- geometry. Only a public constant is applied, including combat.
            N.settingAlpha = true
            pcall(frame.SetAlpha, frame, 0)
            N.settingAlpha = false
        end
    end)
    if ok then self.hooked[object] = true end
    return ok
end

function N:Write(entry, value)
    if not Usable(entry.object) then return false end
    local previousGuard = self.settingAlpha
    if entry.setter == "SetAlpha" then self.settingAlpha = true end
    local ok = pcall(function() entry.object[entry.setter](entry.object, value) end)
    self.settingAlpha = previousGuard
    return ok
end

function N:ReleaseEntry(entry)
    if entry.setter == "SetAlpha" then self.alphaOwners[entry.object] = nil end
    local ok, current = Read(entry.object, entry.getter, type(entry.value))
    if not ok then return false end
    -- Do not overwrite a later external change to an owned property.
    if current ~= entry.value then return true end
    if not self:Write(entry, entry.before) then return false end
    local restored, value = Read(entry.object, entry.getter, type(entry.before))
    return restored and value == entry.before
end

function N:Release(unit)
    local state = self.states[unit]
    if not state then return true end
    state.active = false
    local restored = true
    for i = #state.entries, 1, -1 do
        if self:ReleaseEntry(state.entries[i]) then table.remove(state.entries, i)
        else restored = false end
    end
    if #state.entries == 0 then self.states[unit] = nil end
    return restored
end

local function Find(entries, wanted)
    for _, entry in ipairs(entries) do
        if entry.object == wanted.object and entry.getter == wanted.getter then return entry end
    end
end

function N:Suppress(unit)
    local ok, plan = pcall(BuildPlan, unit)
    if not ok then
        self:Release(unit)
        return false, Public(plan) and type(plan) == "string" and plan or "Native configuration inaccessible"
    end
    local state = self.states[unit]
    if state and state.root ~= plan.root then
        if not self:Release(unit) then return false, "Previous native frame could not be restored" end
        state = nil
    end
    for _, entry in ipairs(plan.entries) do
        if entry.setter == "SetAlpha" and not self:HookAlpha(entry.object) then
            self:Release(unit)
            return false, "Native alpha could not be tracked safely"
        end
    end
    state = state or {root = plan.root, entries = {}}
    self.states[unit] = state
    -- Release only properties no longer part of this exact known layout.
    for i = #state.entries, 1, -1 do
        local entry = state.entries[i]
        if not Find(plan.entries, entry) then
            if not self:ReleaseEntry(entry) then
                self:Release(unit)
                return false, "Previous native state could not be restored"
            end
            table.remove(state.entries, i)
        end
    end
    for _, proposed in ipairs(plan.entries) do
        local entry = Find(state.entries, proposed)
        if not entry or proposed.before ~= entry.value then
            if not self:Write(proposed, proposed.value) then
                self:Release(unit)
                return false, "Native change rejected: " .. proposed.label
            end
            if not entry then
                entry = proposed
                state.entries[#state.entries + 1] = entry
            end
            local applied, value = Read(entry.object, entry.getter, type(entry.value))
            if not applied or value ~= entry.value then
                self:Release(unit)
                return false, "Native change not confirmed: " .. entry.label
            end
        end
    end
    state.active = true
    for _, entry in ipairs(state.entries) do
        if entry.setter == "SetAlpha" then self.alphaOwners[entry.object] = unit end
    end
    return true
end

function N:Apply(selected)
    local status, allOK = {}, true
    if Locked() then
        for _, unit in ipairs(units) do
            status[unit] = {ok = false, hidden = self.states[unit] and self.states[unit].active == true or false,
                error = "Native change deferred until combat ends"}
        end
        self.lastStatus = status
        return false, status
    end
    selected = Public(selected) and type(selected) == "table" and selected or {}
    for _, unit in ipairs(units) do
        local requested = Public(selected[unit]) and selected[unit] == true
        local ok, reason
        if requested then ok, reason = self:Suppress(unit)
        else
            ok = self:Release(unit)
            if not ok then reason = "Native restoration temporarily inaccessible" end
        end
        status[unit] = {ok = ok, hidden = ok and requested, error = reason}
        if not ok then allOK = false end
    end
    self.lastStatus = status
    return allOK, status
end

function N:Restore()
    local ok, status = self:Apply({})
    local restored = self:SyncClassResources(nil)
    status.classResources = {ok = restored, hidden = false}
    return ok and restored, status
end

function N:SyncClassResources(token)
    token = Public(token) and type(token) == "string" and token or nil
    self.classResourceToken = token
    if Locked() then
        self.classResourcePending = true
        return false
    end
    self.classResourcePending = nil
    local ok, reason
    if token then ok, reason = self:Suppress("classResources")
    else ok = self:Release("classResources") end
    self.classResourceError = not ok and reason or nil
    return ok
end
