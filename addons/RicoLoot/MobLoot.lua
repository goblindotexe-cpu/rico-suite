-- A pinned NPC's complete supplied loot, independent of the main browser.
-- Copyright (C) 2026 Rico. Distributed under GNU GPL version 3 or later.
local _, R = ...
local T = R.Theme
local M = { rows = {}, offset = 0, x = 0, y = 0 }
R.MobLoot = M

local WIDTH, HEIGHT = 700, 610
local ROW_HEIGHT, VISIBLE_ROWS, VIEW_WIDTH = 28, 15, 640
local VIEW_HEIGHT = ROW_HEIGHT * VISIBLE_ROWS
local FONT, WHITE = T.font, "Interface\\Buttons\\WHITE8X8"
local UNPACK = unpack or table.unpack
local COLORS = T.colors
local METHOD_NAMES = { loot = "Normal loot", skinning = "Skinning", pickpocket = "Pickpocket", observed = "Observed creature loot" }
local METHOD_ORDER = { loot = 1, skinning = 2, pickpocket = 3 }
local SOURCE_ORDER = { local_observed = 0, forever_observed = 1, forever_reference = 2, classic_reference = 3 }

local function String(value, fallback) return R.String(value) and value or (fallback or "") end
local function Clamp(value, lower, upper) return math.max(lower, math.min(upper, value)) end

local function Text(parent, size, color, justify)
    local surface = parent.ricoForeground or parent
    local text = surface:CreateFontString(nil, "OVERLAY")
    if parent.ricoForeground then
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
    end
    text:SetFont(FONT, size or 11, "")
    text:SetTextColor(UNPACK(color or COLORS.text))
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

local function SourceStyle(tbl)
    if tbl.provenance == "local_observed" then return COLORS.mint, "SEEN" end
    if tbl.provenance == "classic_reference" then return COLORS.amber, "BASE RATE" end
    if tbl.provenance == "forever_observed" or tbl.rateKind == "observed" then return COLORS.mint, "OBSERVED %" end
    if tbl.provenance == "forever_reference" then return COLORS.blue, "CHANCE" end
    return COLORS.muted, "CHANCE"
end

local function ItemColor(item)
    local quality = item and item.quality
    local color = R.Number(quality) and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if R.Table(color) and R.Number(color.r) and R.Number(color.g) and R.Number(color.b) then
        return color.r, color.g, color.b
    end
    return UNPACK(COLORS.text)
end

local function Quantity(row)
    local low, high = row.quantityMin, row.quantityMax
    if not R.Number(low) then low = nil end
    if not R.Number(high) then high = nil end
    if low and high then return low == high and string.format("%g", low) or string.format("%g–%g", low, high) end
    if low then return string.format("%g", low) end
    if high then return string.format("≤%g", high) end
    return "—"
end

function M:IsShown()
    return self.frame and self.frame:IsShown() or false
end

function M:GetPinnedNPC()
    if self:IsShown() then return self.npcID, self.displayName end
end

function M:HideTooltip(owner)
    if not self.tooltipOwner or (owner and self.tooltipOwner ~= owner) then return end
    if GameTooltip then
        local current = GameTooltip.GetOwner and GameTooltip:GetOwner()
        if not R.IsSecret(current) and current == self.tooltipOwner then GameTooltip:Hide() end
    end
    self.tooltipOwner = nil
end

