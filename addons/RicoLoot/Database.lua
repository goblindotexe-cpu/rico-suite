-- Download requests cross the normal SavedVariables/reload boundary.
-- Public web requests are handled by the local companion, outside the game.
local _, R = ...
local T = R.Theme
local D = { rows = {}, cards = {}, page = 1 }
R.Database = D
local unpack = unpack or table.unpack

local function Text(parent, value, size, color)
    local fs = (parent.ricoForeground or parent):CreateFontString(nil, "OVERLAY")
    fs:SetFont(T.font, size or 11, "")
    fs:SetTextColor(unpack(color or T.colors.text))
    fs:SetJustifyH("LEFT"); fs:SetText(value or "")
    return fs
end
local function Button(parent, label, width, callback)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 28); b.background = T:Panel(b)
    b.label = Text(b, label); b.label:SetPoint("CENTER")
    b:SetScript("OnClick", callback); T:Button(b, b.background)
    return b
end
local function Count(value)
    return R.Number(value) and math.max(0, math.floor(value)) or 0
end
local function Stamp(value)
    return R.String(value) and value:sub(1, 19):gsub("T", " ") .. " UTC" or "Not recorded"
end
local function Request(value)
    if not R.String(value) or #value >= 128 then return nil end
    local stamp, nonce = value:match("^RICOLOOT%-SYNC%-1:([1-9]%d+):([%w_%-]+)$")
    return stamp and #stamp >= 9 and #stamp <= 12 and #nonce >= 8 and #nonce <= 64 and value or nil
end
local function Now()
    local ok, value = R.Call(GetServerTime or time)
    return ok and R.Number(value) and math.floor(value) or nil
end
local function InCombat()
    local ok, value = R.Call(InCombatLockdown)
    return ok and value and true or false
end

function D:GetSyncState()
    if not RicoLootEverloot then
        return "idle", "Install the optional Everloot updater to enable database downloads."
    end
    local request = self.requestId or Request(RicoLootSyncRequest)
    local snapshot = R.Data.remoteSnapshot or {}
    local status = R.Data.syncStatus or {}
    if request then
        if snapshot.completedRequestId == request then
            return "success", "Download complete. The latest database is loaded."
        elseif status.requestId == request and status.state == "error" then
            return "error", R.String(status.message) and status.message or "Download failed. The previous database is still loaded."
        else
            local stamp = tonumber(request:match("^RICOLOOT%-SYNC%-1:(%d+):"))
            local now = Now()
            if now and stamp and now - stamp > 600 then
                return "error", "The download request expired. Check the local updater, then choose Fetch latest again."
            end
            return "fetching", "Download requested. When the local updater finishes, choose Reload & view."
        end
    end
    return "idle", "View the latest comparison, or fetch a fresh public Everloot snapshot."
end

function D:Notice(message)
    self.notice = message
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function D:RequestFetch()
    if not RicoLootEverloot then
        self:Notice("Install the optional Everloot updater, then restart WoW.")
        return false
    end
    if InCombat() then self:Notice("Finish combat before fetching a database update."); return false end
    local reload = ReloadUI or UIReload
    if type(reload) ~= "function" then self:Notice("The interface reload API is unavailable. Use the external updater."); return false end
    local stamp = Now()
    if not stamp then self:Notice("The game clock is unavailable. No request was sent."); return false end
    local current = self.requestId or Request(RicoLootSyncRequest)
    local sent = current and tonumber(current:match("^RICOLOOT%-SYNC%-1:(%d+):"))
    local state = self:GetSyncState()
    if sent and state == "fetching" and stamp - sent < 10 then
        self:Notice("A download was just requested. Wait for the updater, then choose Reload & view.")
        return false
    end
    local nonce = string.format("%08d%08d", math.random(10000000, 99999999), math.random(10000000, 99999999))
    local request = "RICOLOOT-SYNC-1:" .. stamp .. ":" .. nonce
    local previous, previousRequest = RicoLootSyncRequest, self.requestId
    RicoLootSyncRequest, self.requestId, self.notice = request, request, nil
    local ok = R.Call(reload)
    if not ok then
        RicoLootSyncRequest, self.requestId = previous, previousRequest
        self:Notice("The interface could not reload. No download request was saved.")
        return false
    end
    return true
