-- A lazy, local browser. All catalog filtering, source selection and chance
-- interpretation belong to Core.lua; this file never joins loot datasets.
-- Copyright (C) 2026 Rico. Distributed under GNU GPL version 3 or later.
local _, RL = ...
local T = RL.Theme
local U = {
    mobPage = 1, lootPage = 1, zonePage = 1,
    mobQuery = "", itemQuery = "", zoneQuery = "", sort = "chance",
    mobRows = {}, lootRows = {}, zoneRows = {},
}
RL.UI = U

local WIDTH, HEIGHT = 1060, 650
local MOB_ROWS, LOOT_ROWS, ZONE_ROWS = 10, 9, 8
local FONT, WHITE = T.font, "Interface\\Buttons\\WHITE8X8"
local UNPACK = unpack or table.unpack
local COLORS = T.colors
local SORTS, SORT_LABELS = {"chance", "name", "quality"},
    {chance = "chance", name = "name", quality = "quality"}

local function Secret(value) return issecretvalue and issecretvalue(value) or false end
local function Number(value)
    return not Secret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function String(value, fallback)
    return not Secret(value) and type(value) == "string" and value or (fallback or "")
end
local function List(value)
    return not Secret(value) and type(value) == "table"
        and (not canaccesstable or canaccesstable(value)) and value or {}
end
local function Clamp(value, lower, upper) return math.max(lower, math.min(upper, value)) end

local function Fill(parent, r, g, b, a)
    return T:Fill(parent, r, g, b, a)
end

local function Text(parent, size, color, align)
    local surface = parent.ricoForeground or parent
    local text = surface:CreateFontString(nil, "OVERLAY")
    if parent.ricoForeground then
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
    end
    text:SetFont(FONT, size or 12, "")
    text:SetTextColor(UNPACK(color or COLORS.text))
    text:SetJustifyH(align or "LEFT")
    return text
end

local function Button(parent, label, width, height, click)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height or 26)
    button:EnableMouse(true)
    button.background = T:Panel(button)
    button.label = Text(button, 11)
    button.label:SetPoint("LEFT", 8, 0)
    button.label:SetPoint("RIGHT", -8, 0)
    button.label:SetJustifyH("CENTER")
    button.label:SetWordWrap(false)
    button.label:SetText(label)
    button:SetScript("OnClick", click)
    T:Button(button, button.background)
    return button
end

local function Enable(button, enabled)
    button:SetEnabled(enabled and true or false)
    T:PaintButton(button)
end

local function Input(parent, width, hint, changed)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 26)
    box:EnableMouse(true)
    box:SetAutoFocus(false)
    box:SetFont(FONT, 12, "")
    box:SetMaxLetters(120)
    T:Input(box)
    box.hint = Text(box, 11, COLORS.muted)
    box.hint:SetPoint("LEFT", 8, 0)
    box.hint:SetPoint("RIGHT", -8, 0)
    box.hint:SetWordWrap(false)
    box.hint:SetText(hint or "")
    box:SetText("")
    box:SetScript("OnTextChanged", function(self)
        local value = String(self:GetText())
        self.hint:SetShown(value == "")
        if not U.building and not U.updatingInputs and changed then changed(value) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if U.frame then U.frame:Hide() end
    end)
    return box
end

local function SetInput(box, value)
    if not box then return end
    U.updatingInputs = true
    box:SetText(value)
    box.hint:SetShown(value == "")
    U.updatingInputs = nil
end

local function LevelText(mob)
    local low, high = mob and mob.minLevel, mob and mob.maxLevel
    if not Number(low) or low <= 0 then low = nil end
    if not Number(high) or high <= 0 then high = nil end
    if low and high then
        return low == high and string.format("Level %d", low) or string.format("Level %d–%d", low, high)
    end
    if low then return string.format("Level %d+", low) end
    if high then return string.format("Up to level %d", high) end
    return "Unknown level"
end

local function SourceStyle(tbl)
    if tbl and tbl.provenance == "local_observed" then return COLORS.mint, "YOUR OBSERVED DROPS" end
    if tbl and tbl.provenance == "classic_reference" then return COLORS.amber, "CLASSIC REFERENCE" end
    if tbl and tbl.provenance == "forever_observed" then return COLORS.mint, "FOREVER · OBSERVED" end
    if tbl and tbl.provenance == "forever_reference" then return COLORS.blue, "FOREVER · REFERENCE" end
    return COLORS.muted, "UNKNOWN SOURCE"
end

local function ItemColor(item)
    local quality = item and item.quality
    local color = Number(quality) and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and not Secret(color) and type(color) == "table" and (not canaccesstable or canaccesstable(color))
        and Number(color.r) and Number(color.g) and Number(color.b) then
        return color.r, color.g, color.b
    end
    return UNPACK(COLORS.text)
