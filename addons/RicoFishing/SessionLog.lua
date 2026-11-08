local _, F = ...
local L = { view = 0, page = 1 }
F.SessionLog = L

local HISTORY_LIMIT, IDLE_SECONDS, ROWS = 25, 15 * 60, 7
local unpack = unpack or table.unpack

local function Timestamp()
    local ok, now = F.Call(GetServerTime)
    if ok and F.Number(now) and now > 0 then return math.floor(now) end
    ok, now = F.Call(time)
    if ok and F.Number(now) and now > 0 then return math.floor(now) end
    return 0
end

local function Empty()
    return { items = {}, quantity = 0, loots = 0 }
end

local function Clean(raw)
    if type(raw) ~= "table" or type(raw.items) ~= "table" then return end
    local session = Empty()
    for id, count in pairs(raw.items) do
        if F.Number(id) and id > 0 and id == math.floor(id) and F.Number(count) and count >= 1 then
            local quantity = math.floor(count)
            session.items[id] = quantity
            session.quantity = session.quantity + quantity
        end
    end
    if session.quantity == 0 then return end
    session.loots = F.Number(raw.loots) and math.min(session.quantity, math.max(1, math.floor(raw.loots))) or 1
    session.started = F.Number(raw.started) and math.max(0, math.floor(raw.started)) or 0
    session.last = F.Number(raw.last) and math.max(session.started, math.floor(raw.last)) or session.started
    if F.PublicString(raw.zone) and raw.zone ~= "" then session.zone = raw.zone end
    return session
end

