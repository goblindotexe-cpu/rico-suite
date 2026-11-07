-- Questie's own two display switches remove its brown badges at the source.
-- Questie 12.4.0 / 12.6.1: Modules/QuestieNameplate.lua and its options tab.
-- Its public quest-objective API, map, tracker and tooltip settings stay intact.
local _, RP = ...
local I = { modules = {}, databases = {}, apis = {} }
RP.QuestieIcons = I
local keys = { "nameplateEnabled", "nameplateTargetFrameEnabled" }

local function Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function Field(object, key)
    if Public(object) == nil then return nil end
    if type(object) == "table" and canaccesstable and not canaccesstable(object) then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return Public(value) end
end

local function Profile()
    local questie = Field(_G, "Questie")
    local db = Field(questie, "db")
    return Field(db, "profile"), db, questie
end

local function Error(message)
    I.lastError = type(Public(message)) == "string" and message or "Questie setting inaccessible"
end

-- Restore only values still equal to our override. A later outside change is
-- not overwritten. The backup belongs to the actual profile table, not its name.
function I:ReleaseProfile()
    local owned = self.owned
    self.owned = nil
    if not owned then return end
    for _, key in ipairs(keys) do
        if Field(owned.profile, key) == false then
            local ok, err = pcall(function() owned.profile[key] = owned.values[key] end)
            if not ok then Error(err) end
        end
    end
end

function I:Restore()
    self.active = false
    self.pendingCleanup = nil
    self:ReleaseProfile()
end

function I:Sync(forceCleanup)
    if not self.active or self.loggingOut or self.transition or self.busy then return end
    local profile, db = Profile()
    if self.owned and (self.owned.profile ~= profile or self.owned.db ~= db) then self:ReleaseProfile() end
    local module = self.module
    if type(profile) ~= "table" or type(Field(module, "HideCurrentFrames")) ~= "function"
        or type(Field(module, "HideCurrentTargetFrame")) ~= "function" then return end
    for _, key in ipairs(keys) do
        if type(Field(profile, key)) ~= "boolean" then return end
    end
    local changed = forceCleanup or self.pendingCleanup
    if not self.owned then
        self.owned = { profile = profile, db = db, values = {} }
        for _, key in ipairs(keys) do self.owned.values[key] = Field(profile, key) end
        changed = true
    end
    self.busy = true
    for _, key in ipairs(keys) do
        if Field(profile, key) ~= false then
            -- A user enabled a Questie display option while RicoPlates owns it.
            -- Remember that preference for restoration, then suppress its output.
            self.owned.values[key] = true
            local ok, err = pcall(function() profile[key] = false end)
            if not ok then
                Error(err); self:ReleaseProfile(); self.busy = nil
                return
            end
            changed = true
        end
    end
    if changed then
        -- Both are Questie's own normal option-off cleanup methods. No frame
        -- discovery, parenting, texture matching or protected-frame inspection.
        local ok1, err1 = pcall(module.HideCurrentFrames, module)
        local ok2, err2 = pcall(module.HideCurrentTargetFrame, module)
        self.pendingCleanup = not (ok1 and ok2) or nil
        if not ok1 then Error(err1) elseif not ok2 then Error(err2) else self.lastError = nil end
    end
    self.busy = nil
end

function I:BindQuestie()
    if self.binding or self.loggingOut then return end
    self.binding = true
    local _, db, questie = Profile()
    local loader = Field(_G, "QuestieLoader")
    local import = Field(loader, "ImportModule")
    if type(import) == "function" then
        local ok, module = pcall(import, loader, "QuestieNameplate")
        if ok and type(Public(module)) == "table" then
            if self.module ~= module then self.pendingCleanup = true end
            self.module = module
            local hooks = self.modules[module] or {}
            self.modules[module] = hooks
            for _, method in ipairs({ "NameplateCreated", "UpdateNameplate", "DrawTargetFrame", "RedrawIcons", "RedrawFrameIcon" }) do
                if not hooks[method] and type(Field(module, method)) == "function" and hooksecurefunc then
                    local hooked, err = pcall(hooksecurefunc, module, method, function()
                        if I.module == module then I:Sync() end
                    end)
                    if hooked then hooks[method] = true else Error(err) end
                end
            end
        end
    else
        self.module = nil
    end
    -- AceDB's outgoing-profile callback runs before it removes defaults/saves
    -- that profile. Copy/reset replace the contents and establish new originals.
    local register = Field(db, "RegisterCallback")
    if type(register) == "function" then
        local callbacks = self.databases[db] or {}
        self.databases[db] = callbacks
        for _, event in ipairs({ "OnProfileShutdown", "OnProfileChanged", "OnProfileCopied", "OnProfileReset", "OnDatabaseShutdown" }) do
            if not callbacks[event] then
                local ok, err = pcall(register, self, event, function()
                    if select(2, Profile()) ~= db then return end
                    if event == "OnDatabaseShutdown" then
                        I.loggingOut = true; I:Restore()
                    elseif event == "OnProfileShutdown" then
                        I.transition = true; I:ReleaseProfile()
                    else
                        if event == "OnProfileCopied" or event == "OnProfileReset" then
                            I.owned = nil -- Old values were explicitly replaced by Questie.
                        end
                        I.transition = nil; I:Sync(true)
                    end
                end)
                if ok then callbacks[event] = true else Error(err) end
            end
        end
    end
    local api = Field(questie, "API")
    local ready = Field(api, "RegisterOnReady")
    if type(ready) == "function" and not self.apis[api] then
        self.apis[api] = true -- RegisterOnReady may invoke the callback immediately.
        local ok, err = pcall(ready, function()
            if Field(Field(_G, "Questie"), "API") ~= api or I.loggingOut then return end
            I:BindQuestie(); I:Sync(true)
        end)
        if not ok then self.apis[api] = nil; Error(err) end
    end
    self.binding = nil
end

function I:UpdateSettings()
    if self.loggingOut then return end
    if not RP.db or RP.db.enabled == false then self:Restore(); return end
    self.active = true
    self:BindQuestie()
    self:Sync(true)
end

-- Compatibility with the existing overhead/HUD attachment lifecycle. RicoPlates
-- always owns the green quest glyph; no external glyph replaces or hides it.
function I:Attach() end
function I:Layout() end
function I:Detach() end
function I:HasIcon() return false end

function I:GetStatus()
    if self.lastError then return "Questie badges: cleanup incomplete (" .. self.lastError .. ")" end
    if self.owned then return "Questie badges: off; our green quest icon stays enabled" end
    if self.active then return "Questie badges: waiting for Questie and its profile" end
    return "Questie badges: original settings restored"
end

function I:Initialize()
    if self.frame then return end
    self.frame = CreateFrame("Frame")
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
        self.frame:RegisterEvent(event)
    end
    self.frame:SetScript("OnEvent", function(_, event, addon)
        if event == "PLAYER_LOGOUT" then
            -- SavedVariables are written after logout handlers, including /reload.
            -- Never persist our temporary false values in Questie's settings.
            I.loggingOut = true; I:Restore()
        elseif event ~= "ADDON_LOADED" or Public(addon) == "Questie" then
            if I.active then I:BindQuestie(); I:Sync(event ~= "PLAYER_REGEN_ENABLED") end
        end
    end)
    self:UpdateSettings()
end