function M:ShowTooltip(widget)
    local entry = widget.entry
    if not self:IsShown() or not entry or not GameTooltip then return end
    self:HideTooltip()
    GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local section = entry.section
    if entry.kind == "item" and widget.item then
        local item, applied = widget.item, false
        local link = String(item.link)
        if link ~= "" and type(GameTooltip.SetHyperlink) == "function" then
            applied = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        elseif R.Number(item.id) and type(GameTooltip.SetItemByID) == "function" then
            applied = pcall(GameTooltip.SetItemByID, GameTooltip, item.id)
        end
        if not applied then GameTooltip:SetText(String(item.name, "Unknown item")) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(String(R:GetChanceDetails(entry.row, section.lootTable)), 0.79, 0.86, 0.90, true)
    else
        GameTooltip:SetText(section.caption)
        GameTooltip:AddLine(section.summary, 0.79, 0.86, 0.90, true)
        if section.note ~= "" then GameTooltip:AddLine(section.note, 0.79, 0.86, 0.90, true) end
        if section.sourceName ~= "" then GameTooltip:AddLine("Source: " .. section.sourceName, 0.68, 0.78, 0.84, true) end
        if section.url ~= "" then GameTooltip:AddLine(section.url, 0.59, 0.68, 0.75, true) end
    end
    GameTooltip:Show()
    self.tooltipOwner = widget
end