end

local function Quantity(row)
    local low, high = row.quantityMin, row.quantityMax
    if not Number(low) then low = nil end
    if not Number(high) then high = nil end
    if low and high then return low == high and string.format("%g", low) or string.format("%g–%g", low, high) end
    if low then return string.format("%g", low) end
    if high then return string.format("≤%g", high) end
    return "—"
end

function U:HideTooltip(owner)
    if not self.tooltipOwner or (owner and self.tooltipOwner ~= owner) then return end
    if GameTooltip then
        local current = GameTooltip.GetOwner and GameTooltip:GetOwner()
        if not Secret(current) and current == self.tooltipOwner then GameTooltip:Hide() end
    end
    self.tooltipOwner = nil
end

function U:ShowTextTooltip(owner, title, detail)
    if not GameTooltip then return end
    self:HideTooltip()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText(String(title))
    if String(detail) ~= "" then GameTooltip:AddLine(detail, 0.78, 0.85, 0.89, true) end
    GameTooltip:Show()
    self.tooltipOwner = owner
end

function U:ShowItemTooltip(button)
    if not button.row or not button.item or not button.lootTable or not GameTooltip then return end
    self:HideTooltip()
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local item, applied = button.item, false
    local link = String(item.link)
    if link ~= "" and type(GameTooltip.SetHyperlink) == "function" then
        applied = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    elseif Number(item.id) and type(GameTooltip.SetItemByID) == "function" then
        applied = pcall(GameTooltip.SetItemByID, GameTooltip, item.id)
    end
    if not applied then GameTooltip:SetText(String(item.name, "Unknown item")) end
    local color = SourceStyle(button.lootTable)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(String(RL:GetTableLabel(button.lootTable)), color[1], color[2], color[3], true)
    local detail = String(RL:GetChanceDetails(button.row, button.lootTable))
    if detail ~= "" then GameTooltip:AddLine(detail, 0.79, 0.86, 0.90, true) end
    if link ~= "" and type(HandleModifiedItemClick) == "function" then
        GameTooltip:AddLine("Alt-click / +: save farming goal • Shift-click: link • Ctrl-click: dress up", 0.49, 0.77, 0.69, true)
    end
    GameTooltip:Show()
    self.tooltipOwner = button
end

function U:Notice(message)
    self.notice = String(message)
    if self.footer then self.footer:SetText(self.notice) end
end

function U:UseCurrentZone()
    local ok, message = RL:UseCurrentZone()
    if ok then
        self.mobPage, self.lootPage = 1, 1
        self:CloseZones()
        self.notice = nil
        self:Refresh()
    elseif String(message) ~= "" then
        self:Notice(message)
    end
end

function U:ChooseZone(id)
    self.mobPage, self.lootPage = 1, 1
    self.notice = nil
    self:CloseZones()
    RL:SetZone(id)
    self:Refresh()
end

function U:ChooseMob(id)
    self.lootPage, self.itemQuery, self.notice = 1, "", nil
    SetInput(self.itemSearch, "")
    RL:SelectMob(id)
    self:Refresh()
end

function U:CycleTable(direction)
    local count = self.tableCount or 0
    if count < 2 then return end
    local index = ((self.tableIndex or 1) - 1 + direction) % count + 1
    self.lootPage, self.notice = 1, nil
    RL:SetTable(index)
    self:Refresh()
end

function U:TurnPage(which, direction)
    local key, maximum = which == "mob" and "mobPage" or "lootPage",
        which == "mob" and (self.mobPages or 1) or (self.lootPages or 1)
    self[key] = Clamp(self[key] + direction, 1, maximum)
    self:Refresh()
end

function U:SavePosition()
    if not self.frame or not RL.db then return end
    if type(RL.SaveWindow) == "function" then RL:SaveWindow(self.frame); return end
    local x, y = self.frame:GetCenter()
    local scale, parentScale = self.frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if Number(x) and Number(y) and Number(scale) and Number(parentScale) and parentScale > 0 then
        RL.db.x = x * scale / parentScale - UIParent:GetWidth() / 2
        RL.db.y = y * scale / parentScale - UIParent:GetHeight() / 2
    end
end

function U:FinishMove()
    if not self.moving then return end
    self.frame:StopMovingOrSizing()
    self.moving = false
    self:SavePosition()
end

