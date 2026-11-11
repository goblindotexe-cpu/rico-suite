local _, RP = ...
local T = RP.Theme
local Q = { rows = {}, scrollOffsets = {} }
RP.QuestTracker = Q

local ROWS, WIDTH, ROW_HEIGHT, HEADER_HEIGHT = 7, 292, 36, 38
local TAB_SPACE = 28
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
    if quest.dungeon then tooltip:AddLine("Dungeon quest", 0.94, 0.75, 0.43) end
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
    local opacity = Q.panelOpacity or 1
    if hover then
        row.surface:SetVertexColor(0.032 + 0.10 * r, 0.046 + 0.10 * g, 0.044 + 0.10 * b, 0.80 * opacity)
    elseif row.alternate then
        row.surface:SetVertexColor(0.041, 0.068, 0.060, 0.58 * opacity)
    else
        row.surface:SetVertexColor(0.021, 0.039, 0.033, 0.56 * opacity)
    end
    local alpha = row.complete and 0.95 or hover and 0.70 or 0.34
    row.marker:SetColorTexture(r, g, b, alpha)
end

function Q:ApplyAppearance()
    if not self.header then return end
    local db, defaults = RP.db, RP.defaults
    local opacity = (db.questTrackerOpacity or defaults.questTrackerOpacity) / 100
    local glow = db.questTrackerGlow ~= false and (db.questTrackerGlowStrength or defaults.questTrackerGlowStrength) / 100 or 0
    self.panelOpacity = opacity
    self.header.ricoBackground:SetVertexColor(0.047, 0.081, 0.070, opacity)
    self.body.ricoBackground:SetVertexColor(0.027, 0.047, 0.042, opacity)
    if self.headerGlow then self.headerGlow:SetStrength(glow) end
    if self.bodyGlow then self.bodyGlow:SetStrength(glow) end
    for _, row in ipairs(self.rows) do PaintRow(row, row.hover) end
end

local function JoinPanels(joined)
    joined = joined == true and Q.body:IsShown()
    if Q.joined == joined then return end
    Q.joined = joined
    if Q.headerGlow then Q.headerGlow:SetBottomFrame(joined and Q.body or nil) end
    if Q.bodyGlow then Q.bodyGlow:SetSuppressed(joined) end
    Q.body.ricoBorder[1]:SetShown(not joined)
end

local function SetHeaderAdjacent(_, adjacent)
    Q.headerAdjacent = adjacent
    JoinPanels(adjacent)
end

local function IntegrateHeader(frame, integrated, rightReserve)
    Q.headerIntegrated = integrated
    Q.title:SetText(integrated and "All Objectives" or "Quests")
    local reserved = rightReserve or 0
    if Q.settings then Q.settings:SetPoint("RIGHT", Q.header, "RIGHT", -reserved - 6, 0) end
    if Q.gpsButton then
        if Q.settings then Q.gpsButton:SetPoint("RIGHT", Q.settings, "LEFT", -4, 0)
        else Q.gpsButton:SetPoint("RIGHT", Q.header, "RIGHT", -reserved - 6, 0) end
    end
    local button = Q.gpsButton or Q.settings
    if button then Q.countSurface:SetPoint("RIGHT", button, "LEFT", -5, 0)
    else Q.countSurface:SetPoint("RIGHT", Q.header, "RIGHT", -reserved - 8, 0) end
    Q.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, integrated and 0 or -HEADER_HEIGHT)
    if not integrated then JoinPanels(true) end
end

local function ScrollWheel(_, delta)
    Q:SetScrollOffset((Q.scrollOffset or 0) - delta)
end

