-- Explicit quest selection; the route provider owns terrain routing and drawing.
local _, RP = ...
local T = RP.Theme
local U = { rows = {}, page = 1 }
RP.QuestRouteUI = U
local unpack = unpack or table.unpack

local function Number(value)
    return RP.Readable(value) and type(value) == "number" and value == value and value > 0 and value < math.huge
end
local function String(value)
    return RP.Readable(value) and type(value) == "string" and value or ""
end
local function Table(value)
    return RP.Readable(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
local function Text(parent, value, size, color)
    local fs = (parent.ricoForeground or parent):CreateFontString(nil, "OVERLAY")
    fs:SetFont(T.font, size or 11, ""); fs:SetTextColor(unpack(color or T.colors.text))
    fs:SetJustifyH("LEFT"); fs:SetText(value or "")
    return fs
end
local function Button(parent, label, width, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 28); button.background = T:Panel(button)
    button.label = Text(button, label); button.label:SetPoint("CENTER")
    button:SetScript("OnClick", callback); T:Button(button, button.background)
    return button
end

function U:GetQuests()
    local entries, seen = {}, {}
    local api = C_QuestLog
    local ok, count = Call(api and api.GetNumQuestLogEntries)
    if not ok or not Number(count) then return entries end
    for index = 1, math.min(250, math.floor(count)) do
        local got, info = Call(api.GetInfo, index)
        if got and Table(info) and RP.Readable(info.isHeader) and not info.isHeader
            and RP.Readable(info.isHidden) and not info.isHidden and Number(info.questID)
            and not seen[info.questID] then
            local title = String(info.title)
            if title ~= "" then
                seen[info.questID] = true
                entries[#entries + 1] = { id = info.questID, title = title }
            end
        end
    end
    return entries
end

function U:StartSelected()
    if not self.selectedID then self.notice = "Select a quest from your quest log first."
    elseif not RP.QuestRoutes then self.notice = "The walking-route provider is unavailable."
    else
        local ok, message = RP.QuestRoutes:StartQuest(self.selectedID)
        self.notice = not ok and message or nil
    end
    self:RefreshStatus()
end

function U:Stop()
    if RP.QuestRoutes then
        local ok, message = RP.QuestRoutes:Stop()
        self.notice = not ok and message or nil
    end
    self:RefreshStatus()
end

function U:StartMapPin()
    if RP.QuestRoutes and RP.QuestRoutes.StartMapPin then
        local ok, message = RP.QuestRoutes:StartMapPin()
        self.notice = not ok and message or nil
    else self.notice = "The walking-route provider is unavailable." end
    self:RefreshStatus()
end

function U:ShowDetails()
    if not self.detailsFrame then
        local frame = CreateFrame("Frame", "RicoPlatesNavigationDetails", UIParent)
        self.detailsFrame = frame
        frame:SetSize(720, 485); frame:SetPoint("CENTER"); frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        T:Window(frame)
        local title = Text(frame, "", 22, T.colors.mint)
        title:SetPoint("TOPLEFT", 24, -22); T:Title(title, "NAVIGATION STATUS")
        local subtitle = Text(frame, "Quest locations come from the game. Questie is optional.", 11, T.colors.muted)
        subtitle:SetPoint("TOPLEFT", 24, -57)
        self.detailsText = Text(frame, "", 11)
        self.detailsText:SetPoint("TOPLEFT", 24, -96); self.detailsText:SetWidth(672)
        self.detailsText:SetHeight(325); self.detailsText:SetJustifyV("TOP")
        self.detailsRefresh = Button(frame, "Refresh", 100, function() U:ShowDetails() end)
        self.detailsRefresh:SetPoint("BOTTOMLEFT", 24, 23)
        self.detailsClose = Button(frame, "Close", 100, function() frame:Hide() end)
        self.detailsClose:SetPoint("BOTTOMRIGHT", -24, 23)
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "RicoPlatesNavigationDetails" end
    end
    local details = RP.QuestRoutes and RP.QuestRoutes.GetDiagnostics and RP.QuestRoutes:GetDiagnostics()
    self.detailsText:SetText(String(details) ~= "" and details or "Navigation details are unavailable.")
    self.detailsFrame:Show()
end

function U:Build()
    if self.frame then return end
    local frame = CreateFrame("Frame", "RicoPlatesQuestRoutes", UIParent)
    self.frame = frame
    frame:SetSize(760, 580); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    T:Window(frame)
    local title = Text(frame, "", 23, T.colors.mint)
    title:SetPoint("TOPLEFT", 24, -22); T:Title(title, "QUEST ROUTES")
    local subtitle = Text(frame, "Game quest locations · walking routes · Questie optional", 11, T.colors.muted)
    subtitle:SetPoint("TOPLEFT", 24, -57)
    self.closeButton = Button(frame, "Close", 72, function() frame:Hide() end)
    self.closeButton:SetPoint("TOPRIGHT", -24, -29)
    self.status = Text(frame, "", 11, T.colors.mint)
    self.status:SetPoint("TOPLEFT", 24, -87); self.status:SetWidth(712); self.status:SetHeight(40); self.status:SetJustifyV("TOP")
    local heading = Text(frame, "Choose a quest from your quest log", 12)
    heading:SetPoint("TOPLEFT", 24, -134)
    for index = 1, 8 do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(712, 30); row:SetPoint("TOPLEFT", 24, -156 - (index - 1) * 34)
        row.background = T:Panel(row); T:Row(row, false, false)
        row.title = Text(row, "", 12); row.title:SetPoint("LEFT", 10, 0); row.title:SetWidth(595); row.title:SetWordWrap(false)
        row.ident = Text(row, "", 10, T.colors.muted); row.ident:SetPoint("RIGHT", -10, 0)
        row:SetScript("OnClick", function(self) if self.quest then U.selectedID = self.quest.id; U.notice = nil; U:Refresh() end end)
        row:SetScript("OnEnter", function(self) T:Row(self, self.quest and self.quest.id == U.selectedID, true) end)
        row:SetScript("OnLeave", function(self) T:Row(self, self.quest and self.quest.id == U.selectedID, false) end)
        self.rows[index] = row
    end
    self.empty = Text(frame, "Your quest log has no readable active quests.", 12, T.colors.muted)
    self.empty:SetPoint("TOPLEFT", 40, -179); self.empty:SetWidth(675)
    self.prevButton = Button(frame, "Previous", 85, function() U.page = math.max(1, U.page - 1); U:Refresh() end)
    self.prevButton:SetPoint("TOPLEFT", 24, -436)
    self.nextButton = Button(frame, "Next", 85, function() U.page = U.page + 1; U:Refresh() end)
    self.nextButton:SetPoint("TOPRIGHT", -24, -436)
    self.pageText = Text(frame, "", 10, T.colors.muted); self.pageText:SetPoint("TOP", 0, -445)
    self.selection = Text(frame, "", 11)
    self.selection:SetPoint("TOPLEFT", 24, -478); self.selection:SetWidth(712); self.selection:SetHeight(35); self.selection:SetJustifyV("TOP")
    self.startButton = Button(frame, "Navigate selected quest", 195, function() U:StartSelected() end)
    self.startButton:SetPoint("BOTTOMLEFT", 24, 27)
    self.pinButton = Button(frame, "Navigate map pin", 180, function() U:StartMapPin() end)
    self.pinButton:SetPoint("LEFT", self.startButton, "RIGHT", 12, 0)
    self.stopButton = Button(frame, "Stop my route", 155, function() U:Stop() end)
    self.stopButton:SetPoint("LEFT", self.pinButton, "RIGHT", 12, 0)
    self.detailsButton = Button(frame, "Details", 130, function() U:ShowDetails() end)
    self.detailsButton:SetPoint("LEFT", self.stopButton, "RIGHT", 12, 0)
    local credit = Text(frame, "Walking routes: Shortest Path Forever · unknown route coverage is reported.", 9, T.colors.muted)
    credit:SetPoint("BOTTOMLEFT", 24, 9)
    frame:SetScript("OnShow", function(self)
        U.elapsed = 0; U:Refresh()
        self:SetScript("OnUpdate", function(_, elapsed)
            U.elapsed = U.elapsed + elapsed
            if U.elapsed >= 0.25 then U.elapsed = 0; U:RefreshStatus() end
        end)
    end)
    frame:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    frame:Hide()
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "RicoPlatesQuestRoutes" end
end

function U:RefreshStatus()
    if not self.frame or not self.frame:IsShown() then return end
    local status = RP.QuestRoutes and RP.QuestRoutes:GetStatus() or {}
    self.status:SetText(String(status.message) ~= "" and status.message or "Walking-route provider is unavailable.")
    local selected
    for _, quest in ipairs(self.quests or {}) do if quest.id == self.selectedID then selected = quest end end
    self.selection:SetText(self.notice or (selected and ("Selected: " .. selected.title) or "Select a quest, then choose Navigate selected quest."))
    self.startButton:SetEnabled(selected ~= nil and status.ready == true)
    self.pinButton:SetEnabled(status.ready == true)
    self.stopButton:SetEnabled(status.active == true or Number(status.activeQuestID))
end

function U:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self.quests = self:GetQuests()
    local pages = math.max(1, math.ceil(#self.quests / 8))
    self.page = math.max(1, math.min(self.page, pages))
    for index, row in ipairs(self.rows) do
        row.quest = self.quests[(self.page - 1) * 8 + index]
        row:SetShown(row.quest ~= nil)
        if row.quest then row.title:SetText(row.quest.title); row.ident:SetText("ID " .. row.quest.id) end
        T:Row(row, row.quest and row.quest.id == self.selectedID, false)
    end
    self.empty:SetShown(#self.quests == 0)
    self.prevButton:SetEnabled(self.page > 1); self.nextButton:SetEnabled(self.page < pages)
    self.pageText:SetText(self.page .. " / " .. pages .. " · " .. #self.quests .. " active quests")
    self:RefreshStatus()
end

function U:Show()
    self:Build(); self.frame:Show(); self:Refresh()
end

U.events = CreateFrame("Frame")
U.events:RegisterEvent("QUEST_LOG_UPDATE")
U.events:SetScript("OnEvent", function() U:Refresh() end)