end

function D:ReloadAndView()
    if InCombat() then self:Notice("Finish combat before reloading the interface."); return false end
    local reload = ReloadUI or UIReload
    if type(reload) ~= "function" then self:Notice("Use /reload to load the downloaded result."); return false end
    return R.Call(reload)
end

function D:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "RicoLootDatabase", UIParent)
    self.frame = f
    f:SetSize(820, 660); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.ricoSkipSuiteButtons = true
    T:Window(f)
    local title = Text(f, "", 23, T.colors.mint); title:SetPoint("TOPLEFT", 24, -22); T:Title(title, "DATABASE")
    self.summary = Text(f, "", 11, T.colors.muted); self.summary:SetPoint("TOPLEFT", 24, -57)
    self.closeButton = Button(f, "Close", 72, function() f:Hide() end)
    self.closeButton:SetPoint("TOPRIGHT", -24, -29)
    self.message = Text(f, "", 11, T.colors.mint)
    self.message:SetPoint("TOPLEFT", 24, -87); self.message:SetWidth(772); self.message:SetHeight(30)
    self.message:SetJustifyV("TOP")
    for index, label in ipairs({"New unique items", "New creature drops", "New creatures"}) do
        local card = CreateFrame("Frame", nil, f)
        card:SetSize(244, 72); card:SetPoint("TOPLEFT", 24 + (index - 1) * 264, -124)
        T:Panel(card)
        card.label = Text(card, label, 11, T.colors.muted); card.label:SetPoint("TOPLEFT", 14, -10)
        card.value = Text(card, "0", 26, T.colors.mint); card.value:SetPoint("BOTTOMLEFT", 14, 10)
        self.cards[index] = card
    end
    self.compared = Text(f, "", 11); self.compared:SetPoint("TOPLEFT", 24, -208); self.compared:SetWidth(772)
    self.lastChecked = Text(f, "", 10, T.colors.muted); self.lastChecked:SetPoint("TOPLEFT", 24, -228); self.lastChecked:SetWidth(772)
    local heading = Text(f, "Items added in the last data change", 12, T.colors.mint); heading:SetPoint("TOPLEFT", 24, -254)
    for index = 1, 6 do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(772, 28); row:SetPoint("TOPLEFT", 24, -277 - (index - 1) * 32)
        T:Panel(row); T:Row(row, false, false)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", 4, 0)
        row.name = Text(row, "", 11); row.name:SetPoint("LEFT", 35, 0); row.name:SetWidth(610); row.name:SetWordWrap(false)
        row.ident = Text(row, "", 10, T.colors.muted); row.ident:SetPoint("RIGHT", -10, 0)
        row:SetScript("OnEnter", function(self)
            T:Row(self, false, true)
            if self.itemID and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.itemID); GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self) T:Row(self, false, false); if GameTooltip then GameTooltip:Hide() end end)
        row:SetScript("OnClick", function(self)
            if self.itemID and R.Wishlist then R.Wishlist:Add(self.itemID); D:Notice("Item saved to your wishlist.") end
        end)
        self.rows[index] = row
    end
    self.empty = Text(f, "No new unique items in this comparison.", 12, T.colors.muted)
    self.empty:SetPoint("TOPLEFT", 40, -298); self.empty:SetWidth(730)
    self.prevButton = Button(f, "Previous", 85, function() D.page = math.max(1, D.page - 1); D:Refresh() end)
    self.prevButton:SetPoint("TOPLEFT", 24, -481)
    self.nextButton = Button(f, "Next", 85, function() D.page = D.page + 1; D:Refresh() end)
    self.nextButton:SetPoint("TOPRIGHT", -24, -481)
    self.pageText = Text(f, "", 10, T.colors.muted); self.pageText:SetPoint("TOP", 0, -490)
    self.details = Text(f, "", 10, T.colors.muted); self.details:SetPoint("TOPLEFT", 24, -521); self.details:SetWidth(772)
    local help = Text(f, "Fetch latest reloads the interface to start the download. When the local updater finishes,\nchoose Reload & view to load the result. Click an item above to save it to your wishlist.", 10, T.colors.muted)
    help:SetPoint("TOPLEFT", 24, -543); help:SetWidth(772); help:SetHeight(32); help:SetJustifyV("TOP")
    self.fetchButton = Button(f, "Fetch latest", 160, function() D:RequestFetch() end)
    self.fetchButton:SetPoint("BOTTOMLEFT", 24, 52)
    self.reloadButton = Button(f, "Reload & view", 160, function() D:ReloadAndView() end)
    self.reloadButton:SetPoint("LEFT", self.fetchButton, "RIGHT", 12, 0)
    local credit = Text(f, "Data from Everloot (https://everloot.app), CC BY-SA 4.0.", 10, T.colors.muted)
    credit:SetPoint("BOTTOMLEFT", 24, 20)
    f:SetScript("OnShow", function() D:Refresh() end)
    f:Hide()
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "RicoLootDatabase" end
end