local function CreateTab(footer, key, label, anchor)
    local button = CreateFrame("Button", nil, footer)
    button:SetSize((WIDTH - 18) / 2, 23)
    button:SetPoint(anchor, footer, anchor)
    button.label = Text(button, 11, T.colors.text, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(label)
    T:Button(button)
    button:SetScript("OnClick", function() Q:SelectTab(key) end)
    return button
end

local function CreateGPSButton(header)
    local button = CreateFrame("Button", nil, header)
    button:SetSize(32, 20)
    button.ricoLabelColor = T.colors.mint
    button.label = Text(button, 10, T.colors.mint, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText("GPS")
    T:Button(button)
    button:SetScript("OnClick", function(self)
        HideTooltip(self)
        RP.QuestRouteUI:Show()
    end)
    button:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:SetText("Quest routes")
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", HideTooltip)
    button:HookScript("OnHide", HideTooltip)
    return button
end

function Q:Build()
    if self.frame then return end
    local frame = CreateFrame("Frame", "RicoPlatesCompactQuestTracker", UIParent)
    self.frame = frame
    frame:SetSize(WIDTH, HEADER_HEIGHT)
    frame:Hide()
    local header = CreateFrame("Frame", nil, frame)
    header:SetSize(WIDTH, HEADER_HEIGHT)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
    self.header, frame.ricoHeader = header, header
    frame.ricoSetHeaderIntegrated, frame.ricoSetHeaderAdjacent = IntegrateHeader, SetHeaderAdjacent
    local body = CreateFrame("Frame", nil, frame)
    self.body = body
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    T:Panel(header)
    T:Panel(body)
    if RP.QuestTrackerGlow then
        self.headerGlow = RP.QuestTrackerGlow:Create(header)
        self.bodyGlow = RP.QuestTrackerGlow:Create(body)
    end

    local headerRule = header:CreateTexture(nil, "BORDER", nil, 1)
    headerRule:SetPoint("TOPLEFT", 1, -1)
    headerRule:SetPoint("TOPRIGHT", -1, -1)
    headerRule:SetHeight(1)
    headerRule:SetColorTexture(0.32, 0.68, 0.51, 0.72)
    if CreateColor and headerRule.SetGradient then
        headerRule:SetGradient("HORIZONTAL", CreateColor(0.42, 0.88, 0.67, 0.80), CreateColor(0.23, 0.54, 0.40, 0.30))
    end

    local badge = header:CreateTexture(nil, "ARTWORK")
    badge:SetPoint("LEFT", 12, 0)
    badge:SetSize(5, 5)
    badge:SetColorTexture(0.45, 0.85, 0.66, 0.94)
    badge:SetRotation(math.pi / 4)
    self.title = Text(header, 14, T.colors.text)
    self.title:SetPoint("LEFT", 23, 0)
    self.countSurface = header:CreateTexture(nil, "ARTWORK")
    self.countSurface:SetSize(62, 20)
    self.countSurface:SetColorTexture(0.064, 0.157, 0.123, 0.82)
    self.count = Text(header, 11, T.colors.mint, "CENTER")
    self.count:SetPoint("CENTER", self.countSurface, "CENTER")
    self.title:SetPoint("RIGHT", self.countSurface, "LEFT", -6, 0)
    if RP.QuestTrackerSettings then self.settings = RP.QuestTrackerSettings:Create(self, header) end
    if RP.QuestRouteUI then self.gpsButton = CreateGPSButton(header) end
    IntegrateHeader(frame, false)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", ScrollWheel)
    header:EnableMouseWheel(true)
    header:SetScript("OnMouseWheel", ScrollWheel)
    local scrollbar = CreateFrame("Slider", nil, body)
    self.scrollbar = scrollbar
    scrollbar:SetPoint("TOPRIGHT", -5, -4)
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

    local footer = CreateFrame("Frame", nil, body)
    footer:SetSize(WIDTH - 12, 23)
    footer:SetPoint("BOTTOM", body, "BOTTOM", 0, 5)
    footer:Hide()
    self.footer = footer
    self.tabs = {
        quests = CreateTab(footer, "quests", "Quests", "LEFT"),
        dungeons = CreateTab(footer, "dungeons", "Dungeons", "RIGHT"),
    }

    for index = 1, ROWS do
        local row = CreateFrame("Button", nil, body)
        row:SetSize(WIDTH - 22, ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 6, -3 - (index - 1) * ROW_HEIGHT)
        row.alternate = index % 2 == 0
        row.surface = T:Fill(row)
        local rowRule = row:CreateTexture(nil, "BORDER")
        rowRule:SetPoint("BOTTOMLEFT", 1, 0)
        rowRule:SetPoint("BOTTOMRIGHT", -1, 0)
        rowRule:SetHeight(1)
        rowRule:SetColorTexture(0.14, 0.26, 0.21, 0.42)
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
    self:ApplyAppearance()
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
    self.scrollOffsets[self.tab] = offset
    if self.scrollbar:GetValue() ~= offset then self.scrollbar:SetValue(offset) end
    self:RenderRows()
end

function Q:RenderView()
    local groups = self.questGroups
    local quests = groups[self.tab]
    self.quests = quests
    local frame = self.frame
    local count = math.min(#quests, ROWS)
    local visible = self.total > 0
    local showTabs = #groups.dungeons > 0
    local tabSpace = showTabs and TAB_SPACE or 0
    local headerSpace = self.headerIntegrated and 0 or HEADER_HEIGHT
    local height = math.max(1, headerSpace + count * ROW_HEIGHT + (count > 0 and 5 or 0) + tabSpace)
    if self.body:IsShown() ~= (count > 0) then self.body:SetShown(count > 0) end
    JoinPanels(not self.headerIntegrated or self.headerAdjacent)
    if frame:GetHeight() ~= height then frame:SetHeight(height) end

    local scrollbar = self.scrollbar
    if self.footer:IsShown() ~= showTabs then
        self.footer:SetShown(showTabs)
        scrollbar:SetPoint("BOTTOMRIGHT", -5, 7 + tabSpace)
    end
    if showTabs then
        for key, button in pairs(self.tabs) do
            if button.selected ~= (self.tab == key) then
                button.selected = self.tab == key
                T:PaintButton(button)
            end
            if button:IsEnabled() ~= (#groups[key] > 0) then button:SetEnabled(#groups[key] > 0) end
        end
    end

    local scrollMax = math.max(0, #quests - ROWS)
    self.scrollOffset = math.min(self.scrollOffsets[self.tab] or 0, scrollMax)
    self.scrollOffsets[self.tab] = self.scrollOffset
    scrollbar.updatingRange = true
    if self.scrollMax ~= scrollMax then
        self.scrollMax = scrollMax
        scrollbar:SetMinMaxValues(0, math.max(1, scrollMax))
        scrollbar:SetShown(scrollMax > 0)
    end
    if scrollbar:GetValue() ~= self.scrollOffset then scrollbar:SetValue(self.scrollOffset) end
    scrollbar.updatingRange = nil
    self:RenderRows()
    if frame:IsShown() ~= visible then frame:SetShown(visible) end
    RP.QuestTrackerNative:LayoutChanged(frame)
end

function Q:SelectTab(tab)
    if not self.attached or self.tab == tab or #self.questGroups[tab] == 0 then return end
    self.tab = tab
    self:RenderView()
end

function Q:Refresh()
    if not self.attached then return end
    local quests, total = RP.QuestTrackerData:Refresh()
    local groups = { quests = {}, dungeons = {} }
    for _, quest in ipairs(quests) do
        local group = quest.dungeon and groups.dungeons or groups.quests
        group[#group + 1] = quest
    end
    self.questGroups, self.total = groups, total
    if #groups.dungeons == 0 then
        self.tab = "quests"
    elseif #groups.quests == 0 then
        self.tab = "dungeons"
    else
        self.tab = self.tab or "quests"
    end
    SetText(self.count, ("%d active"):format(total))
    self:RenderView()
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
            self.tab = nil
            self.scrollOffset = 0
            self.scrollOffsets = {}
            self.frame:SetScript("OnUpdate", nil)
            self.frame:Hide()
        end
        return
    end
    self:Build()
    self:ApplyAppearance()
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
        "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
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
