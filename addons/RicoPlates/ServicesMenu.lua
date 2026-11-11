local _, RP = ...
local Menu = { rows = {} }
RP.ServicesMenu = Menu

local Theme = RP.Theme
local unpack = unpack or table.unpack
local MENU_WIDTH, ROW_HEIGHT = 224, 26
local EXTRA_ENTRIES = { off = "Off", all = "All services" }
local STATUS_TEXT = {
    loading = "Loading Forever service locations…",
    missing = "Install or enable QuestieDB for service locations.",
    unavailable = "QuestieDB service data is unavailable.",
}
local events = CreateFrame("Frame")

local function Call(fn, ...)
    if type(fn) == "function" then return pcall(fn, ...) end
    return false
end

local function Locked()
    local ok, value = Call(InCombatLockdown)
    return ok and value == true
end

local function MouseOver(frame)
    local ok, value = Call(frame and frame.IsMouseOver, frame)
    return ok and not (issecretvalue and issecretvalue(value)) and value == true
end

local function Label(frame, value, size, color)
    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetFont(Theme.font, size, "")
    label:SetTextColor(unpack(color or Theme.colors.text))
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(value)
    return label
end

local function Entries()
    local entries = {}
    for id, category in pairs(RP.Services.categories) do
        entries[#entries + 1] = { id = id, label = category.label, icon = category.icon }
    end
    table.sort(entries, function(a, b)
        if a.label == b.label then return a.id < b.id end
        return a.label < b.label
    end)
    table.insert(entries, 1, { id = "all", label = EXTRA_ENTRIES.all })
    table.insert(entries, 1, { id = "off", label = EXTRA_ENTRIES.off })
    return entries
end

function Menu:Refresh()
    local services = RP.Services
    local filter = services:GetFilter()
    local category = services.categories[filter]
    local name = category and category.label or EXTRA_ENTRIES[filter]
    if self.mapButton then
        name = name or ("%d selected"):format(services:GetSelectedCount())
        self.mapButton.label:SetText("Services: " .. name)
        self.mapButton.selected = filter ~= "off"
        Theme:PaintButton(self.mapButton)
    end
    for _, row in ipairs(self.rows) do
        row.selected = services:IsFilterSelected(row.entry.id)
        row.check:SetShown(row.selected)
        Theme:PaintButton(row)
    end
    if self.status then
        local state = services:GetStatus()
        local message = STATUS_TEXT[state]
        if self.statusMessage ~= message then
            self.statusMessage = message
            self.status:SetText(message or "")
            self.status:SetShown(message ~= nil)
            self.frame:SetHeight(self.menuHeight + (message and 34 or 0))
        end
    end
end

function Menu:Build()
    if self.frame then return self.frame end
    local entries = Entries()
    local frame = CreateFrame("Frame", "RicoMapServicesDropdown", UIParent)
    frame:Hide()
    self.menuHeight = 38 + #entries * ROW_HEIGHT
    frame:SetSize(MENU_WIDTH, self.menuHeight)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetScript("OnShow", function() Call(events.RegisterEvent, events, "GLOBAL_MOUSE_DOWN") end)
    frame:SetScript("OnHide", function() Call(events.UnregisterEvent, events, "GLOBAL_MOUSE_DOWN") end)
    Theme:Panel(frame)
    self.frame = frame

    local title = Label(frame, "MAP SERVICES", 13, Theme.colors.mint)
    title:SetPoint("TOPLEFT", 12, -10)
    self.status = Label(frame, "", 10, Theme.colors.muted)
    self.status:SetPoint("BOTTOMLEFT", 12, 9)
    self.status:SetWidth(MENU_WIDTH - 24)
    self.status:SetWordWrap(true)
    self.status:Hide()
    for index, entry in ipairs(entries) do
        local row = CreateFrame("Button", nil, frame)
        row.entry = entry
        row:SetSize(MENU_WIDTH - 16, ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 8, -32 - (index - 1) * ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")
        row.label = Label(row, entry.label, 11)
        row.label:SetPoint("LEFT", 29, 0)
        row.label:SetWidth(MENU_WIDTH - 71)
        if entry.icon then
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetTexture(entry.icon)
            icon:SetSize(16, 16)
            icon:SetPoint("LEFT", 7, 0)
        end
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(15, 15)
        box:SetPoint("RIGHT", -8, 0)
        box:EnableMouse(false)
        Theme:Panel(box)
        row.check = box:CreateTexture(nil, "OVERLAY")
        row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.check:SetSize(16, 16)
        row.check:SetPoint("CENTER")
        Theme:Button(row)
        row:SetScript("OnClick", function(button)
            if not Locked() then RP.Services:SetFilter(button.entry.id) end
            Menu:Refresh()
        end)
        self.rows[index] = row
    end

    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end
    return frame
end

function Menu:Toggle(anchor)
    if Locked() or not RP.Services then return false end
    if anchor == true then
        anchor = Minimap
    elseif not anchor then
        anchor = self.mapButton and self.mapButton:IsVisible() and self.mapButton or Minimap
    end
    local frame = self:Build()
    if frame:IsShown() and self.anchor == anchor then
        frame:Hide()
        return true
    end
    self.anchor = anchor
    frame:ClearAllPoints()
    if anchor then
        frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
    else
        frame:SetPoint("CENTER")
    end
    self:Refresh()
    frame:Show()
    return true
end

function Menu:AttachWorldMap()
    local map = WorldMapFrame
    if self.mapButton or not map or not RP.Services or Locked() then return end
    local button = CreateFrame("Button", nil, map)
    self.mapButton = button
    local canvas = map.ScrollContainer or map
    button:SetSize(196, 25)
    -- The map title, navigation and close buttons occupy the strip above the canvas.
    button:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -16, -40)
    button:RegisterForClicks("LeftButtonUp")
    button.label = Label(button, "", 11)
    button.label:SetPoint("LEFT", 10, 0)
    button.label:SetWidth(155)
    local arrow = button:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetSize(15, 15)
    arrow:SetPoint("RIGHT", -9, 0)
    Theme:Button(button)
    button:SetScript("OnClick", function(frame) Menu:Toggle(frame) end)
    local function RefreshButton()
        -- Forever can change the world map's strata when the native map opens.
        local _, strata = Call(map.GetFrameStrata, map)
        if not strata or strata == "BACKGROUND" or strata == "LOW" or strata == "MEDIUM" then strata = "HIGH" end
        button:SetFrameStrata(strata)
        button:SetFrameLevel(canvas:GetFrameLevel() + 20)
        Menu:Refresh()
    end
    map:HookScript("OnShow", RefreshButton)
    map:HookScript("OnHide", function()
        if Menu.frame and Menu.anchor == button then Menu.frame:Hide() end
    end)
    RefreshButton()
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "GLOBAL_MOUSE_DOWN" then
        local frame = Menu.frame
        if not frame or not frame:IsShown() or MouseOver(frame) or MouseOver(Menu.anchor) then return end
        for _, row in ipairs(Menu.rows) do if MouseOver(row) then return end end
        frame:Hide()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if Menu.frame then Menu.frame:Hide() end
    else
        Menu:AttachWorldMap()
    end
end)
