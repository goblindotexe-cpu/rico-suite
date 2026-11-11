local addonName, F = ...
_G.RicoFishing = F
F.name, F.version = addonName, "1.12.0"
F.session = { items = {}, quantity = 0, loots = 0 }
F.defaults = { selected = 6291, goal = 20, pins = true, pinsAllFish = true, hud = true, oneKey = true, fishingKey = "F",
    lureTimer = true, bagWarning = true, favoriteAlerts = true, fishingPrompt = true, recentCatches = true, hudX = 0, hudY = 165 }

function F.IsSecret(value) return issecretvalue and issecretvalue(value) or false end
function F.Number(value)
    return not F.IsSecret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
function F.PublicString(value) return not F.IsSecret(value) and type(value) == "string" end
function F.Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
function F:Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff56dfc4RicoFishing|r: " .. message) end
end

function F:GetEntry(id)
    return self.Number(id) and self.Data and self.Data.items and self.Data.items[id] or nil
end

function F:GetCatalog(query, kind)
    local found = {}
    query = self.PublicString(query) and query:lower() or ""
    for _, id in ipairs(self.Data.order) do
        local entry = self:GetEntry(id)
        if entry and (kind == nil or kind == "all" or kind == entry.kind)
            and (query == "" or entry.name:lower():find(query, 1, true) or tostring(id) == query) then
            found[#found + 1] = entry
        end
    end
    return found
end

function F:GetInventory(id)
    local getter = C_Item and C_Item.GetItemCount or GetItemCount
    local ok, count = self.Call(getter, id, false, false, false, false)
    if ok and self.Number(count) and count >= 0 then return count end
end

function F:GetIcon(id)
    local getter = C_Item and C_Item.GetItemIconByID or GetItemIcon
    local ok, icon = self.Call(getter, id)
    if ok and not self.IsSecret(icon) and (type(icon) == "number" or type(icon) == "string") then return icon end
    local entry = self:GetEntry(id)
    if entry and entry.icon then return "Interface\\Icons\\" .. entry.icon end
    return "Interface\\Icons\\Trade_Fishing"
end

function F:Refresh()
    if self.OneKey and self.OneKey.events
        and (self.OneKey.setting ~= self.db.oneKey or self.OneKey.keySetting ~= self.db.fishingKey) then
        self.OneKey:Update()
    end
    if self.BiteDetector then self.BiteDetector:Sync() end
    if self.warningsReady and (self.lureTimerSetting ~= self.db.lureTimer or self.bagWarningSetting ~= self.db.bagWarning) then
        self.lureTimerSetting, self.bagWarningSetting = self.db.lureTimer, self.db.bagWarning
        self.Warnings:RefreshOptions()
    end
    if self.warningsReady and self.Warnings.RefreshRecentCatches then self.Warnings:RefreshRecentCatches() end
    if self.UI then self.UI:Refresh() end
    if self.spotsReady then self.SpotStats:Refresh() end
end

function F:QueueRefresh()
    if self.refreshPending then return end
    self.refreshPending = true
    local function refresh()
        F.refreshPending = nil
        F:Refresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, refresh) else refresh() end
end

function F:Select(id)
    if not self:GetEntry(id) then return false end
    self.db.selected = id
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    if self.Map then self.Map:Refresh() end
    self:Refresh()
    return true
end

function F:SetGoal(value)
    if not self.Number(value) then return false end
    self.db.goal = math.max(1, math.min(9999, math.floor(value)))
    self:Refresh()
    return true
end

function F:SetOption(key, value)
    if type(self.defaults[key]) ~= "boolean" or type(value) ~= "boolean" then return false end
    self.db[key] = value
    if key == "oneKey" and self.OneKey then self.OneKey:Update() end
    if self.Map and (key == "pins" or key == "pinsAllFish") then self.Map:Refresh() end
    self:Refresh()
    return true
end

function F:SetFishingKey(value)
    local binding = self.OneKey
    if not self.db or not binding then return false, "Fishing keys are unavailable." end
    if InCombatLockdown and InCombatLockdown() then return false, "Change your fishing key after combat." end
    local key = binding:NormalizeKey(value)
    if not key then return false, "Choose a supported key or mouse input." end
    local previous = self.db.fishingKey
    if previous == key then return true end
    if not binding:CanBind(key) then return false, "That key cannot be used for fishing." end
    self.db.fishingKey = key
    if binding:Update() == false then
        self.db.fishingKey = previous
        binding:Update()
        return false, "That key cannot be used for fishing."
    end
    self:Refresh()
    return true
end

-- Only an actual fishing loot window contributes to the session. Reading an
-- inventory count, opening a crate, or looting a creature never becomes a catch.
-- Slot contents are saved before auto-loot clears them; duplicate loot events
-- share one window and each original slot can be credited once.
function F:SnapshotFishingLoot()
    local ok, fishing = self.Call(IsFishingLoot)
    if not ok or self.IsSecret(fishing) or fishing ~= true then self.lootWindow = nil; return end
    local gotSlots, count = self.Call(GetNumLootItems)
    if not gotSlots or not self.Number(count) or count < 0 or count > 100 then return end
    local window = self.lootWindow or { slots = {}, credited = false }
    self.lootWindow = window
    for slot = 1, count do
        if not window.slots[slot] then
            local gotLink, link = self.Call(GetLootSlotLink, slot)
            if gotLink and self.PublicString(link) then
                local id = tonumber(link:match("item:(%d+)"))
                local gotInfo, _, _, quantity = self.Call(GetLootSlotInfo, slot)
                if self.Number(id) and id > 0 and gotInfo and self.Number(quantity) and quantity >= 1 then
                    window.slots[slot] = { id = id, quantity = math.floor(quantity), link = link }
                end
            end
        end
    end
    return window
