local addonName, RP = ...
_G.RicoPlates = RP
RP.name, RP.version = addonName, "1.26.0"
RP.media = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
RP.defaults = {
    enabled = true, showFriendlyNPCs = false,
    showParty = true, showRaid = true, showPower = true, showPowerNPC = false,
    showClass = true, showFaction = true, showLevel = true, showCast = true, interruptIndicators = true,
    healthText = "percent", powerText = "value", width = 190, height = 19,
    scale = 1, fontSize = 11, verticalOffset = 0, bubbles = true,
    bubbleCount = 3, bubbleScale = 1.8, maxAnimatedPlates = 24,
    questMarkers = true, questText = false, useQuestie = true, questRoutes = true, compactQuestTracker = true,
    showDebuffs = true, debuffSize = 18, maxDebuffs = 6, debuffsMineOnly = false,
    showBuffs = true, buffSize = 18, maxBuffs = 6, buffsMineOnly = false, targetBuffsAll = true,
    grayTapped = true, grayTrivial = false,
    worldHighlight = true, worldArrow = true, worldArrowSize = 42,
    targetBorder = true, aggroIndicator = true, locale = "en", cvarBackup = {}, worldCVars = {},
    unitFramesEnabled = true, showPlayerFrame = true, showTargetFrame = true, showPetFrame = true,
    unitPortrait3D = true, unitPortraitZoom = 0.85,
    showClassResources = true, showTargetOfTarget = true,
    partyFrames = true, partyFrameScale = 0.8, partyFrameWidth = 200, partyFrameHeight = 20,
    partyLowHealth = true, partyLowHealthThreshold = 25, partyDispels = true,
    healerRange = true, healerHots = true, healerAbsorbs = true, healerOverheal = true, enemyRange = true,
    squareMinimap = true, minimapClock = true, minimapOverview = true,
    layoutGridSnap = true, layoutFrameSnap = true, layoutGridSize = 8, layoutSnapDistance = 12,
    unitFrameWidth = 230, unitFrameHeight = 24, unitFrameScale = 1,
    unitFramePositions = {
        player = { x = -310, y = 250 }, target = { x = 310, y = 250 }, pet = { x = -310, y = 100 },
    },
}
RP.colors = {
    enemy = {0.95, 0.16, 0.12}, neutral = {1.00, 0.78, 0.08},
    party = {0.18, 0.55, 1.00}, raid = {1.00, 0.43, 0.13},
    friendly = {0.23, 0.83, 0.58}, friendlyNPC = {0.23, 0.83, 0.58},
    tapped = {0.70, 0.73, 0.77}, trivial = {0.70, 0.73, 0.77},
    unknown = {0.70, 0.73, 0.77},
}
RP.classIcons = {
    WARRIOR = "Interface\\Icons\\ClassIcon_Warrior",
    PALADIN = "Interface\\Icons\\ClassIcon_Paladin",
    HUNTER = "Interface\\Icons\\ClassIcon_Hunter",
    ROGUE = "Interface\\Icons\\ClassIcon_Rogue",
    PRIEST = "Interface\\Icons\\ClassIcon_Priest",
    DEATHKNIGHT = "Interface\\Icons\\ClassIcon_DeathKnight",
    SHAMAN = "Interface\\Icons\\ClassIcon_Shaman",
    MAGE = "Interface\\Icons\\ClassIcon_Mage",
    WARLOCK = "Interface\\Icons\\ClassIcon_Warlock",
    MONK = "Interface\\Icons\\ClassIcon_Monk",
    DRUID = "Interface\\Icons\\ClassIcon_Druid",
    DEMONHUNTER = "Interface\\Icons\\ClassIcon_DemonHunter",
    EVOKER = "Interface\\Icons\\ClassIcon_Evoker",
}
RP.classAtlas = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
-- Forever may not publish the old FrameXML coordinate table. These are the
-- nine Classic classes from the standard 256px character-creation sheet.
RP.classIconCoords = {
    WARRIOR = {0, 0.25, 0, 0.25}, MAGE = {0.25, 0.49609375, 0, 0.25},
    ROGUE = {0.49609375, 0.7421875, 0, 0.25}, DRUID = {0.7421875, 0.98828125, 0, 0.25},
    HUNTER = {0, 0.25, 0.25, 0.5}, SHAMAN = {0.25, 0.49609375, 0.25, 0.5},
    PRIEST = {0.49609375, 0.7421875, 0.25, 0.5}, WARLOCK = {0.7421875, 0.98828125, 0.25, 0.5},
    PALADIN = {0, 0.25, 0.5, 0.75},
}
RP.factionIcons = {
    Alliance = "Interface\\FriendsFrame\\PlusManz-Alliance",
    Horde = "Interface\\FriendsFrame\\PlusManz-Horde",
}
RP.factionFallbackIcons = {
    Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
    Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
}

