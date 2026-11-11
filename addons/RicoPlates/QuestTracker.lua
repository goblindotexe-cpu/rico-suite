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
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    return text
end

local function SetText(text, value)
    if text.ricoValue ~= value then
        text.ricoValue = value
        text:SetText(value)
    end
end

local function DistanceLabel(yards)
    if not yards then return "—" end
    local meters = yards * 0.9144
    local roundedMeters = math.floor(meters + 0.5)
    if roundedMeters >= 1000 then return ("%.1f km"):format(meters / 1000) end
    return ("%d m"):format(roundedMeters)
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

local function PaintRow(row, hover)
    local r, g, b = unpack(T.colors.accent)
    if hover then
        row.surface:SetVertexColor(0.035 + 0.10 * r, 0.045 + 0.10 * g, 0.043 + 0.10 * b, 0.82)
    else
        row.surface:SetVertexColor(0.013, 0.024, 0.021, 0.56)
    end
    local alpha = row.complete and 0.96 or hover and 0.72 or 0.26
    row.marker:SetColorTexture(r, g, b, alpha)
end

local function AddSmoke(frame)
    local path = RP.media .. "QuestTrackerSmoke.tga"
    local smoke = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    smoke:SetTexture(path)
    smoke:SetPoint("TOPLEFT", -24, 12)
    smoke:SetPoint("BOTTOMRIGHT", 10, -24)
    smoke:SetVertexColor(0.68, 0.83, 0.76, 0.55)

    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetTexture(path)
    glow:SetAllPoints(smoke)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.34, 1, 0.64)

    local pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetTarget(glow)
    alpha:SetFromAlpha(0.28)
    alpha:SetToAlpha(0.58)
    alpha:SetDuration(1.8)
    alpha:SetSmoothing("IN_OUT")
    frame:HookScript("OnShow", function() pulse:Play() end)
    frame:HookScript("OnHide", function() pulse:Stop() end)
end

local function ScrollWheel(_, delta)
    Q:SetScrollOffset((Q.scrollOffset or 0) - delta)
end

function Q:Build()
    if self.frame then return end
    local frame = CreateFrame("Frame", "RicoPlatesCompactQuestTracker", UIParent)
    self.frame = frame
    frame:SetSize(WIDTH, HEADER_HEIGHT)
    frame:Hide()
    T:Panel(frame)
    AddSmoke(frame)

    local headerRule = frame:CreateTexture(nil, "BORDER")
    headerRule:SetPoint("TOPLEFT", 6, -29)
    headerRule:SetPoint("TOPRIGHT", -6, -29)
    headerRule:SetHeight(1)
    headerRule:SetColorTexture(0.31, 0.69, 0.53, 0.52)
    if CreateColor and headerRule.SetGradient then
        headerRule:SetGradient("HORIZONTAL", CreateColor(0.36, 0.89, 0.66, 0.69), CreateColor(0.24, 0.64, 0.46, 0.19))
    end

    local title = Text(frame, 15, T.colors.text)
    title:SetPoint("TOPLEFT", 14, -6)
    title:SetText("Quests")
    local countSurface = frame:CreateTexture(nil, "ARTWORK")
    countSurface:SetPoint("TOPRIGHT", -7, -6)
    countSurface:SetSize(67, 18)
    countSurface:SetColorTexture(0.032, 0.12, 0.086, 0.75)
    self.count = Text(frame, 11, T.colors.mint, "RIGHT")
    self.count:SetPoint("RIGHT", countSurface, "RIGHT", -7, 0)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", ScrollWheel)
    local scrollbar = CreateFrame("Slider", nil, frame)
    self.scrollbar = scrollbar
    scrollbar:SetPoint("TOPRIGHT", -5, -HEADER_HEIGHT)
    scrollbar:SetPoint("BOTTOMRIGHT", -5, 7)
    scrollbar:SetWidth(9)
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetValueStep(1)
    scrollbar:SetObeyStepOnDrag(true)
    scrollbar:EnableMouse(true)
    scrollbar:EnableMouseWheel(true)
    scrollbar:SetScript("OnMouseWheel", ScrollWheel)
    scrollbar:SetScript("OnValueChanged", function(slider, value)
        if not slider.updatingRange then Q:SetScrollOffset(value) end
    end)
    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP")
    track:SetPoint("BOTTOM")
    track:SetWidth(2)
    track:SetColorTexture(0.18, 0.34, 0.27, 0.7)
    scrollbar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = scrollbar:GetThumbTexture()
    thumb:SetSize(5, 20)
    thumb:SetVertexColor(0.43, 0.85, 0.63, 0.9)
    scrollbar:Hide()

    for index = 1, ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(WIDTH - 22, ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 6, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)
        row.surface = T:Fill(row)
        row.marker = row:CreateTexture(nil, "ARTWORK")
        row.marker:SetPoint("TOPLEFT", 0, -5)
        row.marker:SetPoint("BOTTOMLEFT", 0, 5)
        row.marker:SetWidth(2)
        PaintRow(row, false)
        row.title = Text(row, 12, T.colors.text)
        row.title:SetPoint("TOPLEFT", 10, -4)
        row.title:SetWidth(WIDTH - 123)
        row.distance = Text(row, 11, T.colors.mint, "RIGHT")
        row.distance:SetPoint("TOPRIGHT", -34, -5)
        row.distance:SetWidth(52)
        row.detail = Text(row, 10, T.colors.muted)
        row.detail:SetPoint("BOTTOMLEFT", 10, 5)
        row.detail:SetWidth(WIDTH - 61)
        if RP.QuestTrackerItems then
            row.item = RP.QuestTrackerItems:Create(row, ScrollWheel)
            if row.item then row.item:SetPoint("RIGHT", -5, 0) end
        end
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", ScrollWheel)
        row:SetScript("OnClick", OpenQuest)
        row:SetScript("OnEnter", function(button)
            button.hover = true
            PaintRow(button, true)
            ShowTooltip(button)
        end)
        row:SetScript("OnLeave", function(button)
            button.hover = nil
            PaintRow(button, false)
            HideTooltip(button)
        end)
        row:SetScript("OnHide", function(button)
            button.hover = nil
            PaintRow(button, false)
            HideTooltip(button)
        end)
        row:Hide()
        self.rows[index] = row
    end
    frame:HookScript("OnHide", function()
        for _, row in ipairs(self.rows) do HideTooltip(row) end
    end)
