local _, RP = ...
local T = RP.Theme
local S = {}
RP.QuestTrackerSettings = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
local POPUP_NAME = "RicoPlatesQuestTrackerAppearance"
local WIDTH = 214
local unpack = unpack or table.unpack

local function Text(parent, value, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(T.font, size, "")
    text:SetTextColor(unpack(color or T.colors.text))
    text:SetText(value)
    return text
end

local function Button(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    if label then
        button.label = Text(button, label, 11)
        button.label:SetPoint("CENTER")
    end
    T:Button(button)
    button:SetScript("OnClick", onClick)
    return button
end

local function AddGear(button)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("settings-icon") then
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAtlas("settings-icon")
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetVertexColor(0.72, 0.89, 0.82)
        return
    end

    -- The geometric fallback keeps the button recognizable with Classic atlases.
    local function Piece(layer, width, height, x, y, rotation, r, g, b)
        local piece = button:CreateTexture(nil, layer)
        piece:SetSize(width, height)
        piece:SetPoint("CENTER", x, y)
        piece:SetColorTexture(r, g, b, 1)
        piece:SetRotation(rotation)
    end
    for index = 0, 7 do
        local angle = index * math.pi / 4
        Piece("ARTWORK", 3.4, 2, math.cos(angle) * 4.7, math.sin(angle) * 4.7, angle, 0.64, 0.83, 0.74)
    end
    Piece("ARTWORK", 7.6, 7.6, 0, 0, 0, 0.64, 0.83, 0.74)
    Piece("ARTWORK", 7.6, 7.6, 0, 0, math.pi / 4, 0.64, 0.83, 0.74)
    Piece("OVERLAY", 3.5, 3.5, 0, 0, math.pi / 4, 0.07, 0.12, 0.10)
end

local function HideTooltip(button)
    if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function Tooltip(button, label, details)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:SetText(label)
    if details then GameTooltip:AddLine(details, 0.75, 0.83, 0.80, true) end
    GameTooltip:Show()
end

local function Slider(popup, y, key, label, minimum, tracker)
    local caption = Text(popup, label, 11)
    caption:SetPoint("TOPLEFT", 14, y)
    local percent = Text(popup, "", 11, T.colors.mint)
    percent:SetPoint("TOPRIGHT", -14, y)

    local slider = CreateFrame("Slider", nil, popup)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", 14, y - 17)
    slider:SetSize(WIDTH - 28, 15)
    slider:SetMinMaxValues(minimum, 100)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouse(true)
    slider:EnableMouseWheel(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(3)
    track:SetColorTexture(0.15, 0.28, 0.23, 1)
    slider:SetThumbTexture(WHITE)
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(7, 12)
    thumb:SetVertexColor(unpack(T.colors.mint))

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.max(minimum, math.min(100, math.floor(value + 0.5)))
        percent:SetFormattedText("%d%%", value)
        if not popup.refreshing and RP.db[key] ~= value then
            RP.db[key] = value
            tracker:ApplyAppearance()
        end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if self:IsEnabled() then
            self:SetValue(math.max(minimum, math.min(100, self:GetValue() + delta * 5)))
        end
    end)
    function slider:ReadSetting()
        local value = RP.db[key] or RP.defaults[key]
        self:SetValue(value)
        percent:SetFormattedText("%d%%", value)
    end
    function slider:EnableSetting(enabled)
        if enabled then self:Enable() else self:Disable() end
        caption:SetTextColor(unpack(enabled and T.colors.text or T.colors.muted))
        percent:SetTextColor(unpack(enabled and T.colors.mint or T.colors.muted))
        thumb:SetVertexColor(unpack(enabled and T.colors.mint or T.colors.muted))
    end
    return slider
end

local function BuildPopup(tracker, header, gear)
    local popup = CreateFrame("Frame", POPUP_NAME, header)
    popup:Hide()
    popup:SetSize(WIDTH, 198)
    popup:SetPoint("TOPRIGHT", header, "TOPLEFT", -9, 0)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    T:Panel(popup)

    local title = Text(popup, "Tracker appearance", 13)
    title:SetPoint("TOPLEFT", 14, -12)
    local close = Button(popup, "X", 20, 20, function() popup:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    local rule = popup:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", 12, -34)
    rule:SetPoint("TOPRIGHT", -12, -34)
    rule:SetHeight(1)
    rule:SetColorTexture(0.24, 0.61, 0.43, 0.58)

    local showGlow = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    showGlow:SetSize(20, 20)
    showGlow:SetPoint("TOPLEFT", 13, -43)
    T:Check(showGlow)
    local glowLabel = Text(popup, "Show glow", 11)
    glowLabel:SetPoint("LEFT", showGlow, "RIGHT", 7, 0)
    local glow = Slider(popup, -75, "questTrackerGlowStrength", "Glow strength", 0, tracker)
    local opacity = Slider(popup, -119, "questTrackerOpacity", "Panel opacity", 25, tracker)
    showGlow:SetScript("OnClick", function(self)
        RP.db.questTrackerGlow = self:GetChecked() and true or false
        glow:EnableSetting(RP.db.questTrackerGlow)
        tracker:ApplyAppearance()
    end)

    local hide = Button(popup, "Hide tracker", WIDTH - 26, 24, function(self)
        HideTooltip(self)
        popup:Hide()
        RP:SetOption("compactQuestTracker", false)
    end)
    hide:SetPoint("BOTTOM", 0, 10)
    hide:HookScript("OnEnter", function(self)
        Tooltip(self, "Hide tracker", "Turn it back on under Quests in /rp.")
    end)
    hide:HookScript("OnLeave", HideTooltip)
    hide:HookScript("OnHide", HideTooltip)

    popup:SetScript("OnShow", function(self)
        self.refreshing = true
        showGlow:SetChecked(RP.db.questTrackerGlow)
        glow:ReadSetting()
        opacity:ReadSetting()
        glow:EnableSetting(RP.db.questTrackerGlow)
        self.refreshing = nil
        gear.selected = true
        T:PaintButton(gear)
    end)
    popup:SetScript("OnHide", function()
        gear.selected = false
        T:PaintButton(gear)
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = POPUP_NAME end
    return popup
end

function S:Create(tracker, header)
    header = header or tracker.frame
    local gear, popup
    gear = Button(header, nil, 20, 20, function(self)
        HideTooltip(self)
        if not popup then popup = BuildPopup(tracker, header, self) end
        popup:SetShown(not popup:IsShown())
    end)
    AddGear(gear)
    gear:HookScript("OnEnter", function(self)
        if not popup or not popup:IsShown() then Tooltip(self, "Tracker settings") end
    end)
    gear:HookScript("OnLeave", HideTooltip)
    gear:HookScript("OnHide", HideTooltip)
    local function ClosePopup() if popup then popup:Hide() end end
    header:HookScript("OnHide", ClosePopup)
    if header ~= tracker.frame then tracker.frame:HookScript("OnHide", ClosePopup) end
    return gear
end