function RP.IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

function RP.Readable(value)
    return not RP.IsSecret(value)
end

-- Never turn a restricted boolean into a Lua branch.
function RP.PublicTrue(value)
    if RP.IsSecret(value) then return false end
    return value == true or value == 1
end

-- Forever returns first name and surname separately from UnitName. Its
-- GetUnitName helper returns the display name; the second value is no realm.
function RP:DisplayName(unit)
    local name, surname = UnitName(unit)
    if self.IsSecret(name) then return name end
    if type(name) ~= "string" or name == "" then return nil end
    if not self.PublicTrue(UnitIsPlayer(unit)) then return name end
    if type(GetUnitName) == "function" then
        local ok, full = pcall(GetUnitName, unit, false)
        if ok and self.Readable(full) and type(full) == "string" and full ~= "" then name = full end
    end
    if self.Readable(surname) and type(surname) == "string" and surname ~= ""
        and name ~= surname and name:sub(-#surname - 1) ~= " " .. surname then
        name = name .. " " .. surname
    end
    if type(GetGuildInfo) == "function" then
        local ok, guild = pcall(GetGuildInfo, unit)
        if ok and self.Readable(guild) and type(guild) == "string" and guild ~= "" then
            name = name .. " [" .. guild .. "]"
        end
    end
    return name
end

function RP.CanUseFrame(frame)
    if not frame then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    return true
end

function RP:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff59e4bfRicoPlates|r: " .. message)
    end
end

local function CopyDefaults(dst, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            CopyDefaults(dst[key], value)
        elseif type(dst[key]) ~= type(value) then
            dst[key] = value
        end
    end
end

local function Clamp(value, lo, hi)
    return math.min(hi, math.max(lo, value))
end

function RP:ValidateSettings()
    local d = self.db
    -- Ordinary friendly players have a full bar only while targeted.
    d.showFriendlyPlayers, d.showFriendlyTarget = nil, nil
    d.width = Clamp(d.width, 140, 280)
    d.height = Clamp(d.height, 14, 28)
    d.scale = Clamp(d.scale, 0.75, 1.50)
    d.fontSize = Clamp(d.fontSize, 9, 15)
    d.verticalOffset = Clamp(d.verticalOffset, -30, 50)
    d.worldArrowSize = Clamp(d.worldArrowSize, 28, 72)
    d.partyFrameScale = Clamp(d.partyFrameScale, 0.6, 1.2)
    d.partyFrameWidth = Clamp(math.floor(d.partyFrameWidth), 140, 260)
    d.partyFrameHeight = Clamp(math.floor(d.partyFrameHeight), 16, 26)
    d.partyLowHealthThreshold = Clamp(math.floor(d.partyLowHealthThreshold), 10, 50)
    d.bubbleCount = Clamp(math.floor(d.bubbleCount), 1, 5)
    d.bubbleScale = Clamp(d.bubbleScale, 1, 2.6)
    d.maxAnimatedPlates = Clamp(math.floor(d.maxAnimatedPlates), 0, 40)
    d.debuffSize = Clamp(math.floor(d.debuffSize), 14, 24)
    d.maxDebuffs = Clamp(math.floor(d.maxDebuffs), 1, 10)
    d.buffSize = Clamp(math.floor(d.buffSize), 14, 24)
    d.maxBuffs = Clamp(math.floor(d.maxBuffs), 1, 10)
    d.unitFrameWidth = Clamp(d.unitFrameWidth, 180, 320)
    d.unitFrameHeight = Clamp(d.unitFrameHeight, 18, 34)
    d.unitFrameScale = Clamp(d.unitFrameScale, 0.75, 1.4)
    d.unitPortraitZoom = Clamp(d.unitPortraitZoom, 0.5, 1)
    d.layoutGridSize = Clamp(math.floor(d.layoutGridSize), 4, 32)
    d.layoutSnapDistance = Clamp(d.layoutSnapDistance, 2, 24)
    for _, position in pairs(d.unitFramePositions) do
        if type(position) == "table" then
            position.x = Clamp(tonumber(position.x) or 0, -4000, 4000)
            position.y = Clamp(tonumber(position.y) or 210, 0, 4000)
        end
    end
    for _, key in ipairs({"healthText", "powerText"}) do
        if d[key] ~= "percent" and d[key] ~= "value" and d[key] ~= "none" then
            d[key] = self.defaults[key]
        end
    end
end

function RP:IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function GetCVarValue(name)
    local getter = C_CVar and C_CVar.GetCVar or GetCVar
    if not getter then return nil end
    local ok, value = pcall(getter, name)
    if ok and not RP.IsSecret(value) then return value end
end

function RP:SetOwnedCVar(name, value, allowClampedIncrease)
    local current = GetCVarValue(name)
    if current == nil then return false end
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    if not setter then return false end
    local backup = self.db.cvarBackup
    local saved = backup[name]
    if not saved then
        saved = { original = current }
        backup[name] = saved
    end
    local wanted = tostring(value)
    local ok, result = pcall(setter, name, wanted)
    if not ok or (RP.Readable(result) and result == false) then return false end
    local applied = GetCVarValue(name)
    if applied ~= wanted then
        if not allowClampedIncrease then return false end
        local actual, previous = tonumber(applied), tonumber(current)
        if not actual or not previous or actual <= previous or actual > value then return false end
    end
    saved.applied = applied
    return true
end

function RP:RestoreNameplateCVars()
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    if not setter then return end
    for name, saved in pairs(self.db.cvarBackup) do
        if type(saved) == "table" and saved.original ~= nil then
            -- Preserve a setting subsequently changed by the user/another addon.
            if GetCVarValue(name) == saved.applied then
                pcall(setter, name, saved.original)
            end
        end
    end
    self.db.cvarBackup = {}
end

function RP:ApplyVisibility()
    if not self.db.enabled then self:RestoreNameplateCVars(); return end
    self:SetOwnedCVar("nameplateShowEnemies", "1")
    self:SetOwnedCVar("nameplateShowAll", "1")
    -- Ask the client for more native anchors, without shortening an existing
    -- range. The client can clamp each setting to its own supported limit.
    for _, setting in ipairs({{"nameplateMaxDistance", 45}, {"nameplatePlayerMaxDistance", 40}}) do
        local name, defaultRange = setting[1], setting[2]
        local distance = tonumber(GetCVarValue(name))
        if distance and distance < 60 and not self:SetOwnedCVar(name, 60, true) and distance < defaultRange then
            self:SetOwnedCVar(name, defaultRange, true)
        end
    end
    -- Forever has separate player/NPC filters. The old master switch alone
    -- does not guarantee the client will create friendly-player nameplates.
    -- Keep player anchors available for names even without a full health bar.
    if GetCVarValue("nameplateShowFriendlyPlayers") ~= nil then
        self:SetOwnedCVar("nameplateShowFriendlyPlayers", "1")
    else
        self:SetOwnedCVar("nameplateShowFriends", "1")
    end
    -- Minion nameplate anchors are separate from ordinary friendly NPCs.
    self:SetOwnedCVar("nameplateShowFriendlyPlayerMinions", "1")
    self:SetOwnedCVar("nameplateShowEnemyMinions", "1")
    self:SetOwnedCVar("nameplateShowFriendlyNPCs", self.db.showFriendlyNPCs and "1" or "0")
    if GetCVarValue("nameplateShowOnlyNameForFriendlyPlayerUnits") ~= nil then
        self:SetOwnedCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", "0")
    else
        self:SetOwnedCVar("nameplateShowOnlyNames", "0")
    end
end

function RP:ApplySettings()
    if not self.db then return end
    self:ValidateSettings()
    if self:IsInCombat() then
        self.pendingSettings = true
        return
    end
    self.pendingSettings = nil
    if self.QuestieIcons and self.QuestieIcons.UpdateSettings then self.QuestieIcons:UpdateSettings() end
    self:ApplyVisibility()
    if self.Plates then self.Plates:RefreshAll() end
    if self.UnitFrames then self.UnitFrames:ApplySettings() end
    if self.PartyFrames then self.PartyFrames:UpdateSettings() end
    if self.HealerHots then self.HealerHots:RefreshAll() end
    if self.EnemyRange then self.EnemyRange:Refresh() end
    if self.PartyWarnings then self.PartyWarnings:UpdateSettings() end
    if self.Dispels then self.Dispels:UpdateSettings() end
    if self.Aggro then self.Aggro:UpdateSettings() end
    if self.Quest and self.Quest.UpdateSettings then self.Quest:UpdateSettings() end
    if self.QuestRoutes then self.QuestRoutes:UpdateSettings() end
    if self.QuestTracker then self.QuestTracker:UpdateSettings() end
    if self.World and self.World.UpdateSettings then self.World:UpdateSettings() end
    if self.Minimap then self.Minimap:UpdateSettings() end
    if self.Options and self.Options.RefreshPreview then self.Options:RefreshPreview() end
end

function RP:SetOption(key, value)
    if self.defaults[key] == nil or type(value) ~= type(self.defaults[key]) then return end
    self.db[key] = value
    self:ApplySettings()
end

function RP:OnQuestInfoChanged(unit, info)
    if self.Plates then self.Plates:UpdateQuest(unit, info) end
    if self.UnitFrames then self.UnitFrames:OnQuestInfoChanged(unit, info) end
    if self.World and self.World.OnQuestInfoChanged then self.World:OnQuestInfoChanged(unit, info) end
end

function RP:OnExternalQuestIconChanged(plate)
    -- RicoPlates owns its green marker. Questie's separate badge display is
    -- disabled at its source; its presence can no longer hide our own glyph.
    if plate.quest then plate.quest.icon:Show() end
end

function RP:SyncNativeClassResources()
    if not self.NativeFrames or not self.NativeFrames.SyncClassResources then return end
    local player = self.UnitFrames and self.UnitFrames.frames.player
    local replace = self.db and self.db.enabled and self.db.showClassResources
        and player and player.enabled and self.classResourceToken or nil
    self.NativeFrames:SyncClassResources(replace)
end

function RP:OnClassResourceDisplayChanged(token)
    self.classResourceToken = self.Readable(token) and type(token) == "string" and token or nil
    self:SyncNativeClassResources()
end

function RP:Reset()
    if self:IsInCombat() then
        self:Print("Reset is available after combat. Your current settings are preserved.")
        return
    end
    self:RestoreNameplateCVars()
    if self.World then self.World:RestoreCVars() end
    if self.QuestieIcons and self.QuestieIcons.Restore then self.QuestieIcons:Restore() end
    wipe(self.db)
    CopyDefaults(self.db, self.defaults)
    self:ApplySettings()
    if self.Options then self.Options:RefreshControls() end
    self:Print("Default settings restored.")
end

function RP:Restore()
    if self:IsInCombat() then
        self.pendingRestore = true
        self:Print("Restoration will run when combat ends.")
        return
    end
    self.db.enabled = false
    self.db.worldHighlight, self.db.worldArrow = false, false
    self:RestoreNameplateCVars()
    if self.World then self.World:RestoreCVars() end
    self:ApplySettings()
    if self.Options then self.Options:RefreshControls() end
    self:Print("RicoPlates disabled; game settings previously changed by RicoPlates have been restored.")
end

function RP:Status()
    local version, build, _, interface = GetBuildInfo()
    self:Print("v" .. self.version .. " | client " .. tostring(version) .. ", build " .. tostring(build)
        .. ", interface " .. tostring(interface))
    local count, forbidden = 0, 0
    if self.Plates then
        for _ in pairs(self.Plates.active) do count = count + 1 end
        forbidden = self.Plates.forbiddenCount or 0
    end
    self:Print("Active nameplates: " .. count .. " | skipped protected plates: " .. forbidden)
    if self.Plates then
        self:Print("Animated world nameplates: " .. (self.Plates.animatedCount or 0) .. " / " .. self.db.maxAnimatedPlates)
        self:Print("NPC resource filter: " .. (self.Plates.powerAlphaClamp
            and "public zero check + native maximum filter" or "public capacity check (native maximum filter unavailable)"))
    end
    self:Print("Questie API: " .. ((Questie and Questie.API and Questie.API.GetQuestObjectiveIconForUnit) and "available" or "unavailable; built-in quest detection active"))
    if self.QuestieIcons and self.QuestieIcons.GetStatus then self:Print(self.QuestieIcons:GetStatus()) end
    if self.Quest and self.Quest.GetStatus then
        local status = self.Quest:GetStatus()
        self:Print("Quest detection: " .. tostring(status.tracked) .. " targets, " .. tostring(status.scans)
            .. " checks, " .. tostring(status.errors) .. " skipped API errors.")
        if status.lastError then self:Print("Last quest API error: " .. status.lastError) end
    end
    if self.World and self.World.GetStatus then self:Print(self.World:GetStatus()) end
    if self.UnitFrames and self.UnitFrames.GetStatus then
        self:Print(self.UnitFrames:GetStatus())
        if self.UnitFrames.lastError then self:Print("Last unitframe message: " .. self.UnitFrames.lastError) end
    end
    if self.ClassResources and self.ClassResources.GetStatus then self:Print(self.ClassResources:GetStatus()) end
    if self.NativeFrames and self.NativeFrames.classResourceError then
        self:Print("Native class resource: " .. self.NativeFrames.classResourceError)
    end
    if self.Auras and self.Auras.GetStatus then
        self:Print(self.Auras:GetStatus())
        if self.Auras.stats.lastError then self:Print("Last debuff message: " .. self.Auras.stats.lastError) end
    end
    if interface ~= 16001 then
        self:Print("This release targets Forever (16001); you are running a different client version.")
    end
end

local function Slash(message)
    local command = (message or ""):lower():match("^%s*(%S*)")
    if command == "status" or command == "debug" then RP:Status()
    elseif command == "restore" or command == "herstel" then RP:Restore()
    elseif command == "reset" then RP:Reset()
    elseif command == "preview" or command == "voorbeeld" then RP.Options:Toggle(true)
    elseif command == "minimap" then RP.Options:Toggle(true); RP.Options:SelectPage(7)
    elseif command == "unlock" or command == "verplaatsen" then
        if RP.UnitFrames then RP.UnitFrames:SetUnlocked(true) end
    elseif command == "lock" or command == "vastzetten" then
        if RP.UnitFrames then RP.UnitFrames:SetUnlocked(false) end
    elseif command == "help" then
        RP:Print("/rp: settings | /rp minimap: map settings | /rp unlock / lock: move unitframes | /rp status: diagnostics | /rp restore: restore game UI | /rp reset: defaults.")
    else RP.Options:Toggle() end
end

function RP:Initialize()
    if self.initialized then return end
    self.initialized = true
    if self.Mining then self.Mining:Initialize() end
    if self.Inventory then self.Inventory:Initialize() end
    if self.Minimap then self.Minimap:Initialize() end
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
        self:Print("This client has no supported nameplate API. Use the Forever client.")
        return
    end
    if self.Auras then self.Auras:Initialize() end
    if self.EnemyRange then self.EnemyRange:Initialize() end
    if self.QuestieIcons then self.QuestieIcons:Initialize() end
    if self.LootButton then self.LootButton:Initialize() end
    self.Plates:Initialize()
    if self.Aggro then self.Aggro:Initialize() end
    if self.UnitFrames then self.UnitFrames:Initialize() end
    if self.PartyFrames then self.PartyFrames:Initialize() end
    if self.PartyWarnings then self.PartyWarnings:Initialize() end
    if self.Dispels then self.Dispels:Initialize() end
    if self.ClassResources then self.ClassResources:Initialize() end
    self.Quest:Initialize()
    if self.QuestRoutes then self.QuestRoutes:Initialize() end
    if self.QuestTracker then self.QuestTracker:Initialize() end
    self.World:Initialize()
    self.Options:Initialize()
    self:ApplySettings()
    self:Print("v" .. self.version .. " loaded. Type |cffffffff/rp|r for settings and previews.")
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    for _, other in ipairs({"Plater", "Kui_Nameplates", "TidyPlates", "NeatPlates", "ThreatPlates"}) do
        if loaded and loaded(other) then
            self:Print(other .. " is also active. Use one nameplate replacement at a time to avoid overlap.")
            break
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        if type(RicoPlatesDB) ~= "table" then RicoPlatesDB = {} end
        RP.db = RicoPlatesDB
        CopyDefaults(RP.db, RP.defaults)
        RP:ValidateSettings()
        SLASH_RICOPLATES1, SLASH_RICOPLATES2 = "/rp", "/ricoplates"
        SlashCmdList.RICOPLATES = Slash
    elseif event == "PLAYER_LOGIN" then
        RP:Initialize()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if RP.pendingRestore then RP.pendingRestore = nil; RP:Restore()
        elseif RP.pendingSettings then RP:ApplySettings()
        elseif RP.initialized and RP.Plates then RP.Plates:RefreshAll() end
    end
end)