function D:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local snapshot = R.Data.remoteSnapshot or {}
    local changes = snapshot.changes or {}
    self.summary:SetText(string.format("Everloot · %d creatures · %d unique items · %d drop entries", Count(snapshot.npcCount), Count(snapshot.itemCount), Count(snapshot.dropCount)))
    local state, message = self:GetSyncState()
    if not self.notice and (state == "idle" or state == "success") and changes.latestCheckChanged == false and changes.baselineEstablished then
        message = (state == "success" and "Download complete. " or "")
            .. "No new data on the latest check. The last comparison is shown below."
    end
    self.message:SetText(self.notice or message)
    self.message:SetTextColor(unpack(state == "error" and T.colors.amber or T.colors.mint))
    for index, key in ipairs({"addedItems", "addedDrops", "addedNpcs"}) do self.cards[index].value:SetText("+" .. Count(changes[key])) end
    self.compared:SetText(changes.baselineEstablished
        and ("Last data change compared with " .. Stamp(changes.previousDataAsOf))
        or "Comparison baseline established. Additions will be counted from the next data change.")
    self.lastChecked:SetText("Last checked: " .. Stamp(changes.checkedAt) .. " · Source data: " .. Stamp(snapshot.dataAsOf))
    local ids = R.Table(changes.newItemIds) and changes.newItemIds or {}
    local pages = math.max(1, math.ceil(#ids / 6)); self.page = math.max(1, math.min(self.page, pages))
    for index, row in ipairs(self.rows) do
        local id = ids[(self.page - 1) * 6 + index]
        row.itemID = R.Number(id) and id or nil
        row:SetShown(row.itemID ~= nil)
        if row.itemID then
            local item = R:GetItem({itemID = row.itemID})
            row.name:SetText(item.name or ("Item " .. row.itemID))
            row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.ident:SetText("ID " .. row.itemID)
        end
    end
    self.empty:SetShown(#ids == 0)
    self.prevButton:SetEnabled(self.page > 1); self.nextButton:SetEnabled(self.page < pages)
    self.pageText:SetText(self.page .. " / " .. pages .. " · " .. #ids .. " new unique items")
    self.details:SetText(string.format("Updated observation entries: %d · Removed items: %d · Removed creature drops: %d · Removed creatures: %d",
        Count(changes.updatedDrops), Count(changes.removedItems), Count(changes.removedDrops), Count(changes.removedNpcs)))
end

function D:Show()
    R:Initialize(); self:Build(); self.frame:Show(); self:Refresh()
end

function D:Initialize()
    if self.initialized then return end
    self.initialized = true
    self.requestId = Request(RicoLootSyncRequest)
    if not self.requestId then return end
    local state = self:GetSyncState()
    if state == "success" or state == "error" then RicoLootSyncRequest = nil end
    local function Open() D:Show() end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, Open) else Open() end
end

D.events = CreateFrame("Frame")
D.events:RegisterEvent("ADDON_LOADED"); D.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
D.events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == R.name then D:Initialize()
    elseif event == "GET_ITEM_INFO_RECEIVED" then D:Refresh() end
end)
