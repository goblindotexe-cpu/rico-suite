-- RicoPlates: bounded, event-driven quest detection for the Forever client.
-- No database scans, world-object enumeration, tooltip OnUpdate polling, or
-- comparisons involving secret values. See README for client restrictions.
local _, RP = ...
local Quest = {}
RP.Quest = Quest

local type, pairs, pcall = type, pairs, pcall
local min = math.min
local issecretvalue = _G.issecretvalue
local GetTime = _G.GetTime
local QUEST_TITLE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or 17
local QUEST_OBJECTIVE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or 8
local OBJECT_TOOLTIP = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object or 4
local MAX_TOOLTIP_LINES, MAX_OBJECTIVES = 80, 24
local WORK_INTERVAL, MAX_SCANS_PER_TICK, WORK_BUDGET_MS = 0.035, 2, 0.8

-- A public value is the only kind of value used as a key, in a comparison,
-- for string parsing, or for arithmetic. A secret result is simply unavailable.
local function Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function PublicTable(value)
    value = Public(value)
    if type(value) == "table" then return value end
end

local function PublicString(value)
    value = Public(value)
    if type(value) == "string" then return value end
end

local function PublicNumber(value)
    value = Public(value)
    if type(value) == "number" then return value end
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return Public(value) end
    return nil
end

local function Now()
    return GetTime and GetTime() or 0
end

local function ValidToken(unit)
    return PublicString(unit) ~= nil and unit ~= ""
end

local function GUID(unit)
    return PublicString(Call(_G.UnitGUID, unit))
end

local function IsObject(unit, guid)
    if Call(_G.UnitIsGameObject, unit) == true then return true end
    return guid ~= nil and guid:match("^GameObject%-") ~= nil
end

local function Normalize(text)
    text = PublicString(text)
    if not text then return nil end
    -- Native objective text normally matches the quest log exactly. Removing
    -- presentation markup tolerates client formatting without guessing IDs.
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("^%s+", ""):gsub("%s+$", "")
end

local function ObjectiveKind(objectiveType)
    objectiveType = PublicString(objectiveType)
    if objectiveType == "item" then return "loot" end
    if objectiveType == "monster" then return "kill" end
    return "quest"
end

local function IsFinished(flag, fulfilled, required)
    flag, fulfilled, required = Public(flag), PublicNumber(fulfilled), PublicNumber(required)
    if flag == true then return true end
    if fulfilled and required and required > 0 then return fulfilled >= required end
    if flag == false then return false end
    return nil
end

Quest.tracked = {}
Quest.cache = {}
Quest.questCache = {}
Quest.pending = {}
Quest.queue = {}
Quest.queueHead, Quest.queueTail = 1, 0
Quest.generation = 1
Quest.stats = { scans = 0, errors = 0 }

function Quest:IsEnabled()
    local db = RP.db
    if db and db.enabled == false then return false end
    return not db or db.questMarkers ~= false or db.worldArrow ~= false
end