end

function F:ReceiveLootSlot(slot)
    if not self.Number(slot) or slot < 1 then return end
    local window = self.lootWindow
    local data = window and window.slots[slot]
    if not data or data.received then return end
    data.received = true
    local firstInWindow = not window.credited
    window.credited = true
    if self.SessionLog then
        self.SessionLog:Record(data.id, data.quantity, firstInWindow, window, data.link)
    else
        local session = self.session
        if not session.started then session.started = GetTime and GetTime() or 0 end
        session.items[data.id] = (session.items[data.id] or 0) + data.quantity
        session.quantity = session.quantity + data.quantity
        if firstInWindow then session.loots = session.loots + 1 end
    end
    if self.spotsReady then self.SpotStats:Record(data.id, data.quantity, firstInWindow) end
    self:QueueRefresh()
end

function F:ResetSession()
    if self.SessionLog then self.SessionLog:Reset()
    else self.session = { items = {}, quantity = 0, loots = 0 } end
    self:Refresh()
end

function F:GetSessionRate()
    if self.SessionLog then return self.SessionLog:GetRate() end
    local now = GetTime and GetTime()
    local start = self.session.started
    if not self.Number(now) or not self.Number(start) or now - start < 60 then return nil end
    return self.session.quantity * 3600 / (now - start)
end

function F:Status()
    local observed = 0
    for _, entry in ipairs(self:GetCatalog()) do if entry.observed then observed = observed + 1 end end
    self:Print("v" .. self.version .. " | " .. #self.Data.order .. " catalog items; "
        .. observed .. " with direct Forever catch reports. Not a complete server loot database.")
    if self.Map then self:Print(self.Map:GetStatus()) end
    if self.OneKey then self:Print(self.OneKey:GetStatus()) end
    self:Print("Session: " .. self.session.quantity .. " received items from " .. self.session.loots .. " fishing loot windows.")
end

function F:Command(text)
    text = self.PublicString(text) and text or ""
    local command, argument = text:match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()
    if command == "status" then self:Status()
    elseif command == "reset" then self:ResetSession(); self:Print("New fishing session started.")
    elseif command == "log" and self.SessionLog then self.SessionLog:Toggle()
    elseif command == "spots" and self.spotsReady then self.SpotStats:Toggle()
    elseif command == "tools" and self.UI then self.UI:ToggleTools()
    elseif command == "bite" and self.BiteDetector then self.BiteDetector:Command(argument)
    elseif command == "key" and self.OneKey then
        self:SetOption("oneKey", not self.db.oneKey)
        self:Print(self.OneKey:GetStatus())
    elseif command == "doel" or command == "goal" then
        if not self:SetGoal(tonumber(argument)) then self:Print("Use /rf goal 20.") end
    elseif command == "hud" then self:SetOption("hud", not self.db.hud)
    elseif command == "pins" then self:SetOption("pins", not self.db.pins)
    else self.UI:Toggle() end
end

function F:Initialize()
    if self.initialized then return end
    self.initialized = true
    if type(RicoFishingDB) ~= "table" then RicoFishingDB = {} end
    self.db = RicoFishingDB
    for key, value in pairs(self.defaults) do
        if type(self.db[key]) ~= type(value) then self.db[key] = value end
    end
    if self.OneKey then
        self.db.fishingKey = self.OneKey:NormalizeKey(self.db.fishingKey) or self.defaults.fishingKey
    end
    if not self:GetEntry(self.db.selected) then self.db.selected = self.Data.order[1] end
    if not self.Number(self.db.goal) then self.db.goal = 20 end
    self.db.goal = math.max(1, math.min(9999, math.floor(self.db.goal)))
    if not self.Number(self.db.hudX) then self.db.hudX = 0 end
    if not self.Number(self.db.hudY) then self.db.hudY = 165 end
    if self.SessionLog then self.SessionLog:Initialize() end
    if self.SpotStats then self.SpotStats:Initialize(); self.spotsReady = true end
    if self.OneKey then self.OneKey:Initialize() end
    if self.Map then self.Map:Initialize() end
    if self.UI then self.UI:Initialize() end
    if self.Warnings then
        self.Warnings:Initialize()
        self.lureTimerSetting, self.bagWarningSetting = self.db.lureTimer, self.db.bagWarning
        self.warningsReady = true
    end
    self:Select(self.db.selected)
    self:Print("v" .. self.version .. " loaded. /rf opens the fishing guide.")
end

local events = CreateFrame("Frame")
F.eventFrame = events
for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "LOOT_READY", "LOOT_OPENED",
    "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED"}) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(_, event, argument)
    if event == "ADDON_LOADED" and argument == addonName then F:Initialize(); return end
    if not F.initialized then return end
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        local window = F:SnapshotFishingLoot()
        if event == "LOOT_OPENED" and F.OneKey then F.OneKey:Loot(window, argument) end
    elseif event == "LOOT_SLOT_CLEARED" then F:ReceiveLootSlot(argument)
    elseif event == "LOOT_CLOSED" then F.lootWindow = nil
    elseif event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then F:QueueRefresh()
    elseif event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
        or event == "PLAYER_REGEN_ENABLED" then
        if F.Map then F.Map:Refresh() end
        F:QueueRefresh()
    end
end)
SLASH_RICOFISHING1, SLASH_RICOFISHING2 = "/rf", "/ricofishing"
SlashCmdList.RICOFISHING = function(text) F:Command(text) end