function U:FitWindow()
    if not self.frame or not RL.db then return end
    self:FinishMove()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not Number(width) or width <= 32 then width = WIDTH + 32 end
    if not Number(height) or height <= 32 then height = HEIGHT + 32 end
    local scale = math.min(1, (width - 32) / WIDTH, (height - 32) / HEIGHT)
    local maxX, maxY = math.max(0, (width - WIDTH * scale) / 2 - 12),
        math.max(0, (height - HEIGHT * scale) / 2 - 12)
    local x = Clamp(Number(RL.db.x) and RL.db.x or 0, -maxX, maxX)
    local y = Clamp(Number(RL.db.y) and RL.db.y or 0, -maxY, maxY)
    self.frame:SetScale(scale)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
end

function U:CloseZones()
    if self.zoneSearch then self.zoneSearch:ClearFocus() end
    if self.zoneShield then self.zoneShield:Hide() end
end

function U:BuildZones()
    if self.zoneShield then return end
    local shield = CreateFrame("Frame", nil, self.frame)
    shield:SetAllPoints(self.frame)
    shield:SetFrameLevel(self.frame:GetFrameLevel() + 40)
    shield:EnableMouse(true)
    shield:SetScript("OnMouseDown", function() U:CloseZones() end)
    self.zoneShield = shield
    local panel = CreateFrame("Frame", nil, shield)
    panel:SetSize(366, 390)
    panel:SetPoint("TOPLEFT", self.zoneButton, "BOTTOMLEFT", 0, -6)
    panel:SetFrameLevel(shield:GetFrameLevel() + 2)
    panel:EnableMouse(true)
    T:Window(panel, true)
    self.zonePopup = panel
    local all = Button(panel, "All zones", 166, 26, function() U:ChooseZone(0) end)
    all:SetPoint("TOPLEFT", 12, -12)
    self.allZonesButton = all
    local current = Button(panel, "Current zone", 166, 26, function() U:UseCurrentZone() end)
    current:SetPoint("TOPRIGHT", -12, -12)
    self.zoneSearch = Input(panel, 332, "Search zones...", function(value)
        U.zoneQuery, U.zonePage = value, 1
        U:RefreshZones()
    end)
    self.zoneSearch:SetPoint("TOPLEFT", 20, -49)
    self.zoneSearch:SetScript("OnEscapePressed", function() U:CloseZones() end)
    for index = 1, ZONE_ROWS do
        local row = Button(panel, "", 342, 30, function(self) if self.zone then U:ChooseZone(self.zone.id) end end)
        row:SetPoint("TOPLEFT", 12, -87 - (index - 1) * 32)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 9, 0)
        row.label:SetWidth(270)
        row.label:SetJustifyH("LEFT")
        row.count = Text(row, 10, COLORS.muted, "RIGHT")
        row.count:SetPoint("RIGHT", -9, 0)
        row.count:SetWidth(47)
        self.zoneRows[index] = row
    end
    self.zoneEmpty = Text(panel, 12, COLORS.muted)
    self.zoneEmpty:SetPoint("TOPLEFT", 20, -112)
    self.zoneEmpty:SetText("No matching zones found.")
    self.zonePrevious = Button(panel, "<", 36, 24, function()
        U.zonePage = math.max(1, U.zonePage - 1); U:RefreshZones()
    end)
    self.zonePrevious:SetPoint("BOTTOMLEFT", 12, 12)
    self.zoneNext = Button(panel, ">", 36, 24, function()
        U.zonePage = math.min(U.zonePages or 1, U.zonePage + 1); U:RefreshZones()
    end)
    self.zoneNext:SetPoint("BOTTOMRIGHT", -12, 12)
    self.zonePageText = Text(panel, 11, COLORS.muted, "CENTER")
    self.zonePageText:SetPoint("BOTTOM", 0, 18)
    shield:Hide()
end

