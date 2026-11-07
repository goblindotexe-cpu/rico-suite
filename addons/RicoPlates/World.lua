local addonName, RP = ...

-- World objects do not have general-purpose addon coordinates. This module
-- uses the interaction target and existing object nameplates from the client.
-- Never substitute a screen-space guess or draw through forbidden frames.
local World = {}
RP.World = World

local SOFT = "softinteract"
local MIN_ARROW_SIZE, MAX_ARROW_SIZE = 24, 80
local OUTLINE_SETTINGS = {
    { "Outline", "2" },
    { "graphicsOutlineMode", "2" },
    { "raidGraphicsOutlineMode", "2" },
}
local INTERACT_SETTINGS = {
    { "SoftTargetInteract", "3" },
    { "SoftTargetIconGameObject", "1" },
    { "SoftTargetLowPriorityIcons", "1" },
    { "SoftTargetInteractRange", "15" },
    { "SoftTargetInteractArc", "2" },
    { "SoftTargetInteractOnlyInRange", "0" },
    -- The last setting is gated by quest relevance in Refresh().
    { "SoftTargetNameplateInteract", nil },
}

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or IsSecret(value) then return nil end
    return value
end

local function InCombat()
    return Read(InCombatLockdown) == true
end

local function GetCVarValue(name)
    local getter = C_CVar and C_CVar.GetCVar or GetCVar
    local value = Read(getter, name)
    if type(value) == "string" then return value end
    if type(value) == "number" then return tostring(value) end
end

local function SameCVarValue(first, second)
    if first == second then return true end
    local a, b = tonumber(first), tonumber(second)
    return a ~= nil and b ~= nil and a == b
end

local function SetCVarValue(name, value)
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    if type(setter) ~= "function" or InCombat() then return false end
    local current = GetCVarValue(name)
    if SameCVarValue(current, value) then return true, current end
    World.writing = true
    local ok = pcall(setter, name, value)
    World.writing = false
    local applied = GetCVarValue(name)
    return ok and SameCVarValue(applied, value), applied
end

local function ArrowWanted()
    return RP.db and RP.db.enabled ~= false and RP.db.worldArrow ~= false
end

local function OutlineWanted()
    return RP.db and RP.db.enabled ~= false and RP.db.worldHighlight ~= false
end

local function ObjectMarkersWanted()
    return RP.db and RP.db.enabled ~= false and RP.db.questMarkers == true
end

local function SafeFrame(frame)
    if IsSecret(frame) or not frame then return false end
    if frame.IsForbidden and Read(frame.IsForbidden, frame) ~= false then
        return false
    end
    return true
end

local function NamePlate(unit)
    local api = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    local plate = Read(api, unit)
    if SafeFrame(plate) then return plate end
end

local function IsObject(unit)
    local answer = Read(UnitIsGameObject, unit)
    if answer ~= nil then return answer == true end
    local guid = Read(UnitGUID, unit)
    return type(guid) == "string" and guid:match("^GameObject%-") ~= nil
end

local function SameObject(first, second)
    if first == second then return true end
    if Read(UnitIsUnit, first, second) == true then return true end
    local guid1, guid2 = Read(UnitGUID, first), Read(UnitGUID, second)
    return type(guid1) == "string" and type(guid2) == "string" and guid1 == guid2
end

function World:RememberCVar(name, group)
    if not RP.db then return nil end
    RP.db.worldCVars = RP.db.worldCVars or {}
    local saved = RP.db.worldCVars[name]
    if type(saved) == "table" then return saved end
    local current = GetCVarValue(name)
    if current == nil then
        self.unsupported[name] = true
        return nil
    end
    saved = { original = current, applied = current, group = group }
    RP.db.worldCVars[name] = saved
    return saved
end

function World:WriteCVar(name, value, group)
    local saved = self:RememberCVar(name, group)
    if not saved or not value then return false end
    local ok, applied = SetCVarValue(name, value)
    if ok then
        saved.applied = applied
        return true
    end
    return false
end

function World:ApplyGroup(settings, group)
    -- Snapshot the entire group before writing; graphics CVars may affect one
    -- another and must not be captured halfway through an update.
    for _, setting in ipairs(settings) do
        self:RememberCVar(setting[1], group)
    end
    for _, setting in ipairs(settings) do
        if setting[2] then self:WriteCVar(setting[1], setting[2], group) end
    end
    -- Capture the final client values, including any coupled graphics setting.
    for _, setting in ipairs(settings) do
        local saved = RP.db.worldCVars[setting[1]]
        if saved then saved.applied = GetCVarValue(setting[1]) or saved.applied end
    end
