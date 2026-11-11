local _, RP = ...
local T = RP.Theme
local Q = { rows = {} }
RP.QuestTracker = Q

local ROWS, WIDTH, ROW_HEIGHT, HEADER_HEIGHT = 7, 292, 36, 33
local unpack = unpack or table.unpack

local function Text(parent, size, color, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(T.font, size, "")
    text:SetTextColor(unpack(color))
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

local function SetText(text, value)
    if text.ricoValue ~= value then
        text.ricoValue = value
        text:SetText(value)
    end
end

local function DistanceLabel(distance)
    if not distance then return "—" end
    if distance >= 1000 then return ("%.1fk yd"):format(distance / 1000) end
    return ("%d yd"):format(math.floor(distance + 0.5))
end

local function HideTooltip(row)
    if GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function ShowTooltip(row)
    local quest, tooltip = row.quest, GameTooltip
    if not quest or not tooltip then return end
    tooltip:SetOwner(row, "ANCHOR_LEFT")
    tooltip:ClearLines()
    tooltip:SetText(quest.title)
    if quest.complete then tooltip:AddLine("Ready to turn in", 0.42, 0.92, 0.68) end
    for _, objective in ipairs(quest.objectives or {}) do
        local color = objective.finished and T.colors.muted or T.colors.text
        tooltip:AddLine(objective.text, color[1], color[2], color[3], true)
    end
    tooltip:AddLine(quest.distance and ("Distance: " .. DistanceLabel(quest.distance)) or "Distance unavailable",
        0.66, 0.79, 0.74)
    tooltip:Show()
end

local function OpenQuest(row)
    local quest = row.quest
    if quest and type(QuestMapFrame_OpenToQuestDetails) == "function" then
        pcall(QuestMapFrame_OpenToQuestDetails, quest.id)
    end
end

local function ObjectiveSummary(quest)
    if quest.complete then return "Ready to turn in" end
    local objectives = quest.objectives or {}
    for _, objective in ipairs(objectives) do
        if not objective.finished then return objective.text end
    end
    return objectives[1] and objectives[1].text or ""
end

function Q:Build()
    if self.frame then return end
    local frame = CreateFrame("Frame", "RicoPlatesCompactQuestTracker", UIParent)
    self.frame = frame
    frame:SetSize(WIDTH, HEADER_HEIGHT)
    frame:Hide()
    T:Panel(frame)

    local title = Text(frame, 14, T.colors.text)
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("Quests")
    self.count = Text(frame, 11, T.colors.mint, "RIGHT")
    self.count:SetPoint("TOPRIGHT", -12, -11)

    for index = 1, ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(WIDTH - 12, ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 6, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)
        T:Panel(row)
        row.title = Text(row, 11, T.colors.text)
        row.title:SetPoint("TOPLEFT", 8, -5)
        row.title:SetWidth(WIDTH - 86)
        row.distance = Text(row, 10, T.colors.mint, "RIGHT")
        row.distance:SetPoint("TOPRIGHT", -8, -6)
        row.distance:SetWidth(58)
        row.detail = Text(row, 10, T.colors.muted)
        row.detail:SetPoint("BOTTOMLEFT", 8, 5)
        row.detail:SetWidth(WIDTH - 28)
        row:SetScript("OnClick", OpenQuest)
        row:SetScript("OnEnter", function(button)
            T:Row(button, false, true)
            ShowTooltip(button)
        end)
        row:SetScript("OnLeave", function(button)
            T:Row(button, false, false)
            HideTooltip(button)
        end)
        row:SetScript("OnHide", HideTooltip)
        row:Hide()
        self.rows[index] = row
    end
    frame:SetScript("OnHide", function()
        for _, row in ipairs(self.rows) do HideTooltip(row) end
    end)
end

function Q:Refresh()
    if not self.attached then return end
    local quests, total = RP.QuestTrackerData:Refresh()
    local frame = self.frame
    local count = math.min(#quests, ROWS)
    local visible = total > 0
    local height = HEADER_HEIGHT + count * ROW_HEIGHT + (count > 0 and 5 or 0)
    if frame:GetHeight() ~= height then frame:SetHeight(height) end
    SetText(self.count, ("%d active"):format(total))
    for index, row in ipairs(self.rows) do
        local quest = quests[index]
        local previous = row.quest
        row.quest = quest
        if quest then
            local distance = DistanceLabel(quest.distance)
            local detail = ObjectiveSummary(quest)
            local tooltipChanged = previous ~= quest or row.distance.ricoValue ~= distance
            SetText(row.title, quest.title)
            SetText(row.distance, distance)
            SetText(row.detail, detail)
            if row.complete ~= quest.complete then
                row.complete = quest.complete
                row.title:SetTextColor(unpack(quest.complete and T.colors.mint or T.colors.text))
            end
            if tooltipChanged and GameTooltip and GameTooltip:IsShown() and GameTooltip:IsOwned(row) then
                ShowTooltip(row)
            end
        end
        if row:IsShown() ~= (quest ~= nil) then row:SetShown(quest ~= nil) end
    end
    if frame:IsShown() ~= visible then frame:SetShown(visible) end
    RP.QuestTrackerNative:LayoutChanged(frame)
end

local function Tick(frame, elapsed)
    frame.elapsed = (frame.elapsed or 0) + elapsed
    if frame.elapsed < 0.6 then return end
    frame.elapsed = 0
    Q:Refresh()
end

function Q:UpdateSettings()
    if not self.events or not RP.QuestTrackerData or not RP.QuestTrackerNative then return end
    local enabled = RP.db.enabled and RP.db.compactQuestTracker
    if not enabled then
        self.questieNotice = nil
        if self.frame and RP.QuestTrackerNative:Detach(self.frame) then
            self.attached = nil
            self.frame:SetScript("OnUpdate", nil)
            self.frame:Hide()
        end
        return
    end
    self:Build()
    local attached, reason = RP.QuestTrackerNative:Attach(self.frame)
    if reason == "combat" and self.attached then return end
    self.attached = attached
    if attached then
        self.questieNotice = nil
        self.frame.elapsed = 0
        self.frame:SetScript("OnUpdate", Tick)
        self:Refresh()
    else
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
        if reason == "questie" and not self.questieNotice then
            self.questieNotice = true
            RP:Print("Turn off Questie's Tracker option to use the compact quest tracker. Questie map icons can stay on.")
        end
    end
end

function Q:Initialize()
    if self.events then return end
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED",
        "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
        "QUEST_POI_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
    }) do pcall(events.RegisterEvent, events, event) end
    events:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" and addon ~= "Blizzard_ObjectiveTracker" and addon ~= "Questie" and addon ~= "QuestieDB" then return end
        RP.QuestTrackerData:Invalidate()
        if event == "PLAYER_ENTERING_WORLD" or event == "ADDON_LOADED" then
            if C_Timer and C_Timer.After then C_Timer.After(0, function() Q:UpdateSettings() end)
            else Q:UpdateSettings() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            Q:UpdateSettings()
        elseif Q.attached then
            Q:Refresh()
        end
    end)
end