function Quest:GetQuestMetadata(questID)
    questID = PublicNumber(questID)
    if not questID or questID <= 0 then return nil end
    local cached = self.questCache[questID]
    if cached ~= nil then return cached ~= false and cached or nil end

    local log = _G.C_QuestLog
    if not log then self.questCache[questID] = false; return nil end
    local metadata = { objectives = {}, own = Call(log.IsOnQuest, questID) }
    if metadata.own == false then
        self.questCache[questID] = metadata
        return metadata
    end

    local objectives = PublicTable(Call(log.GetQuestObjectives, questID))
    if objectives then
        local allKind, mixed, incompleteCount = nil, false, 0
        for i = 1, min(#objectives, MAX_OBJECTIVES) do
            local objective = PublicTable(objectives[i])
            if objective then
                local text = Normalize(objective.text)
                local kind = ObjectiveKind(objective.type)
                local done = IsFinished(objective.finished, objective.numFulfilled, objective.numRequired)
                metadata.objectives[#metadata.objectives + 1] = { text = text, kind = kind, done = done }
                if done == false then
                    incompleteCount = incompleteCount + 1
                    if allKind and allKind ~= kind then mixed = true end
                    allKind = allKind or kind
                elseif done == nil then
                    -- Unknown completion/type must not turn a mixed objective
                    -- quest into an assumed kill-only or loot-only quest.
                    mixed = true
                end
            end
        end
        if incompleteCount > 0 and not mixed then metadata.commonKind = allKind end
    end
    self.questCache[questID] = metadata
    return metadata
end

function Quest:MatchObjective(questID, text)
    local metadata = self:GetQuestMetadata(questID)
    if not metadata then return "quest", nil, nil end
    if metadata.own == false then return nil, nil, false end
    text = Normalize(text)
    if text then
        for i = 1, #metadata.objectives do
            local objective = metadata.objectives[i]
            if objective.text == text then return objective.kind, objective.done, metadata.own end
        end
    end
    return metadata.commonKind or "quest", nil, metadata.own
end

function Quest:ReadNative(unit, guid, isObject)
    local api = _G.C_TooltipInfo
    local data = api and PublicTable(Call(api.GetUnit, unit))
    if not data then return nil, "unavailable" end

    -- Do not attach data from a previous token occupant to the current plate.
    local tooltipGUID = PublicString(data.guid)
    if guid and tooltipGUID and guid ~= tooltipGUID then return nil, "unavailable" end
    isObject = isObject or PublicNumber(data.type) == OBJECT_TOOLTIP
    local lines = PublicTable(data.lines)
    if not lines then return nil, "restricted" end

    local questID, title, info
    local sawComplete, sawUnknown = false, false
    for i = 1, min(#lines, MAX_TOOLTIP_LINES) do
        local line = PublicTable(lines[i])
        if line then
            local lineType = PublicNumber(line.type)
            if lineType == QUEST_TITLE then
                -- Native quest titles use `id`; `lineIndex` is a rendering
                -- index and must NEVER be treated as a quest objective index.
                questID = PublicNumber(line.id)
                title = PublicString(line.leftText)
            elseif lineType == QUEST_OBJECTIVE then
                local text = PublicString(line.leftText)
                local fulfilled = PublicNumber(line.numFulfilled)
                local required = PublicNumber(line.numRequired)
                local done = IsFinished(line.completed, fulfilled, required)
                local kind, logDone, own = self:MatchObjective(questID, text)
                if own == true then
                    if done == true or logDone == true then
                        sawComplete = true
                    elseif done == false or logDone == false then
                        kind = kind or "quest"
                        if not info then
                            info = {
                                kind = kind, source = "native", isObject = isObject,
                                questID = questID, title = title, text = text,
                            }
                            if fulfilled and required and required > 0 then
                                info.progress = string.format("%d/%d", fulfilled, required)
                                info.fulfilled, info.required = fulfilled, required
                            end
                        elseif info.kind ~= kind then
                            info.kind = "quest"
                        end
                        if kind == "kill" then info.hasKill = true end
                        if kind == "loot" then info.hasLoot = true end
                    else
                        sawUnknown = true
                    end
                elseif own == nil then
                    -- A tooltip can also show party progress. Without a
                    -- readable active quest ID, rely on the native related-to-
                    -- active-quest hint below rather than claiming ownership.
                    sawUnknown = true
                end
            end
        end
    end
    if info then return info, "objective" end
    if sawComplete and not sawUnknown then return nil, "complete" end
    return nil, sawUnknown and "restricted" or "empty"
end

local function QuestieAPI()
    local questie = PublicTable(_G.Questie)
    local api = questie and PublicTable(questie.API)
    if api and Public(api.isReady) == true then return api, questie end
end

local function QuestieIconKind(icon, questie)
    -- The stable API returns a texture rather than an objective enum. Optional
    -- style metadata lets us name its standard/custom kill and loot icons. A
    -- shared/unknown texture remains generic; it is never guessed from a name.
    local icons = PublicTable(questie.icons)
    local db = PublicTable(questie.db)
    local profile = db and PublicTable(db.profile)
    local loot = icons and PublicString(icons.loot)
    local kill = icons and PublicString(icons.slay)
    local customLoot = profile and PublicString(profile.ICON_LOOT)
    local customKill = profile and PublicString(profile.ICON_SLAY)
    local isLoot = icon == loot or icon == customLoot
    local isKill = icon == kill or icon == customKill
    if isLoot and not isKill then return "loot" end
    if isKill and not isLoot then return "kill" end
    return "quest"
end

function Quest:ReadQuestie(guid, isObject)
    if RP.db and RP.db.useQuestie == false then return nil end
    if not guid or isObject then return nil end
    -- The public API accepts NPC GUIDs only; never send an object, player,
    -- nil, secret GUID, or a raw object/NPC number to it.
    if not guid:match("^Creature%-") and not guid:match("^Vehicle%-") then return nil end
    local api, questie = QuestieAPI()
    if not api then return nil end
    local icon = PublicString(Call(api.GetQuestObjectiveIconForUnit, guid))
    if not icon or icon == "" then return nil end
    local kind = QuestieIconKind(icon, questie)
    return {
        kind = kind, icon = icon, source = "questie", isObject = false,
        hasKill = kind == "kill", hasLoot = kind == "loot",
    }
end

function Quest:Scan(unit)
    local guid = GUID(unit)
    if Call(_G.UnitIsPlayer, unit) == true then return nil, false, guid end
    local isObject = IsObject(unit, guid)
    -- UnitExists is false for some legitimate softinteract GameObjects.
    if not isObject and not guid and Call(_G.UnitExists, unit) == false then
        return nil, false, guid
    end

    local info, nativeStatus = self:ReadNative(unit, guid, isObject)
    if info then
        if info.kind == "quest" and not (info.hasKill and info.hasLoot) then
            local extra = self:ReadQuestie(guid, isObject)
            if extra then
                info.kind, info.icon = extra.kind, extra.icon
                info.hasKill, info.hasLoot = extra.hasKill, extra.hasLoot
            end
        end
        return info, false, guid
    end
    if nativeStatus == "complete" then return nil, false, guid end

    info = self:ReadQuestie(guid, isObject)
    if info then return info, false, guid end

    local log = _G.C_QuestLog
    local related = log and Call(log.UnitIsRelatedToActiveQuest, unit)
    if related == true then
        return { kind = "quest", source = "native", isObject = isObject }, false, guid
    end
    return nil, nativeStatus == "unavailable", guid
end

function Quest:Wake()
    if self.worker then self.worker:Show() end
end

function Quest:Request(unit, force)
    if not ValidToken(unit) or not self:IsEnabled() then return end
    if not self.worker then self:Initialize() end
    self.tracked[unit] = true
    local cached = self.cache[unit]
    if not force and cached and cached.generation == self.generation then return end
    if self.pending[unit] then return end
    self.queueTail = self.queueTail + 1
    self.queue[self.queueTail] = unit
    self.pending[unit] = true
    self:Wake()
end

function Quest:GetUnitInfo(unit)
    if not ValidToken(unit) or not self:IsEnabled() then return nil end
    local cached = self.cache[unit]
    if cached and cached.generation == self.generation then
        local guid = GUID(unit)
        if guid == cached.guid then return cached.info or nil end
        -- Recycled nameplate or a newly restricted identity: clear stale data.
        self.cache[unit] = nil
    end
    self:Request(unit)
    return nil
end

function Quest:Forget(unit)
    if not ValidToken(unit) then return end
    self.tracked[unit], self.pending[unit], self.cache[unit] = nil, nil, nil
end

function Quest:Invalidate()
    if not self.worker or not self:IsEnabled() then return end
    -- A burst of native and Questie events produces only one refresh. The
    -- earliest deadline stays fixed so continuous events cannot starve work.
    self.invalidateAt = self.invalidateAt or (Now() + 0.12)
    self:Wake()
end

function Quest:RefreshGeneration()
    self.invalidateAt = nil
    self.generation = self.generation + 1
    self.questCache = {}
    for unit in pairs(self.tracked) do self:Request(unit, true) end
end

function Quest:ProcessUnit(unit)
    self.stats.scans = self.stats.scans + 1
    local ok, info, retry, guid = pcall(self.Scan, self, unit)
    if not ok then
        self.stats.errors = self.stats.errors + 1
        local message = PublicString(info)
        self.stats.lastError = message and message:sub(1, 240) or "Unreadable API data"
        info, retry, guid = nil, false, GUID(unit)
    end
    local previous = self.cache[unit]
    local record = {
        generation = self.generation, guid = guid, info = info or false,
        retried = previous and previous.generation == self.generation and previous.retried or false,
    }
    self.cache[unit] = record
    if RP.OnQuestInfoChanged then RP:OnQuestInfoChanged(unit, info) end
    -- A newly created native plate can precede its tooltip data. Retry once;
    -- the timer only queues work, it does not scan a batch on the timer frame.
    if retry and not record.retried and C_Timer and C_Timer.After then
        record.retried = true
        C_Timer.After(0.35, function()
            if self.tracked[unit] and self.cache[unit] == record then self:Request(unit, true) end
        end)
    end
end

function Quest:OnUpdate(elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < WORK_INTERVAL then return end
    self.elapsed = 0
    if self.invalidateAt and Now() >= self.invalidateAt then self:RefreshGeneration() end

    local start = debugprofilestop and debugprofilestop()
    local scans, dequeued = 0, 0
    while self.queueHead <= self.queueTail and scans < MAX_SCANS_PER_TICK and dequeued < 20 do
        local unit = self.queue[self.queueHead]
        self.queue[self.queueHead] = nil
        self.queueHead = self.queueHead + 1
        dequeued = dequeued + 1
        if self.pending[unit] and self.tracked[unit] then
            self.pending[unit] = nil
            if self:IsEnabled() then self:ProcessUnit(unit) end
            scans = scans + 1
            if start and debugprofilestop() - start >= WORK_BUDGET_MS then break end
        end
    end
    if self.queueHead > self.queueTail then
        self.queueHead, self.queueTail = 1, 0
        if not self.invalidateAt then self.worker:Hide() end
    end
end

function Quest:BindQuestie()
    local questie = PublicTable(_G.Questie)
    local api = questie and PublicTable(questie.API)
    if not api or self.boundQuestieAPI == api then return end
    local function Ready()
        if self.questUpdateAPI ~= api and type(api.RegisterForQuestUpdates) == "function" then
            local ok = pcall(api.RegisterForQuestUpdates, function() self:Invalidate() end)
            if ok then self.questUpdateAPI = api end
        end
        self:Invalidate()
    end
    if type(api.RegisterOnReady) == "function" then
        self.boundQuestieAPI = api
        local ok = pcall(api.RegisterOnReady, Ready)
        if not ok then self.boundQuestieAPI = nil end
    elseif Public(api.isReady) == true then
        self.boundQuestieAPI = api
        Ready()
    end
end

function Quest:UpdateSettings()
    if not self:IsEnabled() then
        for unit in pairs(self.tracked) do
            if RP.OnQuestInfoChanged then RP:OnQuestInfoChanged(unit, nil) end
        end
        self.tracked, self.pending, self.cache, self.questCache = {}, {}, {}, {}
        self.queue, self.queueHead, self.queueTail = {}, 1, 0
        self.invalidateAt = nil
        if self.worker then self.worker:Hide() end
        return
    end
    self:BindQuestie()
    self:Invalidate()
end

function Quest:GetStatus()
    local count = 0
    for _ in pairs(self.tracked) do count = count + 1 end
    local api = QuestieAPI()
    return {
        tracked = count, scans = self.stats.scans, errors = self.stats.errors,
        lastError = self.stats.lastError,
        tooltipAPI = C_TooltipInfo and type(C_TooltipInfo.GetUnit) == "function" or false,
        questieReady = api ~= nil,
    }
end

function Quest:Initialize()
    if self.worker then return end
    local worker = CreateFrame("Frame")
    self.worker = worker
    worker:Hide()
    worker:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
    worker:SetScript("OnEvent", function(_, event, arg1)
        if event == "NAME_PLATE_UNIT_REMOVED" then
            self:Forget(arg1)
        elseif event == "ADDON_LOADED" then
            if PublicString(arg1) == "Questie" then self:BindQuestie() end
        elseif event == "UNIT_QUEST_LOG_CHANGED" then
            if PublicString(arg1) == "player" then self:Invalidate() end
        else
            self:Invalidate()
        end
    end)
    local events = {
        "NAME_PLATE_UNIT_REMOVED", "ADDON_LOADED", "QUEST_LOG_UPDATE",
        "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_WATCH_UPDATE",
        "UNIT_QUEST_LOG_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED",
    }
    for i = 1, #events do pcall(worker.RegisterEvent, worker, events[i]) end
    self:BindQuestie()
end