end

function World:RestoreGroup(group)
    local saved = RP.db and RP.db.worldCVars
    if not saved then return true end
    if InCombat() then return false end
    local complete, restore = true, {}
    local settings = group == "outline" and OUTLINE_SETTINGS or INTERACT_SETTINGS
    -- Decide ownership before restoring anything. A base graphics write can
    -- also change raid graphics; restore the raid setting after the base one.
    for _, setting in ipairs(settings) do
        local name = setting[1]
        local entry = saved[name]
        if type(entry) == "table" and entry.group == group then
            local current = GetCVarValue(name)
            if not SameCVarValue(current, entry.applied) then
                -- A later manual/other-addon change belongs to its author.
                saved[name] = nil
                -- A coupled base-graphics restoration must also preserve this
                -- newer value, so reapply it in the same dependency order.
                if current ~= nil then restore[#restore + 1] = { name, current } end
            else
                restore[#restore + 1] = { name, entry.original }
            end
        end
    end
    for _, entry in ipairs(restore) do
        if SetCVarValue(entry[1], entry[2]) then
            saved[entry[1]] = nil
        else
            complete = false
        end
    end
    return complete
end

function World:SetGate(wanted)
    if InCombat() or not ArrowWanted() then return end
    local saved = self:RememberCVar("SoftTargetNameplateInteract", "arrow")
    if not saved then return end
    -- Leave the user's pre-existing interaction nameplates available when the
    -- object is not a quest target. Only add a plate where this feature needs it.
    local value = wanted and "1" or saved.original
    self:WriteCVar("SoftTargetNameplateInteract", value, "arrow")
end

local function DrawArrow(frame)
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints(frame)
    icon:SetTexture((RP.media or "Interface\\AddOns\\" .. addonName .. "\\Media\\") .. "Arrow")
    frame.icon = icon
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", frame, "TOP", 0, 1)
    label:SetTextColor(0.48, 1, 0.61, 1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    label:SetText("QUEST OBJECT")
    frame.label = label
end

function World:CreateArrow()
    if self.arrow then return self.arrow end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(48, 48)
    frame:EnableMouse(false)
    frame:Hide()
    DrawArrow(frame)
    local bounce = frame:CreateAnimationGroup()
    bounce:SetLooping("BOUNCE")
    local move = bounce:CreateAnimation("Translation")
    move:SetOffset(0, 5)
    move:SetDuration(0.75)
    move:SetSmoothing("IN_OUT")
    frame.bounce = bounce
    self.arrow = frame
    return frame
end

function World:HideArrow()
    if self.arrow then
        self.arrow:Hide()
        self.arrow.bounce:Stop()
        self.arrow:ClearAllPoints()
        -- Detach while safe so a recycled nameplate cannot inherit the arrow.
        if not InCombat() then self.arrow:SetParent(UIParent) end
    end
    self.anchor, self.anchorToken = nil, nil
    self.visible = false
end

function World:PositionArrow()
    if not self.arrow or not self.anchor or InCombat() then return end
    local marker = self.objectMarkers and self.objectMarkers[self.anchor]
    local anchor = marker and marker:IsShown() and marker or self.anchor
    self.arrow:ClearAllPoints()
    self.arrow:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
end

function World:AttachArrow(plate, unit)
    if InCombat() or not SafeFrame(plate) then return end
    local frame = self:CreateArrow()
    local size = RP.db.worldArrowSize
    if type(size) ~= "number" then size = 42 end
    size = math.max(MIN_ARROW_SIZE, math.min(MAX_ARROW_SIZE, size))
    frame:SetScale(size / 42)
    if self.anchor ~= plate then
        frame:Hide()
        frame.bounce:Stop()
        frame:SetParent(plate)
        local level = Read(plate.GetFrameLevel, plate)
        if type(level) == "number" then frame:SetFrameLevel(level + 10) end
        self.anchor = plate
    end
    self:PositionArrow()
    local token = plate.GetUnit and Read(plate.GetUnit, plate)
    self.anchorToken = type(token) == "string" and token or unit
    frame:Show()
    if not frame.bounce:IsPlaying() then frame.bounce:Play() end
    self.visible = true
    self.status = "Arrow above the current quest object"
end

function World:ResolveObject()
    if IsObject(SOFT) then
        local plate = NamePlate(SOFT)
        if plate then return SOFT, plate end
        for unit, candidate in pairs(self.objects) do
            if SafeFrame(candidate) and SameObject(unit, SOFT) then
                return unit, candidate
            end
        end
        -- Quest recognition is possible before the client creates its plate.
        return SOFT, nil
    end
end

function World:GetQuestInfo(unit)
    if RP.Quest and RP.Quest.GetUnitInfo then
        -- The quest module also checks completed objectives and owns its cache.
        -- A nil result must not be overridden by a less precise native hint.
        return RP.Quest:GetUnitInfo(unit)
    end
    local related = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
    if Read(related, unit) == true then
        return { kind = "loot", isObject = true, source = "Blizzard" }
    end
end

function World:HideObjectMarker(plate, unit)
    local marker = plate and self.objectMarkers[plate]
    if not marker or (unit and marker.unit ~= unit) then return end
    marker.unit = nil
    marker:Hide()
    if self.anchor == plate then self:PositionArrow() end
end

function World:PaintObjectMarker(unit, info)
    local plate = self.objects[unit]
    if not plate then return end
    if not SafeFrame(plate) or NamePlate(unit) ~= plate or not IsObject(unit) then
        self.objects[unit] = nil
        self:HideObjectMarker(plate, unit)
        return
    end
    if not ObjectMarkersWanted() or IsSecret(info) or type(info) ~= "table"
        or (canaccesstable and not canaccesstable(info)) or IsSecret(info.kind) then
        self:HideObjectMarker(plate, unit)
        return
    end
    local marker = self.objectMarkers[plate]
    if not marker then
        marker = CreateFrame("Frame", nil, plate)
        marker:SetSize(28, 28)
        marker:SetPoint("BOTTOM", plate, "TOP", 0, 4)
        local level = Read(plate.GetFrameLevel, plate)
        if type(level) == "number" then marker:SetFrameLevel(level + 8) end
        marker:EnableMouse(false)
        marker.icon = marker:CreateTexture(nil, "ARTWORK")
        marker.icon:SetAllPoints(marker)
        self.objectMarkers[plate] = marker
    end
    marker.unit = unit
    marker.icon:SetTexture(RP.media .. (info.kind == "loot" and "QuestLoot" or "Quest"))
    marker:Show()
    if self.anchor == plate then self:PositionArrow() end
end

function World:RefreshObjectMarkers()
    for unit in pairs(self.objects) do
        self:PaintObjectMarker(unit, ObjectMarkersWanted() and self:GetQuestInfo(unit) or nil)
    end
end

function World:DiscoverObjects()
    local plates = Read(C_NamePlate and C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" or (canaccesstable and not canaccesstable(plates)) then return end
    for _, plate in pairs(plates) do
        if SafeFrame(plate) then
            local unit = Read(plate.GetUnit, plate)
            if type(unit) ~= "string" then unit = plate.namePlateUnitToken end
            if not IsSecret(unit) and type(unit) == "string" and IsObject(unit) then
                self.objects[unit] = plate
            end
        end
    end
end

function World:Refresh()
    if not self.initialized then return end
    if not ArrowWanted() then
        self:HideArrow()
        self.status = "Quest object arrow off"
        return
    end
    if InCombat() then
        self:HideArrow()
        self.status = "Quest object arrow resumes outside combat"
        return
    end
    local unit, plate = self:ResolveObject()
    if not unit then
        self:SetGate(false)
        self:HideArrow()
        self.status = "No readable quest object as interaction target"
        return
    end
    local info = self:GetQuestInfo(unit)
    local relevant = type(info) == "table"
    self:SetGate(relevant)
    if not relevant then
        self:HideArrow()
        self.status = "Interaction target is not a confirmed quest object"
    elseif not plate then
        self:HideArrow()
        self.status = "Waiting for the client object marker"
        -- A bounded retry also covers a late nameplate event. No world polling.
        if not self.retriedAnchor then
            self.retriedAnchor = true
            self:ScheduleRefresh(0.15)
        end
    else
        self:AttachArrow(plate, unit)
    end
end

function World:ScheduleRefresh(delay)
    if not self.initialized or self.refreshScheduled then return end
    self.refreshScheduled = true
    local callback = function()
        self.refreshScheduled = false
        self:Refresh()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.06, callback)
    else
        self.delay = delay or 0.06
        self.timer:SetScript("OnUpdate", function(frame, elapsed)
            self.delay = self.delay - elapsed
            if self.delay <= 0 then
                frame:Hide()
                frame:SetScript("OnUpdate", nil)
                callback()
            end
        end)
        self.timer:Show()
    end
end

function World:RequestObject()
    if not ArrowWanted() then return end
    self.retriedAnchor = false
    if RP.Quest and RP.Quest.Forget then RP.Quest:Forget(SOFT) end
    if RP.Quest and RP.Quest.Request then RP.Quest:Request(SOFT) end
    self:ScheduleRefresh()
end

function World:UpdateSettings()
    if not self.initialized or not RP.db then return end
    self:RefreshObjectMarkers()
    local outline, arrow = OutlineWanted(), ArrowWanted()
    if InCombat() then
        self.pendingSettings = true
        if not arrow then self:HideArrow() end
        return
    end
    self.pendingSettings = nil
    if self.appliedOutline ~= outline then
        if outline then
            self:ApplyGroup(OUTLINE_SETTINGS, "outline")
            self.appliedOutline = outline
        else
            if self:RestoreGroup("outline") then self.appliedOutline = outline end
        end
    end
    if self.appliedArrow ~= arrow then
        if arrow then
            self:ApplyGroup(INTERACT_SETTINGS, "arrow")
            self:RequestObject()
            self.appliedArrow = arrow
        else
            self:HideArrow()
            if self:RestoreGroup("arrow") then self.appliedArrow = arrow end
        end
    end
    self:ScheduleRefresh()
end

function World:RestoreCVars()
    -- This is also suitable for the addon's global restore/reset command.
    if RP.db then
        RP.db.worldHighlight, RP.db.worldArrow = false, false
    end
    self:HideArrow()
    if InCombat() then
        self.pendingSettings = true
        return false
    end
    local outline = self:RestoreGroup("outline")
    local arrow = self:RestoreGroup("arrow")
    self.appliedOutline, self.appliedArrow = false, false
    return outline and arrow
end

function World:OnQuestInfoChanged(unit, info)
    if not self.initialized or IsSecret(unit) or type(unit) ~= "string" then return end
    self:PaintObjectMarker(unit, info)
    if unit == SOFT or (self.anchorToken and unit == self.anchorToken) then
        self:ScheduleRefresh()
    end
end

function World:OnEvent(event, unit)
    if event == "PLAYER_SOFT_INTERACT_CHANGED" then
        self:HideArrow()
        self:RequestObject()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) ~= "string" or IsSecret(unit) then return end
        local plate = NamePlate(unit)
        local object = plate and IsObject(unit)
        local previous = self.objects[unit]
        if previous and previous ~= plate then self:HideObjectMarker(previous, unit) end
        local marker = plate and self.objectMarkers[plate]
        if marker and marker.unit and (marker.unit ~= unit or not object) then
            self.objects[marker.unit] = nil
            self:HideObjectMarker(plate)
        end
        self.objects[unit] = object and plate or nil
        if object then
            self:PaintObjectMarker(unit, ObjectMarkersWanted() and self:GetQuestInfo(unit) or nil)
            if ArrowWanted() then self:ScheduleRefresh() end
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) ~= "string" or IsSecret(unit) then return end
        local plate = self.objects[unit]
        self.objects[unit] = nil
        self:HideObjectMarker(plate, unit)
        if unit == self.anchorToken or (plate and plate == self.anchor) then
            self:HideArrow()
            self:ScheduleRefresh()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:HideArrow()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UpdateSettings()
        self:RequestObject()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:HideArrow()
        for token, plate in pairs(self.objects) do
            self:HideObjectMarker(plate, token)
            self.objects[token] = nil
        end
        self:DiscoverObjects()
        self:UpdateSettings()
        self:RequestObject()
    elseif event == "CVAR_UPDATE" then
        if not self.writing and type(unit) == "string" and not IsSecret(unit)
            and unit:lower():find("softtarget", 1, true) then
            self:ScheduleRefresh()
        end
    else
        -- Quest-module invalidation runs in the same event dispatch; the small
        -- deferred refresh sees its new cache rather than the previous quest log.
        self:ScheduleRefresh()
    end
end

function World:GetStatus()
    return self.status or "Quest object assistance ready"
end

function World:Initialize()
    if self.initialized then return end
    self.initialized = true
    self.objects, self.unsupported = {}, {}
    self.objectMarkers = setmetatable({}, {__mode = "k"})
    self.timer = CreateFrame("Frame")
    self.timer:Hide()
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_SOFT_INTERACT_CHANGED",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
        "CVAR_UPDATE",
    }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    self:DiscoverObjects()
    self:UpdateSettings()
end
