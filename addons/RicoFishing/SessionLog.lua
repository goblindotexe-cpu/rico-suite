local _, F = ...
local L = { view = 0, page = 1, requested = {} }
F.SessionLog = L

local HISTORY_LIMIT, RECENT_LIMIT, IDLE_SECONDS, ROWS = 25, 10, 15 * 60, 7
local unpack = unpack or table.unpack
local emptyRecent = {}
local ItemName

local function ItemID(id)
    return F.Number(id) and id > 0 and id == math.floor(id)
end

local function IsQuality(quality)
    return F.Number(quality) and quality >= 0 and quality <= 8 and quality == math.floor(quality)
end

local function ReadQuality(id)
    local ok, _, _, quality = F.Call(C_Item and C_Item.GetItemInfo or GetItemInfo, id)
    if ok and IsQuality(quality) then return quality end
end

local function RequestItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID and not L.requested[id] then
        L.requested[id] = true
        F.Call(C_Item.RequestLoadItemDataByID, id)
    end
end

local function Timestamp()
    local ok, now = F.Call(GetServerTime)
    if ok and F.Number(now) and now > 0 then return math.floor(now) end
    ok, now = F.Call(time)
    if ok and F.Number(now) and now > 0 then return math.floor(now) end
    return 0
end

local function Empty()
    return { items = {}, qualities = {}, quantity = 0, loots = 0 }
end

local function Clean(raw)
    if type(raw) ~= "table" or type(raw.items) ~= "table" then return end
    local session = Empty()
    for id, count in pairs(raw.items) do
        if ItemID(id) and F.Number(count) and count >= 1 then
            local quantity = math.floor(count)
            session.items[id] = quantity
            session.quantity = session.quantity + quantity
        end
    end
    if session.quantity == 0 then return end
    if type(raw.qualities) == "table" then
        for id, quality in pairs(raw.qualities) do
            if session.items[id] and IsQuality(quality) then session.qualities[id] = quality end
        end
    end
    session.loots = F.Number(raw.loots) and math.min(session.quantity, math.max(1, math.floor(raw.loots))) or 1
    session.started = F.Number(raw.started) and math.max(0, math.floor(raw.started)) or 0
    session.last = F.Number(raw.last) and math.max(session.started, math.floor(raw.last)) or session.started
    if F.PublicString(raw.zone) and raw.zone ~= "" then session.zone = raw.zone end
    return session
end