-- Copy references and sort this NPC only. Do not call GetTables/GetLootRows:
-- those are the main browser's source filter and selected-table sort cache.
function M:Prepare(npcID, displayName)
    local mob = R:GetMob(npcID)
    if not R.Table(mob) then mob = nil end
    self.npcID, self.mob = npcID, mob
    self.displayName = R.String(displayName) and displayName ~= "" and displayName
        or mob and String(mob.name, "Unknown creature") or "Unknown creature"
    self.entries, self.sections, self.totalItems = {}, {}, 0
    self.hasClassic, self.hasObserved = false, false
    local ordered = {}
    for index, tbl in ipairs(mob and mob.tables or {}) do
        local caption = String(R:GetTableLabel(tbl), "Loot table")
        local method = METHOD_NAMES[tbl.method] or String(tbl.method, "Loot")
        if not caption:lower():find(method:lower(), 1, true) then caption = method .. " · " .. caption end
        ordered[#ordered + 1] = {
            lootTable = tbl, caption = caption, method = tbl.method,
            methodRank = METHOD_ORDER[tbl.method] or 4, sourceRank = SOURCE_ORDER[tbl.provenance] or 4,
            level = R.Number(tbl.level) and tbl.level or math.huge,
            key = String(tbl.key, caption), originalIndex = index,
        }
    end
    table.sort(ordered, function(a, b)
        if a.methodRank ~= b.methodRank then return a.methodRank < b.methodRank end
        if a.sourceRank ~= b.sourceRank then return a.sourceRank < b.sourceRank end
        if a.level ~= b.level then return a.level < b.level end
        if a.key ~= b.key then return a.key < b.key end
        return a.originalIndex < b.originalIndex
    end)
    for _, section in ipairs(ordered) do
        local tbl, sorted = section.lootTable, {}
        for index, row in ipairs(R:DecodeRows(tbl)) do
            local base = R.Data.items and R.Data.items[row.itemID] or {}
            local name = String(row.name, String(base.name, "Item " .. tostring(row.itemID)))
            local chance = R:GetChance(row, tbl)
            sorted[#sorted + 1] = { row = row, chance = R.Number(chance) and chance or nil,
                name = R:Normalize(name), originalIndex = index }
        end
        table.sort(sorted, function(a, b)
            if a.chance ~= b.chance then
                if a.chance == nil then return false elseif b.chance == nil then return true end
                return a.chance > b.chance
            end
            if a.name ~= b.name then return a.name < b.name end
            if a.row.itemID ~= b.row.itemID then return a.row.itemID < b.row.itemID end
            return a.originalIndex < b.originalIndex
        end)
        section.color, section.chanceLabel = SourceStyle(tbl)
        section.count = #sorted
        section.summary = String(R:GetTableSummary(tbl, mob))
        section.note = String(R:DisplayText(tbl.note))
        local source = R:GetSourceInfo(tbl)
        section.sourceName = String(R:DisplayText(source.name))
        section.url = String(R:GetSourceURL(tbl, mob))
        self.hasClassic = self.hasClassic or tbl.provenance == "classic_reference"
        self.hasObserved = self.hasObserved or tbl.provenance == "forever_observed" or tbl.rateKind == "observed"
        self.sections[#self.sections + 1] = section
        self.entries[#self.entries + 1] = { kind = "header", section = section }
        for _, value in ipairs(sorted) do
            self.totalItems = self.totalItems + 1
            self.entries[#self.entries + 1] = { kind = "item", section = section,
                row = value.row, ordinal = self.totalItems }
        end
        if #sorted == 0 then self.entries[#self.entries + 1] = { kind = "empty", section = section } end
    end
    self.sectionCount = #self.sections
    self.maxOffset, self.offset = math.max(0, #self.entries - VISIBLE_ROWS), 0
end

function M:UpdateItem(widget)
    if not widget.entry or widget.entry.kind ~= "item" then return end
    local item = R:GetItem(widget.entry.row)
    widget.item = item
    widget.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    widget.nameText:SetText(String(item.name, "Unknown item"))
    widget.nameText:SetTextColor(ItemColor(item))
    widget.stripe:SetVertexColor(ItemColor(item))
end

-- Called by Core after an item-cache notification. Static source rows, chances,
-- their order and the scrollbar stay untouched; only visible metadata changes.
function M:RefreshItems()
    if not self:IsShown() then return end
    local hover = self.tooltipOwner
    for _, widget in ipairs(self.rows) do
        if widget.active and widget.entry and widget.entry.kind == "item" then self:UpdateItem(widget) end
    end
    if hover and hover.active and hover.entry and hover.entry.kind == "item" and GameTooltip then
        local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
        if not R.IsSecret(owner) and owner == hover then self:ShowTooltip(hover) end
    end
end

function M:Render()
    if not self:IsShown() then return end
    self:HideTooltip()
    local entries = self.entries or {}
    local first, last
    local context = entries[self.offset + 1]
    self.context:SetText(context and context.kind ~= "header" and context.section.caption or "ITEM")
    self.context:SetTextColor(UNPACK(context and context.kind ~= "header" and context.section.color or COLORS.muted))
    self.chanceHeading:SetText(context and context.section.chanceLabel or "CHANCE")
    for index, widget in ipairs(self.rows) do
        local entry = entries[self.offset + index]
        widget.entry, widget.item, widget.active = entry, nil, entry ~= nil
        widget:SetShown(entry ~= nil)
        widget.icon:SetShown(entry and entry.kind == "item" or false)
        if widget.save then widget.save:SetShown(entry and entry.kind == "item" or false) end
        if entry then
            widget.nameText:ClearAllPoints()
            widget.nameText:SetPoint("LEFT", entry.kind == "item" and 36 or 10, 0)
            widget.nameText:SetWidth(entry.kind == "item" and 375 or 435)
            if entry.kind == "item" then
                T:Row(widget, false, widget:IsMouseOver())
                self:UpdateItem(widget)
                widget.quantity:SetText(Quantity(entry.row))
                widget.chance:SetText(String(R:FormatChance(entry.row, entry.section.lootTable), "—"))
                widget.chance:SetTextColor(UNPACK(COLORS.text))
                first, last = first or entry.ordinal, entry.ordinal
            elseif entry.kind == "header" then
                T:Row(widget, true, false)
                widget.stripe:SetVertexColor(UNPACK(entry.section.color))
                widget.nameText:SetText(entry.section.caption)
                widget.nameText:SetTextColor(UNPACK(entry.section.color))
                widget.quantity:SetText(entry.section.count .. " entries")
                widget.chance:SetText(entry.section.chanceLabel)
                widget.chance:SetTextColor(UNPACK(entry.section.color))
            else
                T:Row(widget, false, false)
                widget.stripe:SetVertexColor(UNPACK(COLORS.muted))
                widget.nameText:SetText("No item entries are available for this source.")
                widget.nameText:SetTextColor(UNPACK(COLORS.muted))
                widget.quantity:SetText(""); widget.chance:SetText("")
            end
        else
            widget.icon:SetTexture(nil); widget.nameText:SetText("")
            widget.quantity:SetText(""); widget.chance:SetText("")
        end
    end
    self.empty:SetShown(#entries == 0)
    self.empty:SetText("No loot is known for this NPC yet. Readable creature loot you observe will be added automatically.")
    self.positionText:SetText(first and string.format("Entries %d–%d / %d · %d source sections", first, last,
        self.totalItems, self.sectionCount) or string.format("%d item entries · %d source sections", self.totalItems or 0, self.sectionCount or 0))
end

function M:ScrollTo(value)
    if not self:IsShown() or not R.Number(value) then return end
    local offset = Clamp(math.floor(value + 0.5), 0, self.maxOffset or 0)
    if offset == self.offset then return end
    self.offset = offset
    self.settingScroll = true
    self.scrollbar:SetValue(offset)
    self.settingScroll = nil
    self:Render()
end

function M:ScrollWheel(delta)
    if R.Number(delta) then self:ScrollTo((self.offset or 0) - delta * 3) end
end

function M:FinishMove()
    if not self.moving then return end
    self.frame:StopMovingOrSizing()
    self.moving = false
    local x, y = self.frame:GetCenter()
    local scale, parentScale = self.frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if R.Number(x) and R.Number(y) and R.Number(scale) and R.Number(parentScale) and parentScale > 0 then
        self.x = x * scale / parentScale - UIParent:GetWidth() / 2
        self.y = y * scale / parentScale - UIParent:GetHeight() / 2
    end
end

function M:FitWindow()
    if not self.frame then return end
    self:FinishMove()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not R.Number(width) or width <= 32 then width = WIDTH + 32 end
    if not R.Number(height) or height <= 32 then height = HEIGHT + 32 end
    local scale = math.min(1, (width - 32) / WIDTH, (height - 32) / HEIGHT)
    local maxX, maxY = math.max(0, (width - WIDTH * scale) / 2 - 12), math.max(0, (height - HEIGHT * scale) / 2 - 12)
    local x = Clamp(self.x or 0, -maxX, maxX)
    local y = Clamp(self.y or 0, -maxY, maxY)
    self.frame:SetScale(scale)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
end

function M:Release()
    self:FinishMove(); self:HideTooltip()
    for _, widget in ipairs(self.rows) do
        widget.entry, widget.item, widget.active = nil, nil, false
        widget.icon:SetTexture(nil); widget.nameText:SetText("")
        widget.quantity:SetText(""); widget.chance:SetText(""); widget:Hide()
    end
    self.npcID, self.mob, self.displayName = nil, nil, nil
    self.entries, self.sections = nil, nil
    self.totalItems, self.sectionCount, self.offset, self.maxOffset = 0, 0, 0, 0
    self.hasClassic, self.hasObserved = false, false
end

function M:Build()
    if self.frame then return end
    local frame = CreateFrame("Frame", "RicoLootMobWindow", UIParent)
    self.frame = frame
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG"); frame:SetFrameLevel(100)
    frame:SetToplevel(true); frame:SetMovable(true); frame:SetClampedToScreen(true); frame:EnableMouse(true)
    T:Window(frame)
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT"); drag:SetPoint("TOPRIGHT"); drag:SetHeight(77)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() M:HideTooltip(); frame:StartMoving(); M.moving = true end)
    drag:SetScript("OnDragStop", function() M:FinishMove() end)
    self.dragHandle = drag
    local brand = Text(frame, 23, COLORS.mint)
    brand:SetPoint("TOPLEFT", 24, -22)
    T:Title(brand, "LOOT")
    self.title = Text(frame, 14, COLORS.text)
    self.title:SetPoint("TOPLEFT", 24, -61); self.title:SetWidth(390)
    self.meta = Text(frame, 10, COLORS.muted, "RIGHT")
    self.meta:SetPoint("TOPRIGHT", -24, -63); self.meta:SetWidth(245)
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(72, 28); close:SetPoint("TOPRIGHT", -24, -29)
    close:SetFrameLevel(frame:GetFrameLevel() + 5); close:EnableMouse(true)
    close.background = T:Panel(close)
    close.label = Text(close, 11)
    close.label:SetPoint("CENTER"); close.label:SetText("Close")
    close:SetScript("OnClick", function() frame:Hide() end)
    T:Button(close, close.background)
    self.closeButton = close
    local wishlist = CreateFrame("Button", nil, frame)
    wishlist:SetSize(88, 28); wishlist:SetPoint("TOPRIGHT", -108, -29)
    wishlist.background = T:Panel(wishlist)
    wishlist.label = Text(wishlist, 11); wishlist.label:SetPoint("CENTER"); wishlist.label:SetText("Wishlist")
    wishlist:SetScript("OnClick", function() if R.Wishlist then R.Wishlist:Show() end end)
    T:Button(wishlist, wishlist.background)
    self.context = Text(frame, 10, COLORS.muted)
    self.context:SetPoint("TOPLEFT", 28, -83); self.context:SetWidth(435)
    self.quantityHeading = Text(frame, 10, COLORS.muted, "RIGHT")
    self.quantityHeading:SetPoint("TOPRIGHT", frame, "TOPLEFT", 553, -83); self.quantityHeading:SetText("QTY")
    self.chanceHeading = Text(frame, 10, COLORS.muted, "RIGHT")
    self.chanceHeading:SetPoint("TOPRIGHT", frame, "TOPLEFT", 649, -83); self.chanceHeading:SetWidth(88)
    self.chanceHeading:SetText("CHANCE")
    local view = CreateFrame("Frame", nil, frame)
    view:SetSize(VIEW_WIDTH, VIEW_HEIGHT); view:SetPoint("TOPLEFT", 18, -110)
    view:EnableMouse(true); view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta) M:ScrollWheel(delta) end)
    T:Panel(view)
    self.viewport = view
    for index = 1, VISIBLE_ROWS do
        local widget = CreateFrame("Frame", nil, view)
        widget:SetSize(VIEW_WIDTH, ROW_HEIGHT)
        widget:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        widget:EnableMouse(true); widget:EnableMouseWheel(true)
        widget.background = T:Panel(widget)
        T:Row(widget, false, false)
        widget.stripe = widget:CreateTexture(nil, "ARTWORK")
        widget.stripe:SetTexture(WHITE); widget.stripe:SetSize(2, 20); widget.stripe:SetPoint("LEFT", 0, 0)
        widget.icon = widget:CreateTexture(nil, "ARTWORK")
        widget.icon:SetSize(21, 21); widget.icon:SetPoint("LEFT", 6, 0); widget.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        widget.nameText = Text(widget, 11)
        widget.quantity = Text(widget, 10, COLORS.muted, "RIGHT")
        widget.quantity:SetPoint("RIGHT", -105, 0); widget.quantity:SetWidth(82)
        widget.chance = Text(widget, 10, COLORS.text, "RIGHT")
        widget.chance:SetPoint("RIGHT", -9, 0); widget.chance:SetWidth(88)
        widget:SetScript("OnEnter", function(self)
            T:Row(self, self.entry and self.entry.kind == "header", true)
            M:ShowTooltip(self)
        end)
        widget:SetScript("OnLeave", function(self)
            T:Row(self, self.entry and self.entry.kind == "header", false)
            M:HideTooltip(self)
        end)
        widget:SetScript("OnMouseWheel", function(_, delta) M:ScrollWheel(delta) end)
        local save = CreateFrame("Button", nil, widget)
        save:SetSize(21, 21); save:SetPoint("RIGHT", -194, 0)
        save.background = T:Panel(save)
        save.label = Text(save, 10); save.label:SetPoint("CENTER"); save.label:SetText("+")
        save:SetScript("OnClick", function()
            if widget.item and R.Wishlist then R.Wishlist:Add(widget.item.id); R.Wishlist:Show() end
        end)
        T:Button(save, save.background)
        widget.save = save
        widget:SetScript("OnMouseUp", function()
            if IsAltKeyDown and IsAltKeyDown() and widget.item and R.Wishlist then R.Wishlist:Add(widget.item.id); R.Wishlist:Show() end
        end)
        self.rows[index] = widget
    end
    local slider = CreateFrame("Slider", nil, frame)
    slider:SetSize(13, VIEW_HEIGHT); slider:SetPoint("TOPLEFT", 669, -110)
    slider:SetOrientation("VERTICAL"); slider:EnableMouse(true); slider:EnableMouseWheel(true)
    slider:SetMinMaxValues(0, 1); slider:SetValueStep(1); slider:SetObeyStepOnDrag(true)
    T:Panel(slider)
    slider:SetThumbTexture(WHITE)
    slider:GetThumbTexture():SetSize(11, 28); slider:GetThumbTexture():SetVertexColor(UNPACK(COLORS.mint))
    slider:SetScript("OnValueChanged", function(_, value) if not M.settingScroll then M:ScrollTo(value) end end)
    slider:SetScript("OnMouseWheel", function(_, delta) M:ScrollWheel(delta) end)
    self.scrollbar = slider
    self.empty = Text(view, 13, COLORS.muted, "CENTER")
    self.empty:SetPoint("CENTER"); self.empty:SetSize(530, 70); self.empty:SetWordWrap(true)
    self.positionText = Text(frame, 10, COLORS.muted)
    self.positionText:SetPoint("TOPLEFT", 21, -543); self.positionText:SetWidth(658)
    self.caveat = Text(frame, 10, COLORS.muted)
    self.caveat:SetPoint("TOPLEFT", 21, -566); self.caveat:SetSize(658, 30); self.caveat:SetWordWrap(true)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RicoLootMobWindow" end
    frame:SetScript("OnShow", function(self)
        self:RegisterEvent("DISPLAY_SIZE_CHANGED"); self:RegisterEvent("UI_SCALE_CHANGED")
        M:FitWindow(); M:Render()
    end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterEvent("DISPLAY_SIZE_CHANGED"); self:UnregisterEvent("UI_SCALE_CHANGED")
        M:Release()
    end)
    frame:SetScript("OnEvent", function() M:FitWindow() end)
    frame:Hide()
end

function M:Open(npcID, displayName)
    self:Build(); self:FinishMove(); self:HideTooltip()
    self:Prepare(npcID, displayName)
    self.title:SetText("Loot: " .. self.displayName)
    self.meta:SetText(string.format("All known loot · %d item entries", self.totalItems))
    local caveats = {}
    if self.hasClassic then caveats[#caveats + 1] = "Classic loot and rates may differ in Forever." end
    if self.hasObserved then caveats[#caveats + 1] = "Observations count opened loot windows." end
    caveats[#caveats + 1] = "Your sightings are positive evidence, not drop-rate estimates. — = unknown; * = conditional. Sources are listed separately."
    self.caveat:SetText(table.concat(caveats, " "))
    self.caveat:SetTextColor(UNPACK(self.hasClassic and COLORS.amber or COLORS.muted))
    self.settingScroll = true
    self.scrollbar:SetMinMaxValues(0, math.max(1, self.maxOffset))
    self.scrollbar:SetValue(0)
    self.scrollbar:GetThumbTexture():SetHeight(math.max(22, VIEW_HEIGHT * math.min(1, VISIBLE_ROWS / math.max(1, #self.entries))))
    self.scrollbar:SetShown(self.maxOffset > 0)
    self.settingScroll = nil
    local shown = self.frame:IsShown()
    self.frame:Show()
    if shown then self:Render() end
    return true
end

function R:OpenMobLoot(npcID, displayName)
    if not self.Number(npcID) or npcID <= 0 or npcID ~= math.floor(npcID) then return false end
    return M:Open(npcID, displayName)
end