end

function Q:RenderRows()
    for index, row in ipairs(self.rows) do
        local quest = self.quests[index + self.scrollOffset]
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
                row.detail:SetTextColor(unpack(quest.complete and T.colors.mint or T.colors.muted))
                PaintRow(row, row.hover)
            end
            local distanceKnown = quest.distance ~= nil
            if row.distanceKnown ~= distanceKnown then
                row.distanceKnown = distanceKnown
                row.distance:SetTextColor(unpack(distanceKnown and T.colors.mint or T.colors.muted))
            end
            if tooltipChanged and GameTooltip and GameTooltip:IsShown() and GameTooltip:IsOwned(row) then
                ShowTooltip(row)
            end
        end
        if row:IsShown() ~= (quest ~= nil) then row:SetShown(quest ~= nil) end
        if row.item then RP.QuestTrackerItems:Update(row.item, quest) end
    end
end

function Q:SetScrollOffset(value)
    if not self.attached then return end
    local offset = math.max(0, math.min(self.scrollMax, math.floor(value + 0.5)))
    if self.scrollOffset == offset then return end
    self.scrollOffset = offset
    if self.scrollbar:GetValue() ~= offset then self.scrollbar:SetValue(offset) end
    self:RenderRows()
end

function Q:Refresh()
    if not self.attached then return end
    local quests, total = RP.QuestTrackerData:Refresh()
    self.quests = quests
    local frame = self.frame
    local count = math.min(#quests, ROWS)
    local visible = total > 0
    local height = HEADER_HEIGHT + count * ROW_HEIGHT + (count > 0 and 5 or 0)
    if frame:GetHeight() ~= height then frame:SetHeight(height) end
    SetText(self.count, ("%d active"):format(total))

    local scrollbar = self.scrollbar
    local scrollMax = math.max(0, #quests - ROWS)
    self.scrollOffset = math.min(self.scrollOffset or 0, scrollMax)
    if self.scrollMax ~= scrollMax then
        self.scrollMax = scrollMax
        scrollbar.updatingRange = true
        scrollbar:SetMinMaxValues(0, math.max(1, scrollMax))
        scrollbar.updatingRange = nil
        scrollbar:SetShown(scrollMax > 0)
    end
    if scrollbar:GetValue() ~= self.scrollOffset then scrollbar:SetValue(self.scrollOffset) end
    self:RenderRows()
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
            self.scrollOffset = 0
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