function L:Initialize()
    local old = type(RicoFishingLogDB) == "table" and RicoFishingLogDB or {}
    local history = {}
    local favorites = {}
    local recentCatches = {}
    if type(old.history) == "table" then
        for index = 1, HISTORY_LIMIT do
            local session = Clean(old.history[index])
            if session then history[#history + 1] = session end
        end
    end
    if type(old.favorites) == "table" then
        for id, selected in pairs(old.favorites) do
            if ItemID(id) and selected == true then favorites[id] = true end
        end
    end
    if type(old.recentCatches) == "table" then
        for index = 1, RECENT_LIMIT do
            local row = old.recentCatches[index]
            if type(row) == "table" and ItemID(row.id) and F.Number(row.count) and row.count >= 1 then
                local link = F.PublicString(row.link) and tonumber(row.link:match("item:(%d+)")) == row.id and row.link or nil
                recentCatches[#recentCatches + 1] = { id = row.id, count = math.floor(row.count), link = link }
            end
        end
    end
    self.db = { history = history, current = Clean(old.current) or Empty(), favorites = favorites,
        recentCatches = recentCatches, spots = type(old.spots) == "table" and old.spots or {},
        wantedCatch = ItemID(old.wantedCatch) and old.wantedCatch or nil }
    RicoFishingLogDB, F.session = self.db, self.db.current
end

function L:GetRecentCatches()
    return self.db and self.db.recentCatches or emptyRecent
end

function L:GetWantedCatch()
    return self.db and self.db.wantedCatch
end

function L:SetWantedCatch(id)
    if not self.db or F.IsSecret(id) or (id ~= nil and not ItemID(id)) then return false end
    if self.db.wantedCatch ~= id then
        self.db.wantedCatch = id
        F:Refresh()
    end
    return true
end

function L:IsFavorite(id)
    return self.db ~= nil and ItemID(id) and self.db.favorites[id] == true
end

function L:ToggleFavorite(id)
    if not self.db or not ItemID(id) then return false end
    local selected = not self:IsFavorite(id)
    self.db.favorites[id] = selected and true or nil
    self:Refresh()
    if F.QueueRefresh then F:QueueRefresh() else F:Refresh() end
    return selected
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

local function RecordRecent(recent, window, id, quantity, link)
    window.recentByItem = window.recentByItem or {}
    local row = window.recentByItem[id]
    if row then
        row.count = row.count + quantity
        return
    end
    row = { id = id, count = quantity, link = link }
    window.recentByItem[id] = row
    table.insert(recent, 1, row)
    recent[RECENT_LIMIT + 1] = nil
end

function L:Record(id, quantity, firstInWindow, window, link)
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
    if current.qualities[id] == nil then current.qualities[id] = ReadQuality(id) end
    current.quantity = current.quantity + quantity
    if firstInWindow then
        current.loots = current.loots + 1
        self.favoriteAlerted = nil
    end
    if window then RecordRecent(self.db.recentCatches, window, id, quantity, link) end
    if self:IsFavorite(id) and not self.favoriteAlerted and F.db.favoriteAlerts ~= false then
        self.favoriteAlerted = true
        F:Print("Favorite caught · " .. ItemName(id) .. " ×" .. quantity)
    end
    if self.view == 0 or archived then self:Refresh() end
end

local function Duration(session)
    if session.started and session.started > 0 then return session.last - session.started end
end

function L:GetRate(session)
    session = session or self.db.current
    local elapsed = Duration(session)
    if elapsed and elapsed >= 60 then return session.quantity * 3600 / elapsed end
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

ItemName = function(id)
    local entry = F:GetEntry(id)
    if entry and F.PublicString(entry.name) then return entry.name end
    local ok, name = F.Call(C_Item and C_Item.GetItemNameByID or GetItemInfo, id)
    if ok and F.PublicString(name) then return name end
    RequestItem(id)
    return "Item #" .. id
end

local function DurationLabel(elapsed)
    if not elapsed then return "Time unavailable" end
    local minutes, seconds = math.floor(elapsed / 60), elapsed % 60
    if minutes >= 60 then return ("%dh %02dm"):format(math.floor(minutes / 60), minutes % 60) end
    if minutes >= 1 then return ("%dm %02ds"):format(minutes, seconds) end
    return ("%ds"):format(seconds)
end

local function BestCatch(session)
    local bestID, bestCount, bestQuality
    for id, count in pairs(session.items) do
        local quality = session.qualities[id]
        if quality == nil then
            quality = ReadQuality(id)
            session.qualities[id] = quality
            if quality == nil then RequestItem(id) end
        end
        if quality and (not bestQuality or quality > bestQuality or (quality == bestQuality
            and (count > bestCount or (count == bestCount and id < bestID)))) then
            bestID, bestCount, bestQuality = id, count, quality
        end
    end
    return bestID, bestCount, bestQuality
end

function L:Build()
    if self.frame then return end
    local T = F.Theme
    local frame = CreateFrame("Frame", "RicoFishingCatchLog", UIParent)
    self.frame, self.rows = frame, {}
    frame:SetSize(510, 472)
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
    self.best = Text(frame, 10, T.colors.amber)
    self.best:SetPoint("TOPLEFT", 24, -157)
    self.best:SetWidth(462)
    self.best:SetWordWrap(false)
    for index = 1, ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(466, 28)
        row:SetPoint("TOPLEFT", 22, -183 - (index - 1) * 31)
        row:EnableMouse(true)
        row.background = T:Panel(row)
        row:SetScript("OnClick", function(self) if self.itemID then L:ToggleFavorite(self.itemID) end end)
        row:SetScript("OnEnter", function(self)
            self.hovered = true
            T:Row(self, L:IsFavorite(self.itemID), true)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L:IsFavorite(self.itemID) and "Click to remove favorite" or "Click to favorite")
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hovered = false
            T:Row(self, L:IsFavorite(self.itemID), false)
            if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(19, 19)
        row.icon:SetPoint("LEFT", 6, 0)
        row.name = Text(row, 11)
        row.name:SetPoint("LEFT", 32, 0)
        row.name:SetWidth(344)
        row.name:SetWordWrap(false)
        row.count = Text(row, 11, T.colors.mint)
        row.count:SetPoint("RIGHT", -36, 0)
        row.star = Text(row, 14, T.colors.amber)
        row.star:SetPoint("RIGHT", -10, 0)
        self.rows[index] = row
    end
    self.empty = Text(frame, 12, T.colors.muted)
    self.empty:SetPoint("TOPLEFT", 24, -192)
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
    help:SetPoint("BOTTOMLEFT", 24, 20)
    help:SetText("Click an item to favorite it. A catch after 15 minutes idle starts a new session.")
    local method = Text(frame, 9, T.colors.muted)
    method:SetPoint("BOTTOMLEFT", 24, 8)
    method:SetText("Duration runs from first to last catch. Best uses known rarity, then quantity.")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(_, _, id, success)
        if F.Number(id) and L.requested[id] and not F.IsSecret(success) and success == true then L:Refresh() end
    end)
    frame:Hide()
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RicoFishingCatchLog" end
end

function L:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local T = F.Theme
    local history = self.db.history
    self.view = math.max(0, math.min(self.view, #history))
    local current = self.view == 0
    local session = current and self.db.current or history[self.view]
    self.selection:SetText(current and "Current session" or ("Past session %d/%d"):format(self.view, #history))
    self.newer:SetEnabled(not current)
    self.older:SetEnabled(self.view < #history)
    self.reset:SetEnabled(current and session.quantity > 0)
    local summary = ("%d %s · %d %s"):format(session.quantity, session.quantity == 1 and "item" or "items",
        session.loots, session.loots == 1 and "catch" or "catches")
    if session.quantity > 0 then
        local rate = self:GetRate(session)
        summary = summary .. " · " .. DurationLabel(Duration(session))
        if rate then summary = summary .. (" · %.0f items/h"):format(rate) end
    end
    self.summary:SetText(summary)
    self.details:SetText(session.quantity > 0 and ("Started " .. DateLabel(session.started)
        .. (session.zone and " · " .. session.zone or "")) or "")
    local bestID, bestCount, bestQuality = BestCatch(session)
    local qualityLabel = bestQuality and _G["ITEM_QUALITY" .. bestQuality .. "_DESC"]
    local best = bestID and ("Best by rarity · " .. ItemName(bestID) .. " ×" .. bestCount
        .. (F.PublicString(qualityLabel) and " · " .. qualityLabel or ""))
    self.best:SetText(best or (session.quantity > 0 and "Best by rarity · Item quality unavailable" or ""))

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
        row.itemID = item and item.id or nil
        row:SetShown(item ~= nil)
        if item then
            local favorite = self:IsFavorite(item.id)
            row.icon:SetTexture(F:GetIcon(item.id))
            row.name:SetText(ItemName(item.id))
            row.count:SetText("×" .. item.count)
            row.star:SetText(favorite and "★" or "☆")
            row.star:SetTextColor(unpack(favorite and T.colors.amber or T.colors.muted))
            T:Row(row, favorite, row.hovered)
        end
    end
end

function L:Toggle()
    if not self.db then return end
    self:Build()
    self.frame:SetShown(not self.frame:IsShown())
    self:Refresh()
end
