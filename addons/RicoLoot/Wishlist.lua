-- Persistent farming goals. Source searches are lazy and spread across frames.
local _, R = ...
local T = R.Theme
local W = {rows = {}, page = 1, sourcePage = 1, sourceCache = {}}
R.Wishlist = W
local unpack = unpack or table.unpack

local function Text(parent, text, size, color)
    local fs = (parent.ricoForeground or parent):CreateFontString(nil, "OVERLAY")
    fs:SetFont(T.font, size or 11, "")
    fs:SetTextColor(unpack(color or T.colors.text))
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end
local function Button(parent, label, width, height, callback)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 25)
    b.background = T:Panel(b)
    b.label = Text(b, label, 10)
    b.label:SetPoint("CENTER")
    b:SetScript("OnClick", callback)
    T:Button(b, b.background)
    return b
end
local function Input(parent, width)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, 25); edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    T:Input(edit)
    return edit
end
local function ItemID(value)
    if R.String(value) then value = tonumber(value:match("item:(%d+)") or value) end
    if R.Number(value) and value > 0 and value == math.floor(value) then return value end
end

function W:Initialize()
    if not R.db then return end
    if not R.Table(R.db.wishlist) then R.db.wishlist = {} end
    for id, entry in pairs(R.db.wishlist) do
        if not ItemID(id) or not R.Table(entry) or not R.Number(entry.goal) then R.db.wishlist[id] = nil
        else entry.goal = math.max(1, math.min(999999, math.floor(entry.goal))) end
    end
end
function W:Add(value, goal)
    R:Initialize(); self:Initialize()
    local id = ItemID(value)
    if not id then return false, "Enter an item ID or an item link." end
    local count = 0; for _ in pairs(R.db.wishlist) do count = count + 1 end
    if count >= 200 and not R.db.wishlist[id] then return false, "The wishlist supports up to 200 items." end
    if R.String(goal) then goal = tonumber(goal) end
    if goal ~= nil and (not R.Number(goal) or goal < 1) then return false, "Enter a goal of at least 1." end
    local saved = R.db.wishlist[id]
    R.db.wishlist[id] = {goal = math.max(1, math.min(999999, math.floor(goal or (saved and saved.goal) or 1)))}
    self:Refresh()
    return true
end
function W:Remove(id)
    if R.db and R.db.wishlist then R.db.wishlist[id] = nil end
    self:Refresh()
end
function W:IsSaved(id)
    return R.db and R.db.wishlist and R.db.wishlist[id] ~= nil or false