function L:Initialize()
    local old = type(RicoFishingLogDB) == "table" and RicoFishingLogDB or {}
    local history = {}
    if type(old.history) == "table" then
        for index = 1, HISTORY_LIMIT do
            local session = Clean(old.history[index])
            if session then history[#history + 1] = session end
        end
    end
    self.db = { history = history, current = Clean(old.current) or Empty() }
    RicoFishingLogDB, F.session = self.db, self.db.current
end

function L:Archive()
    local current = self.db.current
    if current.quantity == 0 then return false end
    local history = self.db.history
    table.insert(history, 1, current)
    history[HISTORY_LIMIT + 1] = nil
    if self.view > 0 then self.view = math.min(#history, self.view + 1) end
    self.db.current = Empty()
    F.session = self.db.current
    return true
end

function L:Reset()
    local archived = self:Archive()
    self.view, self.page = 0, 1
    self:Refresh()
    return archived
end

function L:Record(id, quantity, firstInWindow)
    local now = Timestamp()
    local current = self.db.current
    local archived
    if firstInWindow and current.last and now >= current.last + IDLE_SECONDS then
        archived = self:Archive()
        current = self.db.current
    end
    if not current.started then
        current.started = now
        local ok, zone = F.Call(GetRealZoneText or GetZoneText)
        if ok and F.PublicString(zone) and zone ~= "" then current.zone = zone end
    end
    current.last = math.max(now, current.last or current.started)
    current.items[id] = (current.items[id] or 0) + quantity
    current.quantity = current.quantity + quantity
    if firstInWindow then current.loots = current.loots + 1 end
    if self.view == 0 or archived then self:Refresh() end
end

function L:GetRate()
    local current = self.db.current
    if not current.started or current.started <= 0 then return end
    local elapsed = Timestamp() - current.started
    if elapsed >= 60 then return current.quantity * 3600 / elapsed end
end

local function Text(parent, size, color)
    local T = F.Theme
    local text = (parent.ricoForeground or parent):CreateFontString(nil, "OVERLAY")
    text:SetFont(T.font, size, "")
    text:SetTextColor(unpack(color or T.colors.text))
    text:SetJustifyH("LEFT")
    return text
end

local function Button(parent, label, width, click)
    local T = F.Theme
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 24)
    button:EnableMouse(true)
    local background = T:Panel(button)
    local caption = Text(button, 11)
    caption:SetPoint("CENTER")
    caption:SetText(label)
    button:SetScript("OnClick", click)
    T:Button(button, background)
    return button
end

local function DateLabel(timestamp)
    if not timestamp or timestamp <= 0 then return "Date unavailable" end
    local ok, result = F.Call(date, "%d %b %Y  %H:%M", timestamp)
    return ok and F.PublicString(result) and result or "Date unavailable"
end

local function ItemName(id)
    local entry = F:GetEntry(id)
    if entry and F.PublicString(entry.name) then return entry.name end
    local ok, name = F.Call(C_Item and C_Item.GetItemNameByID or GetItemInfo, id)
    if ok and F.PublicString(name) then return name end
    if C_Item and C_Item.RequestLoadItemDataByID and not L.requested[id] then
        L.requested[id] = true
        F.Call(C_Item.RequestLoadItemDataByID, id)
    end
    return "Item #" .. id
end

function L:Build()
    if self.frame then return end
    local T = F.Theme
    local frame = CreateFrame("Frame", "RicoFishingCatchLog", UIParent)
    self.frame, self.rows, self.requested = frame, {}, {}
    frame:SetSize(510, 447)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    T:Window(frame)
    local title = Text(frame, 23)
    title:SetPoint("TOPLEFT", 24, -22)
    T:Title(title, "CATCH LOG")
    local sub = Text(frame, 11, T.colors.muted)
    sub:SetPoint("TOPLEFT", 24, -57)
    sub:SetText("Confirmed fishing loot, grouped by session")
    local close = Button(frame, "Close", 62, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -24, -30)
    self.newer = Button(frame, "< Newer", 78, function() L.view = L.view - 1; L.page = 1; L:Refresh() end)
    self.newer:SetPoint("TOPLEFT", 22, -88)
    self.older = Button(frame, "Older >", 78, function() L.view = L.view + 1; L.page = 1; L:Refresh() end)
    self.older:SetPoint("TOPRIGHT", -22, -88)
    self.selection = Text(frame, 12, T.colors.mint)
    self.selection:SetPoint("TOP", 0, -94)
    self.summary = Text(frame, 11)
    self.summary:SetPoint("TOPLEFT", 24, -124)
    self.details = Text(frame, 10, T.colors.muted)
    self.details:SetPoint("TOPLEFT", 24, -142)
    self.details:SetWidth(462)
    self.details:SetWordWrap(false)
    for index = 1, ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(466, 28)
        row:SetPoint("TOPLEFT", 22, -163 - (index - 1) * 31)
        T:Panel(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(19, 19)
        row.icon:SetPoint("LEFT", 6, 0)
        row.name = Text(row, 11)
        row.name:SetPoint("LEFT", 32, 0)
        row.name:SetWidth(360)
        row.name:SetWordWrap(false)
        row.count = Text(row, 11, T.colors.mint)
        row.count:SetPoint("RIGHT", -10, 0)
        self.rows[index] = row
    end
    self.empty = Text(frame, 12, T.colors.muted)
    self.empty:SetPoint("TOPLEFT", 24, -175)
    self.empty:SetText("No catches yet. Loot a fish to start the session.")
    self.previousPage = Button(frame, "<", 27, function() L.page = L.page - 1; L:Refresh() end)
    self.previousPage:SetPoint("BOTTOMLEFT", 22, 40)
    self.nextPage = Button(frame, ">", 27, function() L.page = L.page + 1; L:Refresh() end)
    self.nextPage:SetPoint("LEFT", self.previousPage, "RIGHT", 48, 0)
    self.pages = Text(frame, 10, T.colors.muted)
    self.pages:SetPoint("CENTER", self.previousPage, "CENTER", 38, 0)
    self.reset = Button(frame, "End session", 112, function() L:Reset(); F:Refresh() end)
    self.reset:SetPoint("BOTTOMRIGHT", -22, 40)
    local help = Text(frame, 9, T.colors.muted)
    help:SetPoint("BOTTOMLEFT", 24, 17)
    help:SetText("A new catch after 15 minutes of inactivity starts a new session.")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(_, _, id, success)
        if F.Number(id) and L.requested[id] and success == true then L:Refresh() end
    end)
    frame:Hide()
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RicoFishingCatchLog" end
end

function L:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local history = self.db.history
    self.view = math.max(0, math.min(self.view, #history))
    local current = self.view == 0
    local session = current and self.db.current or history[self.view]
    self.selection:SetText(current and "Current session" or ("Past session %d/%d"):format(self.view, #history))
    self.newer:SetEnabled(not current)
    self.older:SetEnabled(self.view < #history)
    self.reset:SetEnabled(current and session.quantity > 0)
    self.summary:SetText(("%d %s · %d %s"):format(session.quantity, session.quantity == 1 and "item" or "items",
        session.loots, session.loots == 1 and "catch" or "catches"))
    self.details:SetText(session.quantity > 0 and (DateLabel(session.started)
        .. (session.zone and " · " .. session.zone or "")) or "")

    local items = {}
    for id, count in pairs(session.items) do items[#items + 1] = { id = id, count = count } end
    table.sort(items, function(a, b) return a.count > b.count or (a.count == b.count and a.id < b.id) end)
    local pageCount = math.max(1, math.ceil(#items / ROWS))
    self.page = math.max(1, math.min(self.page, pageCount))
    self.pages:SetText(("%d/%d"):format(self.page, pageCount))
    self.previousPage:SetEnabled(self.page > 1)
    self.nextPage:SetEnabled(self.page < pageCount)
    self.empty:SetShown(#items == 0)
    for index, row in ipairs(self.rows) do
        local item = items[(self.page - 1) * ROWS + index]
        row:SetShown(item ~= nil)
        if item then
            row.icon:SetTexture(F:GetIcon(item.id))
            row.name:SetText(ItemName(item.id))
            row.count:SetText("×" .. item.count)
        end
    end
end

function L:Toggle()
    if not self.db then return end
    self:Build()
    self.frame:SetShown(not self.frame:IsShown())
    self:Refresh()
end