function U:RefreshZones()
    if not self.zoneShield or not self.zoneShield:IsShown() then return end
    self.allZonesButton.selected = RL.db.zoneID == 0
    self.allZonesButton.ricoLabelColor = self.allZonesButton.selected and COLORS.mint or COLORS.text
    T:PaintButton(self.allZonesButton)
    local matches = {}
    for _, zone in ipairs(List(RL:GetZones(self.zoneQuery))) do
        if zone.id ~= 0 then matches[#matches + 1] = zone end
    end
    self.zonePages = math.max(1, math.ceil(#matches / ZONE_ROWS))
    self.zonePage = Clamp(self.zonePage, 1, self.zonePages)
    for index, row in ipairs(self.zoneRows) do
        local zone = matches[(self.zonePage - 1) * ZONE_ROWS + index]
        row.zone = zone
        row:SetShown(zone ~= nil)
        if zone then
            row.label:SetText(String(zone.name, "Unknown zone"))
            row.count:SetText(Number(zone.count) and tostring(zone.count) or "")
            row.selected = zone.id == RL.db.zoneID
            row.ricoLabelColor = row.selected and COLORS.mint or COLORS.text
            T:PaintButton(row)
        end
    end
    self.zoneEmpty:SetShown(#matches == 0)
    self.zonePageText:SetText(string.format("%d / %d · %d zones", self.zonePage, self.zonePages, #matches))
    Enable(self.zonePrevious, self.zonePage > 1)
    Enable(self.zoneNext, self.zonePage < self.zonePages)
end

function U:ToggleZones()
    self:BuildZones()
    if self.zoneShield:IsShown() then self:CloseZones(); return end
    self.zonePage, self.zoneQuery = 1, ""
    SetInput(self.zoneSearch, "")
    self.zoneShield:Show()
    self:RefreshZones()
    self.zoneSearch:SetFocus()
end

function U:CloseSource()
    if self.sourceEdit then self.sourceEdit:ClearFocus() end
    if self.sourceShield then self.sourceShield:Hide() end
end

function U:CopySource()
    local mob, tbl = RL:GetSelectedMob(), RL:GetSelectedTable()
    local url = String(RL:GetSourceURL(tbl, mob))
    if url == "" then self:Notice("No link is available for this source."); return end
    self:CloseZones()
    if not self.sourceShield then
        local shield = CreateFrame("Frame", nil, self.frame)
        shield:SetAllPoints(self.frame)
        shield:SetFrameLevel(self.frame:GetFrameLevel() + 80)
        shield:EnableMouse(true)
        Fill(shield, 0, 0, 0, 0.45)
        shield:SetScript("OnMouseDown", function() U:CloseSource() end)
        self.sourceShield = shield
        local panel = CreateFrame("Frame", nil, shield)
        panel:SetSize(720, 116)
        panel:SetPoint("CENTER")
        panel:SetFrameLevel(shield:GetFrameLevel() + 2)
        panel:EnableMouse(true)
        T:Window(panel, true)
        local title = Text(panel, 14, COLORS.mint)
        title:SetPoint("TOPLEFT", 18, -16)
        title:SetText("Loot table source")
        local hint = Text(panel, 11, COLORS.muted)
        hint:SetPoint("BOTTOMLEFT", 20, 13)
        hint:SetText("Press Ctrl+C to copy, then paste the link into your browser.")
        self.sourceEdit = Input(panel, 672, "")
        self.sourceEdit:SetMaxLetters(2048)
        self.sourceEdit:SetPoint("TOPLEFT", 24, -48)
        self.sourceEdit:SetScript("OnEscapePressed", function() U:CloseSource() end)
        local close = Button(panel, "Close", 68, 23, function() U:CloseSource() end)
        close:SetPoint("TOPRIGHT", -14, -12)
        shield:Hide()
    end
    SetInput(self.sourceEdit, url)
    self.sourceShield:Show()
    self.sourceEdit:SetFocus()
    self.sourceEdit:HighlightText()
end

function U:Build()
    if self.frame then return end
    self.building = true
    local frame = CreateFrame("Frame", "RicoLootWindow", UIParent)
    self.frame = frame
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    local function startMove()
        U:CloseZones(); U:CloseSource(); U:HideTooltip()
        frame:StartMoving(); U.moving = true
    end
    frame:SetScript("OnDragStart", startMove)
    frame:SetScript("OnDragStop", function() U:FinishMove() end)
    T:Window(frame)
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT"); drag:SetPoint("TOPRIGHT"); drag:SetHeight(74)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", startMove)
    drag:SetScript("OnDragStop", function() U:FinishMove() end)
    self.dragHandle = drag
    local title = Text(frame, 23, COLORS.mint)
    title:SetPoint("TOPLEFT", 24, -22)
    T:Title(title, "LOOT")
    local subtitle = Text(frame, 12, COLORS.muted)
    subtitle:SetPoint("TOPLEFT", 24, -57)
    local snapshot = RL.Data and RL.Data.remoteSnapshot
    subtitle:SetText("Loot browser · WoW Forever" .. (snapshot and snapshot.dataAsOf
        and " · Everloot " .. snapshot.dataAsOf:sub(1, 10) or ""))
    self.coverage = Text(frame, 10, COLORS.muted)
    self.coverage:SetPoint("TOPRIGHT", -24, -59)
    self.coverage:SetWidth(700)
    self.coverage:SetJustifyH("RIGHT")
    self.coverage:SetWordWrap(false)
    self.closeButton = Button(frame, "Close", 72, 28, function() frame:Hide() end)
    self.closeButton:SetFrameLevel(frame:GetFrameLevel() + 5)
    self.closeButton:SetPoint("TOPRIGHT", -24, -29)
    self.wishlistButton = Button(frame, "Wishlist", 88, 28, function() if RL.Wishlist then RL.Wishlist:Show() end end)
    self.wishlistButton:SetFrameLevel(frame:GetFrameLevel() + 5)
    self.wishlistButton:SetPoint("TOPRIGHT", -108, -29)
    self.databaseButton = Button(frame, "Database", 104, 28, function() if RL.Database then RL.Database:Show() end end)
    self.databaseButton:SetFrameLevel(frame:GetFrameLevel() + 5)
    self.databaseButton:SetPoint("TOPRIGHT", -300, -29)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RicoLootWindow" end

    self.zoneButton = Button(frame, "All zones", 345, 29, function() U:ToggleZones() end)
    self.zoneButton:SetPoint("TOPLEFT", 20, -80)
    self.zoneButton.label:SetJustifyH("LEFT")
    self.zoneButton.label:SetPoint("RIGHT", -26, 0)
    local arrow = Text(self.zoneButton, 12, COLORS.mint)
    arrow:SetPoint("RIGHT", -10, 0); arrow:SetText("▾")
    self.currentZoneButton = Button(frame, "Current zone", 116, 29, function() U:UseCurrentZone() end)
    self.currentZoneButton:SetPoint("TOPLEFT", 375, -80)
    self.targetButton = Button(frame, "Selected target", 140, 29, function()
        local ok, message = RL:SelectTarget()
        if ok then U.mobPage, U.lootPage, U.notice = 1, 1, nil; U:Refresh()
        elseif String(message) ~= "" then U:Notice(message) end
    end)
    self.targetButton:SetPoint("TOPLEFT", 501, -80)
    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(24, 24); check:SetPoint("TOPLEFT", 683, -83)
    T:Check(check)
    check.label = Text(frame, 11, COLORS.amber)
    check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.label:SetText("Include Classic reference")
    check:SetScript("OnClick", function(self)
        U.mobPage, U.lootPage, U.notice = 1, 1, nil
        RL:SetOption("includeReference", self:GetChecked() and true or false)
        U:Refresh()
    end)
    self.referenceCheck = check

    local left = CreateFrame("Frame", nil, frame)
    left:SetSize(304, 486); left:SetPoint("TOPLEFT", 18, -124)
    T:Panel(left)
    local right = CreateFrame("Frame", nil, frame)
    right:SetSize(708, 486); right:SetPoint("TOPLEFT", 334, -124)
    T:Panel(right)
    local mobHeading = Text(frame, 14)
    mobHeading:SetPoint("TOPLEFT", 32, -137); mobHeading:SetText("Creatures")
    self.mobCount = Text(frame, 11, COLORS.muted, "RIGHT")
    self.mobCount:SetPoint("TOPRIGHT", frame, "TOPLEFT", 307, -140)
    self.mobSearch = Input(frame, 271, "Creature name or NPC ID", function(value)
        U.mobQuery, U.mobPage, U.notice = value, 1, nil; RL:RequestRefresh()
    end)
    self.mobSearch:SetPoint("TOPLEFT", 36, -168)
    local mobHint = Text(frame, 10, COLORS.muted)
    mobHint:SetPoint("TOPLEFT", 33, -203)
    mobHint:SetText("Select a creature to browse its loot")
    for index = 1, MOB_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(280, 32); row:SetPoint("TOPLEFT", 30, -225 - (index - 1) * 34)
        row:EnableMouse(true)
        row.background = T:Panel(row)
        T:Row(row, false, false)
        row.nameText = Text(row, 11)
        row.nameText:SetPoint("TOPLEFT", 8, -4); row.nameText:SetWidth(263); row.nameText:SetWordWrap(false)
        row.detail = Text(row, 9, COLORS.muted)
        row.detail:SetPoint("BOTTOMLEFT", 8, 4); row.detail:SetWidth(263); row.detail:SetWordWrap(false)
        row:SetScript("OnClick", function(self) if self.mob then U:ChooseMob(self.mob.id) end end)
        row:SetScript("OnEnter", function(self)
            T:Row(self, self.selected, true)
            if self.mob then U:ShowTextTooltip(self, String(self.mob.name), LevelText(self.mob) .. " · NPC-ID " .. tostring(self.mob.id)) end
        end)
        row:SetScript("OnLeave", function(self)
            U:HideTooltip(self)
            T:Row(self, self.selected, false)
        end)
        self.mobRows[index] = row
    end
    self.mobEmpty = Text(frame, 12, COLORS.muted)
    self.mobEmpty:SetPoint("TOPLEFT", 40, -270); self.mobEmpty:SetWidth(258); self.mobEmpty:SetWordWrap(true)
    self.mobPrevious = Button(frame, "<", 35, 24, function() U:TurnPage("mob", -1) end)
    self.mobPrevious:SetPoint("TOPLEFT", 31, -575)
    self.mobNext = Button(frame, ">", 35, 24, function() U:TurnPage("mob", 1) end)
    self.mobNext:SetPoint("TOPLEFT", 275, -575)
    self.mobPageText = Text(frame, 11, COLORS.muted, "CENTER")
    self.mobPageText:SetPoint("TOP", frame, "TOPLEFT", 171, -581)

    self.mobTitle = Text(frame, 20)
    self.mobTitle:SetPoint("TOPLEFT", 350, -136); self.mobTitle:SetWidth(580); self.mobTitle:SetWordWrap(false)
    self.mobMeta = Text(frame, 11, COLORS.muted)
    self.mobMeta:SetPoint("TOPLEFT", 351, -164); self.mobMeta:SetWidth(335); self.mobMeta:SetWordWrap(false)
    self.sourceStatus = Text(frame, 10, COLORS.amber, "RIGHT")
    self.sourceStatus:SetPoint("TOPRIGHT", -35, -165); self.sourceStatus:SetWidth(328); self.sourceStatus:SetWordWrap(false)
    self.sourceButton = Button(frame, "Source", 66, 24, function() U:CopySource() end)
    self.sourceButton:SetPoint("TOPRIGHT", -34, -136)
    self.tablePrevious = Button(frame, "<", 32, 27, function() U:CycleTable(-1) end)
    self.tablePrevious:SetPoint("TOPLEFT", 350, -189)
    self.tableButton = Button(frame, "No loot table", 600, 27, function() U:CycleTable(1) end)
    self.tableButton:SetPoint("TOPLEFT", 388, -189)
    self.tableButton.label:SetJustifyH("LEFT")
    self.tableButton:HookScript("OnEnter", function(self)
        if U.displayTable then U:ShowTextTooltip(self, RL:GetTableLabel(U.displayTable), RL:GetTableSummary(U.displayTable, U.displayMob)) end
    end)
    self.tableButton:HookScript("OnLeave", function(self) U:HideTooltip(self) end)
    self.tableNext = Button(frame, ">", 32, 27, function() U:CycleTable(1) end)
    self.tableNext:SetPoint("TOPLEFT", 994, -189)
    self.tableSummary = Text(frame, 11, COLORS.muted)
    self.tableSummary:SetPoint("TOPLEFT", 351, -224); self.tableSummary:SetSize(675, 32); self.tableSummary:SetWordWrap(true)
    self.itemSearch = Input(frame, 510, "Search this table by item name or ID", function(value)
        U.itemQuery, U.lootPage, U.notice = value, 1, nil; RL:RequestRefresh()
    end)
    self.itemSearch:SetPoint("TOPLEFT", 356, -269)
    self.sortButton = Button(frame, "Sort: chance", 148, 26, function()
        local index = 1
        for i, value in ipairs(SORTS) do if value == U.sort then index = i end end
        U.sort, U.lootPage = SORTS[index % #SORTS + 1], 1
        U:Refresh()
    end)
    self.sortButton:SetPoint("TOPLEFT", 878, -269)
    local itemHeading = Text(frame, 10, COLORS.muted)
    itemHeading:SetPoint("TOPLEFT", 389, -310); itemHeading:SetText("ITEM")
    local quantityHeading = Text(frame, 10, COLORS.muted, "RIGHT")
    quantityHeading:SetPoint("TOPRIGHT", frame, "TOPLEFT", 922, -310); quantityHeading:SetText("QTY")
    local chanceHeading = Text(frame, 10, COLORS.muted, "RIGHT")
    chanceHeading:SetPoint("TOPRIGHT", frame, "TOPLEFT", 1017, -310); chanceHeading:SetText("CHANCE")
    self.chanceHeading = chanceHeading
    for index = 1, LOOT_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(676, 26); row:SetPoint("TOPLEFT", 350, -331 - (index - 1) * 26)
        row:EnableMouse(true)
        row.background = T:Panel(row)
        T:Row(row, false, false)
        row.stripe = row:CreateTexture(nil, "ARTWORK")
        row.stripe:SetTexture(WHITE); row.stripe:SetSize(2, 18); row.stripe:SetPoint("LEFT", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(21, 21); row.icon:SetPoint("LEFT", 6, 0); row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.nameText = Text(row, 11)
        row.nameText:SetPoint("LEFT", 36, 0); row.nameText:SetWidth(410); row.nameText:SetWordWrap(false)
        row.quantity = Text(row, 10, COLORS.muted, "RIGHT")
        row.quantity:SetPoint("RIGHT", -104, 0); row.quantity:SetWidth(82)
        row.chance = Text(row, 11, COLORS.text, "RIGHT")
        row.chance:SetPoint("RIGHT", -9, 0); row.chance:SetWidth(88)
        row:SetScript("OnEnter", function(self) T:Row(self, false, true); U:ShowItemTooltip(self) end)
        row:SetScript("OnLeave", function(self) T:Row(self, false, false); U:HideTooltip(self) end)
        row.save = Button(row, "+", 21, 21, function()
            if row.item and RL.Wishlist then RL.Wishlist:Add(row.item.id); RL.Wishlist:Show() end
        end)
        row.save:SetPoint("RIGHT", -194, 0)
        row:SetScript("OnClick", function(self)
            if IsAltKeyDown and IsAltKeyDown() and self.item and RL.Wishlist then RL.Wishlist:Add(self.item.id); RL.Wishlist:Show(); return end
            local link = self.item and String(self.item.link)
            if link and link ~= "" and type(HandleModifiedItemClick) == "function" then pcall(HandleModifiedItemClick, link) end
        end)
        self.lootRows[index] = row
    end
    self.lootEmpty = Text(frame, 13, COLORS.muted, "CENTER")
    self.lootEmpty:SetPoint("TOPLEFT", 390, -392); self.lootEmpty:SetSize(588, 80); self.lootEmpty:SetWordWrap(true)
    self.lootPrevious = Button(frame, "<", 35, 24, function() U:TurnPage("loot", -1) end)
    self.lootPrevious:SetPoint("TOPLEFT", 350, -575)
    self.lootNext = Button(frame, ">", 35, 24, function() U:TurnPage("loot", 1) end)
    self.lootNext:SetPoint("TOPLEFT", 991, -575)
    self.lootPageText = Text(frame, 11, COLORS.muted, "CENTER")
    self.lootPageText:SetPoint("TOP", frame, "TOPLEFT", 688, -581)
    self.footer = Text(frame, 10, COLORS.muted)
    self.footer:SetPoint("TOPLEFT", 21, -624); self.footer:SetWidth(1016); self.footer:SetWordWrap(false)

    frame:SetScript("OnShow", function(self)
        self:RegisterEvent("DISPLAY_SIZE_CHANGED"); self:RegisterEvent("UI_SCALE_CHANGED")
        U:FitWindow(); U:Refresh()
    end)
    frame:SetScript("OnEvent", function() U:FitWindow() end)
    frame:SetScript("OnHide", function(self)
        U:FinishMove(); U:HideTooltip(); U:CloseZones(); U:CloseSource()
        if U.mobSearch then U.mobSearch:ClearFocus() end
        if U.itemSearch then U.itemSearch:ClearFocus() end
        self:UnregisterEvent("DISPLAY_SIZE_CHANGED"); self:UnregisterEvent("UI_SCALE_CHANGED")
    end)
    frame:Hide()
    self.building = false
    self:FitWindow()
end

function U:Refresh()
    if self.building or self.refreshing or not RL.db or not self.frame or not self.frame:IsShown() then return end
    self.refreshing = true
    self:HideTooltip()
    local zones = List(RL:GetZones(""))
    local zoneName = RL.db.zoneID == 0 and "All zones" or "Selected zone"
    for _, zone in ipairs(zones) do if zone.id == RL.db.zoneID then zoneName = String(zone.name, zoneName); break end end
    self.zoneButton.label:SetText(zoneName)
    self.referenceCheck:SetChecked(RL.db.includeReference and true or false)
    self.coverage:SetText(String(RL:GetCoverageText()))
    local mobs = List(RL:GetMobs(RL.db.zoneID, self.mobQuery))
    self.mobPages = math.max(1, math.ceil(#mobs / MOB_ROWS))
    self.mobPage = Clamp(self.mobPage, 1, self.mobPages)
    local mob = RL:GetSelectedMob()
    local mobID = mob and mob.id
    if self.displayMobID ~= mobID then
        self.lootPage, self.itemQuery = 1, ""
        SetInput(self.itemSearch, "")
    end
    self.displayMob, self.displayMobID = mob, mobID
    self.mobCount:SetText(string.format("%d found", #mobs))
    for index, row in ipairs(self.mobRows) do
        local entry = mobs[(self.mobPage - 1) * MOB_ROWS + index]
        row.mob = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.selected = entry.id == mobID
            row.nameText:SetText(String(entry.name, "Unknown creature"))
            row.nameText:SetTextColor(UNPACK(row.selected and COLORS.mint or COLORS.text))
            row.detail:SetText(LevelText(entry) .. " · NPC-ID " .. tostring(entry.id))
            T:Row(row, row.selected, row:IsMouseOver())
        end
    end
    self.mobEmpty:SetShown(#mobs == 0)
    self.mobEmpty:SetText(RL.db.includeReference and "No creatures found. Change the zone or search term."
        or "No creatures found. Change the zone or search term; Classic references are disabled.")
    self.mobPageText:SetText(string.format("%d / %d", self.mobPage, self.mobPages))
    Enable(self.mobPrevious, self.mobPage > 1); Enable(self.mobNext, self.mobPage < self.mobPages)

    local tables = mob and List(RL:GetTables(mob)) or {}
    local tbl = mob and RL:GetSelectedTable() or nil
    if self.displayTable ~= tbl then self.lootPage = 1 end
    self.displayTable, self.tableCount, self.tableIndex = tbl, #tables, 1
    for index, value in ipairs(tables) do if value == tbl then self.tableIndex = index; break end end
    self.mobTitle:SetText(mob and String(mob.name, "Unknown creature") or "Select a creature")
    self.mobMeta:SetText(mob and (LevelText(mob) .. " · NPC-ID " .. tostring(mob.id)) or "Prefilled loot, grouped by source")
    local color, status = SourceStyle(tbl)
    self.sourceStatus:SetText(tbl and status or "")
    self.sourceStatus:SetTextColor(UNPACK(color))
    local label = tbl and String(RL:GetTableLabel(tbl), "Loot table") or "No loot table available"
    self.tableButton.label:SetText(tbl and string.format("%d/%d · %s", self.tableIndex, #tables, label) or label)
    self.tableButton.ricoLabelColor = color
    Enable(self.tablePrevious, #tables > 1); Enable(self.tableNext, #tables > 1); Enable(self.tableButton, #tables > 1)
    self.tableSummary:SetText(tbl and String(RL:GetTableSummary(tbl, mob)) or "Select a creature, then choose a source, level group and loot method.")
    self.chanceHeading:SetText(tbl and tbl.provenance == "local_observed" and "SEEN"
        or tbl and tbl.provenance == "classic_reference" and "BASE RATE"
        or tbl and (tbl.rateKind == "observed" or tbl.provenance == "forever_observed") and "OBSERVED %" or "CHANCE")
    Enable(self.sourceButton, tbl and String(RL:GetSourceURL(tbl, mob)) ~= "")
    self.sortButton.label:SetText("Sort: " .. SORT_LABELS[self.sort])

    local rows = tbl and List(RL:GetLootRows(tbl, self.itemQuery, self.sort)) or {}
    local total = self.itemQuery ~= "" and tbl and #List(RL:GetLootRows(tbl, "", self.sort)) or #rows
    self.lootPages = math.max(1, math.ceil(#rows / LOOT_ROWS))
    self.lootPage = Clamp(self.lootPage, 1, self.lootPages)
    for index, button in ipairs(self.lootRows) do
        local row = rows[(self.lootPage - 1) * LOOT_ROWS + index]
        button.row, button.lootTable, button.item = row, tbl, nil
        button:SetShown(row ~= nil)
        if row then
            local item = RL:GetItem(row)
            button.item = item
            button.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            button.nameText:SetText(String(item.name, "Unknown item"))
            button.nameText:SetTextColor(ItemColor(item)); button.stripe:SetVertexColor(ItemColor(item))
            button.quantity:SetText(Quantity(row))
            button.chance:SetText(String(RL:FormatChance(row, tbl), "—"))
        else
            button.icon:SetTexture(nil); button.nameText:SetText(""); button.quantity:SetText(""); button.chance:SetText("")
        end
    end
    self.lootEmpty:SetShown(#rows == 0)
    self.lootEmpty:SetText(not mob and "Select a creature on the left to browse its prefilled loot table."
        or not tbl and "No loot table is available for this creature with the current source filter."
        or self.itemQuery ~= "" and "No items match this search."
        or "This source has no individual item entries yet.")
    local countLabel = #rows == total and string.format("%d items", total) or string.format("%d of %d items", #rows, total)
    self.lootPageText:SetText(string.format("%d / %d · %s", self.lootPage, self.lootPages, countLabel))
    Enable(self.lootPrevious, self.lootPage > 1); Enable(self.lootNext, self.lootPage < self.lootPages)
    self.footer:SetText(self.notice or (tbl and tbl.provenance == "classic_reference"
        and "Classic reference: these rates are not confirmed for Forever. Each dataset retains its own source and denominator."
        or "Each dataset retains its own source and denominator. — means no supported rate is available."))
    self:RefreshZones()
    self.refreshing = nil
end

function U:Toggle(force)
    if force == false and not self.frame then return end
    self:Build()
    local wasShown = self.frame:IsShown()
    local show = force == nil and not wasShown or force == true
    self.frame:SetShown(show)
    if show and wasShown then self:FitWindow(); self:Refresh() end
end