end
function W:GetEntries()
    self:Initialize()
    local entries = {}
    for id, entry in pairs(R.db and R.db.wishlist or {}) do
        local item = R:GetItem({itemID = id})
        local ok, count = R.Call(C_Item and C_Item.GetItemCount or GetItemCount, id, false, false, false, false)
        entries[#entries + 1] = {id = id, goal = entry.goal, item = item, count = ok and R.Number(count) and count or nil}
    end
    table.sort(entries, function(a, b)
        local an, bn = R:Normalize(a.item.name), R:Normalize(b.item.name)
        return an ~= bn and an < bn or (an == bn and a.id < b.id)
    end)
    return entries
end

local function Contains(tbl, id)
    if R.Table(tbl.rows) then
        for _, row in ipairs(tbl.rows) do if row.itemID == id then return true end end
    end
    local packed = tbl.packed
    if type(packed) == "string" then
        local needle = tostring(id) .. "|"
        return packed:sub(1, #needle) == needle or packed:find(";" .. needle, 1, true) ~= nil
    end
    return false
end
function W:InvalidateSources()
    self.sourceCache = {}
    if not self.sourceFrame or not self.sourceFrame:IsShown() or not self.sources or self.sourceRefreshPending then return end
    self.sourceRefreshPending = true
    local function Refresh()
        self.sourceRefreshPending = nil
        if self.sourceFrame:IsShown() and self.sources then self:FindSources(self.sources.itemID) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, Refresh) else Refresh() end
end
function W:FindSources(id)
    local cached = self.sourceCache[id]
    if cached and cached.done then self.sources = cached; self.sourcePage = 1; self:RefreshSources(); return cached end
    self.sourceGeneration = (self.sourceGeneration or 0) + 1
    local generation = self.sourceGeneration
    local result = {itemID = id, entries = {}, done = false, processed = 0}
    self.sourceCache[id], self.sources, self.sourcePage = result, result, 1
    local mobs = {}
    for _, mob in pairs(R:GetAllMobs()) do mobs[#mobs + 1] = mob end
    table.sort(mobs, function(a, b) return a.id < b.id end)
    result.total = #mobs
    local cursor = 1
    local function Step()
        if self.sourceGeneration ~= generation then return end
        for _ = 1, 80 do
            local mob = mobs[cursor]
            if not mob then result.done = true; break end
            cursor = cursor + 1
            local labels, seen = {}, {}
            for _, tbl in ipairs(mob.tables or {}) do
                if Contains(tbl, id) then
                    local label = tbl.provenance == "local_observed" and "Your observation"
                        or tbl.provenance == "classic_reference" and "Classic reference"
                        or tbl.provenance == "forever_observed" and "Supplied observations" or "Forever reference"
                    if not seen[label] then labels[#labels + 1] = label; seen[label] = true end
                end
            end
            if #labels > 0 then
                local zones = {}
                for _, key in ipairs(mob.zones or {}) do local zone = R:GetZone(key); if zone then zones[#zones + 1] = zone.name end end
                result.entries[#result.entries + 1] = {id = mob.id, name = mob.name, zones = table.concat(zones, ", "),
                    provenance = table.concat(labels, " / ")}
            end
        end
        result.processed = math.min(#mobs, cursor - 1)
        self:RefreshSources()
        if not result.done then
            if C_Timer and C_Timer.After then C_Timer.After(0.01, Step)
            else Step() end
        else self:Refresh() end
    end
    Step()
    return result
end

function W:BuildSources()
    if self.sourceFrame then return end
    local frame = CreateFrame("Frame", "RicoLootWishlistSources", UIParent)
    self.sourceFrame = frame
    frame:SetSize(760, 480); frame:SetPoint("CENTER"); frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true); frame:EnableMouse(true)
    T:Window(frame)
    local title = Text(frame, "", 23); title:SetPoint("TOPLEFT", 24, -22); T:Title(title, "FARM SOURCES")
    self.sourceStatus = Text(frame, "", 10, T.colors.muted); self.sourceStatus:SetPoint("TOPLEFT", 24, -58); self.sourceStatus:SetWidth(710)
    Button(frame, "Close", 72, 28, function() frame:Hide() end):SetPoint("TOPRIGHT", -24, -29)
    self.sourceRows = {}
    for index = 1, 8 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(712, 39); row:SetPoint("TOPLEFT", 24, -88 - (index - 1) * 42); T:Panel(row)
        row.name = Text(row, "", 11); row.name:SetPoint("TOPLEFT", 9, -5); row.name:SetWidth(601)
        row.detail = Text(row, "", 9, T.colors.muted); row.detail:SetPoint("BOTTOMLEFT", 9, 5); row.detail:SetWidth(601)
        row.name:SetWordWrap(false); row.detail:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.source or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.source.name)
            GameTooltip:AddLine("Areas: " .. (self.source.zones ~= "" and self.source.zones or "Unknown"), 0.75, 0.83, 0.79, true)
            GameTooltip:AddLine(self.source.provenance, 0.65, 0.75, 0.70, true)
            GameTooltip:Show()
        end)
        local function Hide(self) if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
        row:SetScript("OnLeave", Hide); row:SetScript("OnHide", Hide)
        row.open = Button(row, "Loot", 61, 25, function() if row.source then R:OpenMobLoot(row.source.id, row.source.name) end end)
        row.open:SetPoint("RIGHT", -7, 0)
        self.sourceRows[index] = row
    end
    self.sourceEmpty = Text(frame, "", 12, T.colors.muted); self.sourceEmpty:SetPoint("TOPLEFT", 31, -115); self.sourceEmpty:SetWidth(690)
    Button(frame, "Previous", 85, 25, function() W.sourcePage = math.max(1, W.sourcePage - 1); W:RefreshSources() end):SetPoint("BOTTOMLEFT", 24, 16)
    Button(frame, "Next", 85, 25, function() W.sourcePage = W.sourcePage + 1; W:RefreshSources() end):SetPoint("BOTTOMRIGHT", -24, 16)
    self.sourcePageText = Text(frame, "", 10, T.colors.muted); self.sourcePageText:SetPoint("BOTTOM", 0, 22)
    frame:Hide()
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "RicoLootWishlistSources" end
end
function W:ShowSources(id)
    self:BuildSources(); self.sourceFrame:Show(); self:FindSources(id)
end
function W:RefreshSources()
    if not self.sourceFrame or not self.sourceFrame:IsShown() or not self.sources then return end
    local result = self.sources
    local item = R:GetItem({itemID = result.itemID})
    self.sourceStatus:SetText(item.name .. " • " .. (result.done and (#result.entries .. " known creatures")
        or ("Searching sources: " .. result.processed .. "/" .. result.total)))
    local pages = math.max(1, math.ceil(#result.entries / 8))
    self.sourcePage = math.max(1, math.min(self.sourcePage, pages))
    for index, row in ipairs(self.sourceRows) do
        local source = result.entries[(self.sourcePage - 1) * 8 + index]
        row.source = source; row:SetShown(source ~= nil)
        if source then
            row.name:SetText(source.name .. " • NPC " .. source.id)
            row.detail:SetText((source.zones ~= "" and source.zones or "Location unknown") .. " • " .. source.provenance)
        end
    end
    self.sourceEmpty:SetShown(result.done and #result.entries == 0)
    self.sourceEmpty:SetText("No source is known yet. Creature-sourced loot you observe will be added automatically.")
    self.sourcePageText:SetText(self.sourcePage .. " / " .. pages)
end

function W:Build()
    if self.frame then return end
    local frame = CreateFrame("Frame", "RicoLootWishlist", UIParent)
    self.frame = frame
    frame:SetSize(850, 570); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    T:Window(frame)
    local title = Text(frame, "", 23); title:SetPoint("TOPLEFT", 24, -22); T:Title(title, "WISHLIST")
    local subtitle = Text(frame, "Saved farming goals • Alt-click a loot item to save it", 10, T.colors.muted)
    subtitle:SetPoint("TOPLEFT", 24, -58)
    Button(frame, "Close", 72, 28, function() frame:Hide() end):SetPoint("TOPRIGHT", -24, -29)
    self.itemInput = Input(frame, 205); self.itemInput:SetPoint("TOPLEFT", 24, -91); self.itemInput:SetMaxLetters(250)
    self.itemInput:SetText("")
    self.goalInput = Input(frame, 65); self.goalInput:SetPoint("LEFT", self.itemInput, "RIGHT", 10, 0)
    self.goalInput:SetNumeric(true); self.goalInput:SetMaxLetters(6); self.goalInput:SetText("1")
    local add = Button(frame, "Add item", 82, 25, function()
        local ok, message = W:Add(W.itemInput:GetText(), W.goalInput:GetText())
        if W.status then W.status:SetText(ok and "Item saved. Use Sources to see where it can drop." or message) end
        W.itemInput:ClearFocus(); W.goalInput:ClearFocus()
    end)
    add:SetPoint("LEFT", self.goalInput, "RIGHT", 10, 0)
    Text(frame, "Item ID or item link", 9, T.colors.muted):SetPoint("TOPLEFT", 26, -120)
    Text(frame, "Goal", 9, T.colors.muted):SetPoint("TOPLEFT", 242, -120)
    for index = 1, 6 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(802, 55); row:SetPoint("TOPLEFT", 24, -143 - (index - 1) * 58); T:Panel(row)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(31, 31); row.icon:SetPoint("LEFT", 8, 0)
        row.name = Text(row, "", 11); row.name:SetPoint("TOPLEFT", 47, -8); row.name:SetWidth(280)
        row.name:SetWordWrap(false)
        row.count = Text(row, "", 10); row.count:SetPoint("TOPLEFT", 338, -9); row.count:SetWidth(150)
        row.sources = Text(row, "", 9, T.colors.muted); row.sources:SetPoint("BOTTOMLEFT", 47, 8); row.sources:SetWidth(650)
        row.sources:SetWordWrap(false)
        row.goal = Input(row, 53); row.goal:SetPoint("TOPRIGHT", -227, -6); row.goal:SetNumeric(true); row.goal:SetMaxLetters(6)
        local function Save() if row.entry then W:Add(row.entry.id, row.goal:GetText()) end; row.goal:ClearFocus() end
        row.goal:SetScript("OnEnterPressed", Save)
        Button(row, "Save", 45, 25, Save):SetPoint("TOPRIGHT", -176, -6)
        Button(row, "Sources", 67, 25, function() if row.entry then W:ShowSources(row.entry.id) end end):SetPoint("TOPRIGHT", -101, -6)
        Button(row, "Remove", 77, 25, function() if row.entry then W:Remove(row.entry.id) end end):SetPoint("TOPRIGHT", -16, -6)
        self.rows[index] = row
    end
    self.empty = Text(frame, "Save an item from a loot table, or enter an item ID above.", 12, T.colors.muted)
    self.empty:SetPoint("TOPLEFT", 42, -167); self.empty:SetWidth(760)
    self.status = Text(frame, "Bag counts track your current inventory; source evidence is shown separately.", 10, T.colors.muted)
    self.status:SetPoint("TOPLEFT", 25, -504); self.status:SetWidth(800)
    Button(frame, "Previous", 85, 25, function() W.page = math.max(1, W.page - 1); W:Refresh() end):SetPoint("BOTTOMLEFT", 24, 16)
    Button(frame, "Next", 85, 25, function() W.page = W.page + 1; W:Refresh() end):SetPoint("BOTTOMRIGHT", -24, 16)
    self.pageText = Text(frame, "", 10, T.colors.muted); self.pageText:SetPoint("BOTTOM", 0, 22)
    frame:SetScript("OnShow", function() W:Refresh() end)
    frame:Hide()
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "RicoLootWishlist" end
end
function W:Show()
    R:Initialize(); self:Build(); self.frame:Show(); self:Refresh()
end
function W:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local entries = self:GetEntries()
    local pages = math.max(1, math.ceil(#entries / 6))
    self.page = math.max(1, math.min(self.page, pages))
    for index, row in ipairs(self.rows) do
        local entry = entries[(self.page - 1) * 6 + index]
        row.entry = entry; row:SetShown(entry ~= nil)
        if entry then
            row.icon:SetTexture(entry.item.icon); row.name:SetText(entry.item.name)
            row.count:SetText("Bags: " .. (entry.count and tostring(entry.count) or "?") .. " / " .. entry.goal)
            row.count:SetTextColor(unpack(entry.count and entry.count >= entry.goal and T.colors.mint or T.colors.muted))
            if not row.goal:HasFocus() then row.goal:SetText(tostring(entry.goal)) end
            local sources = self.sourceCache[entry.id]
            row.sources:SetText(sources and sources.done and (#sources.entries .. " known creature sources • click Sources to inspect")
                or "Sources: search known creatures and areas on demand")
        end
    end
    self.empty:SetShown(#entries == 0)
    self.pageText:SetText(self.page .. " / " .. pages .. " • " .. #entries .. " saved items")
end

W.eventFrame = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED"}) do W.eventFrame:RegisterEvent(event) end
W.eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then if name == R.name then W:Initialize() end
    else W:Refresh(); W:RefreshSources() end
end)
