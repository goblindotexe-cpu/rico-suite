local _, F = ...
local S = { page = 1, selectedOnly = false }
F.SpotStats = S

local CELL_COUNT, SPOT_LIMIT, ITEM_LIMIT, ROWS = 50, 150, 128, 7
local MAX_GAP, MIN_INTERVALS, MIN_SECONDS = 90, 3, 60
local unpack = unpack or table.unpack

local function Integer(value, min, max)
    return F.Number(value) and value >= min and value <= max and value == math.floor(value)
end

local function Count(value)
    return Integer(value, 0, 2147483647) and value or 0
end

local function PublicTable(value)
    return not F.IsSecret(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function SpotKey(mapID, x, y)
    return ("%d:%d:%d"):format(mapID, x, y)
end

local function ReadName(getter)
    local ok, name = F.Call(getter)
    if ok and F.PublicString(name) and name ~= "" then return name end
end

local function Position()
    if not C_Map then return end
    local gotMap, mapID = F.Call(C_Map.GetBestMapForUnit, "player")
    if not gotMap or not Integer(mapID, 1, 2147483647) then return end
    local gotPosition, position = F.Call(C_Map.GetPlayerMapPosition, mapID, "player")
    if not gotPosition or F.IsSecret(position) or position == nil then return end
    local read, x, y = pcall(function() return position:GetXY() end)
    if not read or not F.Number(x) or not F.Number(y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
    return mapID, math.min(CELL_COUNT - 1, math.floor(x * CELL_COUNT)),
        math.min(CELL_COUNT - 1, math.floor(y * CELL_COUNT))
end

local function SpotName(mapID)
    local name = ReadName(GetSubZoneText) or ReadName(GetMinimapZoneText) or ReadName(GetRealZoneText)
    if name then return name end
    local ok, info = F.Call(C_Map.GetMapInfo, mapID)
    if ok and PublicTable(info) and F.PublicString(info.name) and info.name ~= "" then return info.name end
    return "Map " .. mapID
end

local function Timestamp()
    local ok, now = F.Call(GetServerTime)
    if ok and F.Number(now) and now > 0 then return now end
    ok, now = F.Call(time)
    if ok and F.Number(now) and now > 0 then return now end
    return 0
end

local function Clean(key, raw)
    if not PublicTable(raw) or not Integer(raw.mapID, 1, 2147483647)
        or not Integer(raw.x, 0, CELL_COUNT - 1) or not Integer(raw.y, 0, CELL_COUNT - 1)
        or key ~= SpotKey(raw.mapID, raw.x, raw.y) then return end
    local catches, total = Count(raw.catches), Count(raw.total)
    if catches == 0 or total < catches then return end
    local spot = {
        mapID = raw.mapID, x = raw.x, y = raw.y,
        name = F.PublicString(raw.name) and raw.name ~= "" and raw.name or ("Map " .. raw.mapID),
        updated = F.Number(raw.updated) and math.max(0, raw.updated) or 0,
        catches = catches, total = total, items = {}, itemCount = 0, overflow = raw.overflow == true,
    }
    spot.intervals = math.min(catches - 1, Count(raw.intervals))
    spot.seconds = F.Number(raw.seconds) and math.max(0, math.min(spot.intervals * MAX_GAP, raw.seconds)) or 0
    spot.timedTotal = math.min(total, Count(raw.timedTotal))
    if PublicTable(raw.items) then
        for id, item in pairs(raw.items) do
            if Integer(id, 1, 2147483647) and PublicTable(item) and Count(item.total) > 0 then
                if spot.itemCount == ITEM_LIMIT then spot.overflow = true; break end
                local itemTotal = math.min(total, Count(item.total))
                spot.items[id] = { total = itemTotal, timed = math.min(itemTotal, spot.timedTotal, Count(item.timed)) }
                spot.itemCount = spot.itemCount + 1
            end
        end
    end
    return spot
end

function S:Initialize()
    local old = RicoFishingLogDB.spots
    local recent = {}
    if PublicTable(old) then
        for key, raw in pairs(old) do
            local spot = Clean(key, raw)
            if spot then recent[#recent + 1] = { key = key, spot = spot } end
        end
    end
    table.sort(recent, function(a, b)
        if a.spot.updated ~= b.spot.updated then return a.spot.updated > b.spot.updated end
        return a.key > b.key
    end)
    self.spots, self.spotCount = {}, math.min(#recent, SPOT_LIMIT)
    self.windowSpot, self.windowTimed, self.lastCatch = nil, nil, nil
    for index = 1, self.spotCount do
        local entry = recent[index]
        self.spots[entry.key] = entry.spot
    end
    RicoFishingLogDB.spots = self.spots
end

function S:OpenCatch()
    self.windowSpot, self.windowTimed = nil, nil
    local last = self.lastCatch
    self.lastCatch = nil
    local mapID, x, y = Position()
    if not mapID then return end
    local now, key = Timestamp(), SpotKey(mapID, x, y)
    local spot = self.spots[key]
    if not spot then
        if self.spotCount == SPOT_LIMIT then
            local oldestKey, oldestTime
            for otherKey, other in pairs(self.spots) do
                if not oldestKey or other.updated < oldestTime or (other.updated == oldestTime and otherKey < oldestKey) then
                    oldestKey, oldestTime = otherKey, other.updated
                end
            end
            self.spots[oldestKey] = nil
        else
            self.spotCount = self.spotCount + 1
        end
        spot = { mapID = mapID, x = x, y = y, name = SpotName(mapID),
            updated = now, catches = 0, total = 0, timedTotal = 0, seconds = 0, intervals = 0,
            items = {}, itemCount = 0 }
        self.spots[key] = spot
    end
    spot.catches = spot.catches + 1
    spot.updated = math.max(spot.updated, now)
    self.windowSpot = spot
    if last and last.key == key and last.session == F.session and now > last.time and now - last.time <= MAX_GAP then
        spot.seconds = spot.seconds + now - last.time
        spot.intervals = spot.intervals + 1
        self.windowTimed = true
    end
    if now > 0 then self.lastCatch = { key = key, time = now, session = F.session } end
end

function S:Record(itemID, quantity, firstInWindow)
    if not self.spots then return end
    if firstInWindow then self:OpenCatch() end
    local spot = self.windowSpot
    if not spot then return end
    spot.total = spot.total + quantity
    if self.windowTimed then spot.timedTotal = spot.timedTotal + quantity end
    local item = spot.items[itemID]
    if not item and spot.itemCount < ITEM_LIMIT then
        item = { total = 0, timed = 0 }
        spot.items[itemID] = item
        spot.itemCount = spot.itemCount + 1
    end
    if item then
        item.total = item.total + quantity
        if self.windowTimed then item.timed = item.timed + quantity end
    else
        spot.overflow = true
    end
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

function S:Build()
    if self.frame then return end
    local T = F.Theme
    local frame = CreateFrame("Frame", "RicoFishingSpotStats", UIParent)
    self.frame, self.rows = frame, {}
    frame:SetSize(600, 460)
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
    T:Title(title, "FISHING SPOTS")
    local close = Button(frame, "Close", 62, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -24, -30)
    local sub = Text(frame, 11, T.colors.muted)
    sub:SetPoint("TOPLEFT", 24, -57)
    sub:SetText("Your catches, grouped by the area where you stood")
    self.all = Button(frame, "All catches", 92, function() S.selectedOnly, S.page = false, 1; S:Refresh() end)
    self.all:SetPoint("TOPLEFT", 22, -83)
    self.selected = Button(frame, "Selected item", 110, function() S.selectedOnly, S.page = true, 1; S:Refresh() end)
    self.selected:SetPoint("LEFT", self.all, "RIGHT", 8, 0)
    self.filter = Text(frame, 11, T.colors.mint)
    self.filter:SetPoint("LEFT", self.selected, "RIGHT", 12, 0)
    self.filter:SetWidth(324)
    self.filter:SetWordWrap(false)
    local spotLabel = Text(frame, 10, T.colors.muted)
    spotLabel:SetPoint("TOPLEFT", 32, -121)
    spotLabel:SetText("FISHING SPOT")
    local catchLabel = Text(frame, 10, T.colors.muted)
    catchLabel:SetPoint("TOPRIGHT", -138, -121)
    catchLabel:SetText("ITEMS")
    local rateLabel = Text(frame, 10, T.colors.muted)
    rateLabel:SetPoint("TOPRIGHT", -32, -121)
    rateLabel:SetText("ITEMS / HOUR")
    for index = 1, ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(556, 31)
        row:SetPoint("TOPLEFT", 22, -138 - (index - 1) * 34)
        T:Panel(row)
        row.name = Text(row, 11)
        row.name:SetPoint("TOPLEFT", 10, -4)
        row.name:SetWidth(375)
        row.name:SetWordWrap(false)
        row.details = Text(row, 10, T.colors.muted)
        row.details:SetPoint("BOTTOMLEFT", 10, 3)
        row.total = Text(row, 11)
        row.total:SetPoint("RIGHT", -116, 0)
        row.rate = Text(row, 11, T.colors.mint)
        row.rate:SetPoint("RIGHT", -10, 0)
        self.rows[index] = row
    end
    self.empty = Text(frame, 12, T.colors.muted)
    self.empty:SetPoint("TOPLEFT", 32, -155)
    self.empty:SetText("Loot a catch to record your first fishing spot.")
    self.previous = Button(frame, "<", 27, function() S.page = S.page - 1; S:Refresh() end)
    self.previous:SetPoint("BOTTOMLEFT", 22, 54)
    self.next = Button(frame, ">", 27, function() S.page = S.page + 1; S:Refresh() end)
    self.next:SetPoint("LEFT", self.previous, "RIGHT", 54, 0)
    self.pages = Text(frame, 10, T.colors.muted)
    self.pages:SetPoint("CENTER", self.previous, "CENTER", 41, 0)
    local sample = Text(frame, 10, T.colors.muted)
    sample:SetPoint("BOTTOMLEFT", 24, 32)
    sample:SetText(("Rates count catches ending a timed interval at the same spot, up to %ds apart."):format(MAX_GAP))
    local threshold = Text(frame, 10, T.colors.muted)
    threshold:SetPoint("BOTTOMLEFT", 24, 17)
    threshold:SetText(("Hourly rates need at least %d timed intervals and %ds of measured time."):format(MIN_INTERVALS, MIN_SECONDS))
    frame:Hide()
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RicoFishingSpotStats" end
end

function S:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local id = F.db and F.db.selected
    local entry = F:GetEntry(id)
    local selected = self.selectedOnly and entry ~= nil
    if not entry then self.selectedOnly = false end
    if selected and self.viewID ~= id then self.page = 1 end
    self.viewID = selected and id or nil
    self.all:SetEnabled(selected)
    self.selected:SetEnabled(not selected and entry ~= nil)
    self.filter:SetText(selected and entry.name or "All looted items")

    local spots = {}
    for key, spot in pairs(self.spots) do
        local item = selected and spot.items[id]
        local untracked = selected and not item and spot.overflow
        local count, timed = spot.total, spot.timedTotal
        if selected then count, timed = item and item.total or 0, item and item.timed or 0 end
        local rate
        if not untracked and spot.intervals >= MIN_INTERVALS and spot.seconds >= MIN_SECONDS then
            rate = timed * 3600 / spot.seconds
        end
        spots[#spots + 1] = { key = key, spot = spot, count = count, rate = rate, untracked = untracked }
    end
    table.sort(spots, function(a, b)
        if a.rate ~= b.rate then return (a.rate or -1) > (b.rate or -1) end
        if a.count ~= b.count then return a.count > b.count end
        if a.spot.updated ~= b.spot.updated then return a.spot.updated > b.spot.updated end
        return a.key < b.key
    end)
    local pageCount = math.max(1, math.ceil(#spots / ROWS))
    self.page = math.max(1, math.min(self.page, pageCount))
    self.pages:SetText(("%d/%d"):format(self.page, pageCount))
    self.previous:SetEnabled(self.page > 1)
    self.next:SetEnabled(self.page < pageCount)
    self.empty:SetShown(#spots == 0)
    for index, row in ipairs(self.rows) do
        local result = spots[(self.page - 1) * ROWS + index]
        row:SetShown(result ~= nil)
        if result then
            local spot = result.spot
            row.name:SetText(spot.name)
            row.details:SetText(("~%.0f, %.0f  ·  %d %s  ·  %d timed  ·  %.1f min"):format(
                (spot.x + 0.5) * 100 / CELL_COUNT, (spot.y + 0.5) * 100 / CELL_COUNT,
                spot.catches, spot.catches == 1 and "catch" or "catches", spot.intervals, spot.seconds / 60))
            row.total:SetText(result.untracked and "—" or tostring(result.count))
            row.rate:SetText(result.rate and ("%.1f"):format(result.rate) or "—")
        end
    end
end

function S:Toggle()
    if not self.spots then return end
    self:Build()
    self.frame:SetShown(not self.frame:IsShown())
    self:Refresh()
end
