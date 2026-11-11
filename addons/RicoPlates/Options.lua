local _, RP = ...
local T = RP.Theme
local O = { controls = {}, demos = {} }
RP.Options = O
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = T.font
local unpack = unpack or table.unpack
local COLORS = T.colors

local function Text(parent, text, size, color)
    local surface = parent.ricoForeground or parent
    local fs = surface:CreateFontString(nil, "OVERLAY")
    if parent.ricoForeground then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    end
    fs:SetFont(FONT, size or 12, "")
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(color or COLORS.text))
    fs:SetText(text)
    return fs
end

local function Button(parent, title, width, height, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.bg = T:Panel(button)
    button.label = Text(button, title, 11)
    button.label:SetPoint("CENTER")
    button:SetScript("OnClick", callback)
    T:Button(button, button.bg)
    return button
end

local function Checkbox(page, y, key, label)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 0, y)
    T:Check(cb)
    cb.label = Text(page, label, 12)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    cb.label:SetWidth(405)
    cb.key = key
    cb:SetScript("OnClick", function(self)
        RP:SetOption(key, self:GetChecked() and true or false)
        O:RefreshState()
    end)
    function cb:Refresh() self:SetChecked(RP.db[key]) end
    O.controls[#O.controls + 1] = cb
    return cb
end

local function Slider(page, y, key, label, low, high, step, format)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(420, 46)
    row:SetPoint("TOPLEFT", 4, y)
    local labelText = Text(row, label, 12)
    labelText:SetPoint("TOPLEFT")
    local valueText = Text(row, "", 12, COLORS.mint)
    valueText:SetPoint("TOPRIGHT")
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", 0, -23)
    slider:SetSize(420, 13)
    slider.track = slider:CreateTexture(nil, "BACKGROUND")
    slider.track:SetTexture(WHITE)
    slider.track:SetVertexColor(COLORS.muted[1] * 0.28, COLORS.muted[2] * 0.28, COLORS.muted[3] * 0.28, 1)
    slider.track:SetPoint("LEFT")
    slider.track:SetPoint("RIGHT")
    slider.track:SetHeight(3)
    slider:SetThumbTexture(WHITE)
    slider:GetThumbTexture():SetSize(9, 13)
    slider:GetThumbTexture():SetVertexColor(unpack(COLORS.mint))
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetScript("OnValueChanged", function(_, value)
        local rounded = low + math.floor((value - low) / step + 0.5) * step
        valueText:SetFormattedText(format or "%d", rounded)
        row.newValue = rounded
    end)
    -- Commit only on release. Dragging does not repeatedly rebuild all plates.
    slider:SetScript("OnMouseUp", function()
        if row.newValue then RP:SetOption(key, row.newValue); O:RefreshState() end
    end)
    function row:Refresh()
        slider:SetValue(RP.db[key])
        valueText:SetFormattedText(format or "%d", RP.db[key])
    end
    O.controls[#O.controls + 1] = row
    return row
end

local function Cycle(page, y, key, label)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(426, 32)
    row:SetPoint("TOPLEFT", 3, y)
    local fs = Text(row, label, 12)
    fs:SetPoint("LEFT")
    local modes = {"percent", "value", "none"}
    local labels = {percent = "Percentage (%)", value = "Current / maximum", none = "No text"}
    local button
    button = Button(row, "", 205, 28, function()
        local index = 1
        for i, mode in ipairs(modes) do if RP.db[key] == mode then index = i end end
        RP:SetOption(key, modes[index % #modes + 1])
        row:Refresh()
        O:RefreshState()
    end)
    button:SetPoint("RIGHT")
    function row:Refresh() button.label:SetText(labels[RP.db[key]]) end
    O.controls[#O.controls + 1] = row
end

function O:SelectPage(index)
    self.selectedPage = index
    for i, page in ipairs(self.pages) do
        page:SetShown(i == index)
        self.tabs[i].selected = i == index
        T:PaintButton(self.tabs[i])
    end
    self:RefreshPreview()
    self:RefreshState()
end

function O:RefreshState()
    if not self.frame then return end
    if self.partyStatus then
        local status = RP.PartyFrames and RP.PartyFrames:GetStatus()
        self.partyStatus:SetText(type(status) == "table" and status.message or "Party styling is ready when group frames are available.")
    end
    if self.minimapStatus and RP.Minimap then self.minimapStatus:SetText(RP.Minimap:GetStatus()) end
    if self.enemyRangeSpell then
        local spell = RP.EnemyRange and RP.EnemyRange.spellName
        self.enemyRangeSpell:SetText(spell and ("Enemy range reference • " .. spell) or "Enemy range reference is unavailable.")
    end
    if self.questSourceStatus then
        local status = RP.Quest and RP.Quest.GetStatus and RP.Quest:GetStatus()
        local message = "Questie not loaded; built-in quest detection is active."
        if not RP.db.useQuestie then message = "Questie integration is disabled; built-in detection is active."
        elseif status and status.questieReady then message = "Questie connected; quest markers use its objective data when needed."
        elseif type(Questie) == "table" then message = "Questie is loading; built-in quest detection remains active." end
        self.questSourceStatus:SetText(message)
    end
    if self.questRouteStatus then
        local status = RP.QuestRoutes and RP.QuestRoutes:GetStatus()
        self.questRouteStatus:SetText(status and status.message or "Walking-route provider is unavailable.")
    end
    if self.unitLockButton then self.unitLockButton:Refresh() end
    if RP.pendingSettings then
        self.state:SetText("Settings saved. Applied after combat.")
        self.state:SetTextColor(unpack(COLORS.amber))
    elseif not RP.db.enabled then
        self.state:SetText("RicoPlates is disabled. The default UI has been restored.")
        self.state:SetTextColor(unpack(COLORS.muted))
    else
        self.state:SetText("Active • Changes apply immediately outside combat.")
        self.state:SetTextColor(unpack(COLORS.mint))
    end
end

function O:RefreshControls()
    for _, control in ipairs(self.controls) do control:Refresh() end
    self:RefreshState()
    self:RefreshPreview()
end

function O:RefreshPreview()
    if not self.frame then return end
    local shown = self.frame:IsShown()
    local unitPage = self.selectedPage == 5
    local partyPage = self.selectedPage == 6 or self.selectedPage == 8
    local mapPage = self.selectedPage == 7
    if self.nameplatePreview then self.nameplatePreview:SetShown(not unitPage and not partyPage and not mapPage) end
    if self.unitPreviewPanel then self.unitPreviewPanel:SetShown(unitPage) end
    if self.partyPreviewPanel then self.partyPreviewPanel:SetShown(partyPage) end
    if self.minimapHelp then self.minimapHelp:SetShown(mapPage) end
    local unitFrames = RP.UnitFrames
    if shown and unitPage and not self.unitPreview and self.unitPreviewPanel
        and unitFrames and type(unitFrames.CreateOptionsPreview) == "function" then
        self.unitPreview = unitFrames:CreateOptionsPreview(self.unitPreviewPanel)
    end
    if self.unitPreview and unitFrames and type(unitFrames.SetPreviewShown) == "function" then
        local showUnits = shown and unitPage
        if self.unitPreviewShown ~= showUnits then
            unitFrames:SetPreviewShown(self.unitPreview, showUnits)
            self.unitPreviewShown = showUnits
        end
    end
    local party = RP.PartyFrames
    if shown and partyPage and not self.partyPreview and self.partyPreviewPanel
        and party and type(party.CreateOptionsPreview) == "function" then
        self.partyPreview = party:CreateOptionsPreview(self.partyPreviewPanel)
    end
    if self.partyPreview and party and type(party.SetPreviewShown) == "function" then
        party:SetPreviewShown(self.partyPreview, shown and partyPage)
    end
    if shown and partyPage and self.partyPreview and party and type(party.RefreshOptionsPreview) == "function" then
        party:RefreshOptionsPreview(self.partyPreview)
    end
    if not shown or unitPage or partyPage or mapPage then
        for _, p in ipairs(self.demos) do RP.Plates:StopBubbles(p) end
        if shown and unitPage and self.unitPreview and unitFrames and type(unitFrames.RefreshOptionsPreview) == "function" then
            unitFrames:RefreshOptionsPreview(self.unitPreview)
        end
        self:RefreshState()
        return
    end
    local spacing = RP.db.showBuffs and RP.db.showDebuffs and 82 or 76
    for i, p in ipairs(self.demos) do
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", 84, -92 - (i - 1) * spacing)
        RP.Plates:UpdateDemo(p, self.samples[i])
    end
    self:RefreshState()
end

function O:Build()
    if self.frame then return end
    local frame = CreateFrame("Frame", "RicoPlatesOptions", UIParent)
    self.frame = frame
    frame:SetSize(940, 650)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetScale(math.min(1, UIParent:GetWidth() / 990, UIParent:GetHeight() / 700))
    frame:Hide()
    T:Window(frame)
    local title = Text(frame, "", 23)
    title:SetPoint("TOPLEFT", 24, -22)
    T:Title(title, "PLATES")
    local subtitle = Text(frame, "Forever  •  v" .. RP.version .. "  •  /rp", 11, COLORS.muted)
    subtitle:SetPoint("TOPLEFT", 24, -57)
    local close = Button(frame, "Close", 72, 28, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -24, -29)
    self.pages, self.tabs = {}, {}
    local names = {"Nameplates", "Style", "Auras", "Quests", "Unitframes", "Party", "Minimap", "Healing"}
    local widths, tabX = {72, 37, 41, 45, 65, 43, 53, 50}, 24
    for i, name in ipairs(names) do
        local index = i
        local tab = Button(frame, name, widths[i], 32, function() O:SelectPage(index) end)
        tab:SetPoint("TOPLEFT", tabX, -85)
        tabX = tabX + widths[i] + 4
        self.tabs[i] = tab
        local page = CreateFrame("Frame", nil, frame)
        page:SetSize(438, 440)
        page:SetPoint("TOPLEFT", 24, -135)
        self.pages[i] = page
    end
    local general = self.pages[1]
    local rows = {
        {"enabled", "Enable RicoPlates"},
        {"showFriendlyNPCs", "Show friendly NPCs"},
        {"showParty", "Always show party members — blue HP bar"},
        {"showRaid", "Always show raid members — orange HP bar"},
        {"showPower", "Show mana, energy, rage, and other main resources"},
        {"showPowerNPC", "Show NPC resources only when available"},
        {"showClass", "Show class icons on players"},
        {"showFaction", "Show faction symbols on hostile players"},
        {"showLevel", "Show level"},
        {"showCast", "Show cast and channel bars"},
        {"targetBorder", "Highlight the iron border on the selected target"},
        {"grayTapped", "Use gray/white for mobs tapped by someone else"},
        {"grayTrivial", "Also gray out trivial mobs"},
        {"interruptIndicators", "Highlight casts I can interrupt"},
        {"aggroIndicator", "Glow when a creature is attacking me"},
    }
    for i, row in ipairs(rows) do Checkbox(general, -(i - 1) * 25, row[1], row[2]) end
    local note = Text(general, "Player names stay visible. Friendly players outside your group get a full bar when targeted. Party and raid have separate toggles.", 11, COLORS.muted)
    note:SetPoint("TOPLEFT", 5, -390)
    note:SetWidth(420)
    note:SetWordWrap(true)

    local effects = self.pages[2]
    Cycle(effects, 0, "healthText", "HP text")
    Cycle(effects, -38, "powerText", "Resource text")
    Slider(effects, -80, "width", "Width", 140, 280, 10)
    Slider(effects, -123, "height", "HP bar height", 14, 28, 1)
    Slider(effects, -166, "scale", "Overall scale", 0.75, 1.50, 0.05, "%.2fx")
    Slider(effects, -209, "fontSize", "Font size", 9, 15, 1)
    Slider(effects, -252, "verticalOffset", "Vertical offset", -30, 50, 1)
    Checkbox(effects, -299, "bubbles", "Animate liquid and bubbles in the HP bar")
    Slider(effects, -335, "bubbleCount", "Bubbles per bar", 1, 5, 1)
    Slider(effects, -382, "bubbleScale", "Bubble size", 1, 2.6, 0.1, "%.1fx")
    Slider(effects, -425, "maxAnimatedPlates", "Maximum animated world nameplates", 0, 40, 1)

    local auras = self.pages[3]
    local debuffTitle = Text(auras, "DEBUFFS — ABOVE", 11, COLORS.mint)
    debuffTitle:SetPoint("TOPLEFT", 5, 0)
    Checkbox(auras, -24, "showDebuffs", "Show debuffs above the name")
    Checkbox(auras, -53, "debuffsMineOnly", "Only debuffs cast by me and my pet")
    Slider(auras, -85, "debuffSize", "Debuff icon size", 14, 24, 1)
    Slider(auras, -132, "maxDebuffs", "Maximum debuffs in the upper row", 1, 10, 1)
    local buffTitle = Text(auras, "BUFFS — BELOW", 11, COLORS.mint)
    buffTitle:SetPoint("TOPLEFT", 5, -200)
    Checkbox(auras, -224, "showBuffs", "Show buffs below the bars")
    Checkbox(auras, -253, "buffsMineOnly", "Only buffs cast by me and my pet")
    Checkbox(auras, -280, "targetBuffsAll", "Always show all buffs on my selected target")
    Slider(auras, -310, "buffSize", "Buff icon size", 14, 24, 1)
    Slider(auras, -357, "maxBuffs", "Maximum buffs in the lower row", 1, 10, 1)
    local auraNote = Text(auras,
        "Both rows fit the bar width. Buffs move below any visible resource or cast bar.",
        11, COLORS.muted)
    auraNote:SetPoint("TOPLEFT", 5, -405)
    auraNote:SetWidth(420)
    auraNote:SetWordWrap(true)

    local quests = self.pages[4]
    Checkbox(quests, 0, "questMarkers", "Show our quest icon to the left of the level")
    Checkbox(quests, -27, "questText", "Also show KILL/LOOT text and progress")
    Checkbox(quests, -54, "useQuestie", "Use Questie automatically when it is available")
    self.questSourceStatus = Text(quests, "", 10, COLORS.muted)
    self.questSourceStatus:SetPoint("TOPLEFT", 5, -84); self.questSourceStatus:SetWidth(420); self.questSourceStatus:SetHeight(28)
    self.questSourceStatus:SetJustifyV("TOP")
    Checkbox(quests, -118, "worldHighlight", "Enable built-in outlines for interactive objects")
    Checkbox(quests, -148, "worldArrow", "Show a green arrow near a quest object")
    Slider(quests, -185, "worldArrowSize", "Quest object arrow size", 28, 72, 2)
    Checkbox(quests, -244, "questRoutes", "Enable routes over known walkable paths")
    local chooseRoute = Button(quests, "Choose quest route", 204, 28, function() if RP.QuestRouteUI then RP.QuestRouteUI:Show() end end)
    chooseRoute:SetPoint("TOPLEFT", 5, -280)
    local stopRoute = Button(quests, "Stop my route", 204, 28, function()
        if RP.QuestRoutes then RP.QuestRoutes:Stop() end; O:RefreshState()
    end)
    stopRoute:SetPoint("LEFT", chooseRoute, "RIGHT", 10, 0)
    self.questRouteStatus = Text(quests, "", 11, COLORS.mint)
    self.questRouteStatus:SetPoint("TOPLEFT", 5, -320); self.questRouteStatus:SetWidth(420); self.questRouteStatus:SetHeight(42)
    self.questRouteStatus:SetJustifyV("TOP")
    local limitations = Text(quests,
        "Routes are shown on the map and minimap with directional guidance. Unknown route coverage is reported. The object arrow marks the interaction target selected by the client.",
        11, COLORS.muted)
    limitations:SetPoint("TOPLEFT", 5, -372)
    limitations:SetWidth(420)
    limitations:SetWordWrap(true)
    Checkbox(quests, -415, "compactQuestTracker", "Show the compact quest tracker")

    local unitOptions = self.pages[5]
    local unitRows = {
        {"unitFramesEnabled", "Enable fixed unitframes"},
        {"showPlayerFrame", "Show my player frame"},
        {"showTargetFrame", "Show a frame for my current target"},
        {"showTargetOfTarget", "Show my target's target"},
        {"showPetFrame", "Show my pet frame when I have a pet"},
        {"unitPortrait3D", "Show animated 3D portraits"},
        {"showClassResources", "Show combo points and other class resources"},
    }
    for i, row in ipairs(unitRows) do Checkbox(unitOptions, -(i - 1) * 23, row[1], row[2]) end
    Slider(unitOptions, -175, "unitFrameWidth", "HP bar width", 180, 320, 10)
    Slider(unitOptions, -218, "unitFrameHeight", "HP bar height", 18, 34, 2)
    Slider(unitOptions, -261, "unitFrameScale", "Unitframe scale", 0.75, 1.40, 0.05, "%.2fx")
    Slider(unitOptions, -304, "unitPortraitZoom", "Portrait zoom — higher is closer", 0.50, 1, 0.05, "%.2f")
    local unlock
    unlock = Button(unitOptions, "Move frames", 205, 28, function()
        local module = RP.UnitFrames
        if module and type(module.IsUnlocked) == "function" and type(module.SetUnlocked) == "function" then
            module:SetUnlocked(not module:IsUnlocked())
        end
        O:RefreshState()
    end)
    unlock:SetPoint("TOPLEFT", 5, -355)
    function unlock:Refresh()
        local module = RP.UnitFrames
        local available = module and type(module.IsUnlocked) == "function" and type(module.SetUnlocked) == "function"
        local unlocked = available and module:IsUnlocked()
        self:SetEnabled(available and true or false)
        self.label:SetText(unlocked and "Lock frames" or "Move frames")
    end
    self.unitLockButton = unlock
    self.controls[#self.controls + 1] = unlock
    local resetPositions = Button(unitOptions, "Reset positions", 205, 28, function()
        local module = RP.UnitFrames
        if module and type(module.ResetPositions) == "function" then module:ResetPositions() end
        O:RefreshPreview()
        O:RefreshState()
    end)
    resetPositions:SetPoint("LEFT", unlock, "RIGHT", 10, 0)
    function resetPositions:Refresh()
        self:SetEnabled(RP.UnitFrames and type(RP.UnitFrames.ResetPositions) == "function" and true or false)
    end
    self.controls[#self.controls + 1] = resetPositions
    local unitNote = Text(unitOptions,
        "Move frames opens a grid. Grid snap and frame snapping are available in the move toolbar. Drag a green outline, then click Lock frames. Available outside combat.",
        11, COLORS.muted)
    unitNote:SetPoint("TOPLEFT", 5, -396)
    unitNote:SetWidth(420)
    unitNote:SetWordWrap(true)

    local partyOptions = self.pages[6]
    Checkbox(partyOptions, 0, "partyFrames", "Use Rico styling on party frames")
    Slider(partyOptions, -40, "partyFrameWidth", "Standard party health bar width", 140, 260, 10)
    Slider(partyOptions, -85, "partyFrameHeight", "Standard party health bar height", 16, 26, 1)
    Slider(partyOptions, -130, "partyFrameScale", "Standard party frame scale", 0.6, 1.2, 0.05, "%.2fx")
    Checkbox(partyOptions, -184, "partyLowHealth", "Warn when a party member has low health")
    Slider(partyOptions, -216, "partyLowHealthThreshold", "Low-health warning threshold", 10, 50, 5, "%d%%")
    Checkbox(partyOptions, -270, "partyDispels", "Mark debuffs I can remove with learned spells")
    self.partyStatus = Text(partyOptions, "", 11, COLORS.mint)
    self.partyStatus:SetPoint("TOPLEFT", 5, -308); self.partyStatus:SetWidth(420); self.partyStatus:SetHeight(60)
    self.partyStatus:SetJustifyV("TOP")
    local partyNote = Text(partyOptions,
        "Move the group in Blizzard Edit Mode. Size controls affect standard frames; compact frames keep native sizing. Dispel icons show effects your learned spells can remove; hover for the effect. Appearance changes apply after combat.",
        10, COLORS.muted)
    partyNote:SetPoint("TOPLEFT", 5, -385); partyNote:SetWidth(420); partyNote:SetWordWrap(true)

    local minimap = self.pages[7]
    Checkbox(minimap, 0, "squareMinimap", "Use the square Rico minimap")
    Checkbox(minimap, -33, "minimapClock", "Show the clock inside the minimap")
    Checkbox(minimap, -66, "minimapOverview", "Enable one extra zoom-out step outdoors")
    self.minimapStatus = Text(minimap, "", 11, COLORS.mint)
    self.minimapStatus:SetPoint("TOPLEFT", 5, -105)
    self.minimapStatus:SetWidth(420); self.minimapStatus:SetWordWrap(true)

    local healing = self.pages[8]
    Checkbox(healing, 0, "healerRange", "Dim party bars outside group range")
    Checkbox(healing, -33, "enemyRange", "Dim enemy bars outside attack range")
    Checkbox(healing, -66, "healerHots", "Show timers for my heals over time")
    Checkbox(healing, -99, "healerAbsorbs", "Show healing absorbs on health bars")
    Checkbox(healing, -132, "healerOverheal", "Mark overheal on my healing preview")
    local healHint = Text(healing, "Mint shows the healing your cast is expected to restore. Purple shows healing absorbed by an effect. Gold marks a cast that exceeds the target's missing health.", 11, COLORS.muted)
    healHint:SetPoint("TOPLEFT", 5, -177); healHint:SetWidth(420); healHint:SetWordWrap(true)
    local rangeHint = Text(healing, "Party dimming uses Blizzard's group range. Enemy dimming checks a learned attack from your spellbook.", 11, COLORS.muted)
    rangeHint:SetPoint("TOPLEFT", 5, -235); rangeHint:SetWidth(420); rangeHint:SetWordWrap(true)
    self.enemyRangeSpell = Text(healing, "", 11, COLORS.mint)
    self.enemyRangeSpell:SetPoint("TOPLEFT", 5, -278); self.enemyRangeSpell:SetWidth(420)

    local preview = CreateFrame("Frame", nil, frame)
    self.nameplatePreview = preview
    preview:SetPoint("TOPLEFT", 485, -85)
    preview:SetSize(430, 492)
    T:Panel(preview)
    local previewTitle = Text(preview, "LIVE PREVIEW", 11, COLORS.mint)
    previewTitle:SetPoint("TOPLEFT", 20, -16)
    local previewHint = Text(preview, "Sample values • scaled to fit", 10, COLORS.muted)
    previewHint:SetPoint("TOPLEFT", 20, -35)
    local ownFaction = UnitFactionGroup("player")
    local opposite = ownFaction == "Alliance" and "Horde" or "Alliance"
    self.samples = {
        { name = "Hostile player", kind = "enemy", hp = 1540, max = 2100, level = 27,
            class = "ROGUE", faction = opposite, power = 70, powerMax = 100, powerColor = {1, 0.85, 0.15},
            debuffs = {
                {icon = "Interface\\Icons\\Ability_Rogue_Garrote", duration = 18, remaining = 11},
                {icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", duration = 18, remaining = 8},
            },
            buffs = {
                {icon = "Interface\\Icons\\Spell_Holy_WordFortitude", duration = 1800, remaining = 900},
                {icon = "Interface\\Icons\\Spell_Holy_Renew", duration = 15, remaining = 9},
            } },
        { name = "Hostile quest mob", kind = "enemy", hp = 740, max = 1200, level = 26, quest = {kind = "kill", progress = "3/8"},
            debuffs = {
                {icon = "Interface\\Icons\\Ability_Rogue_Garrote", duration = 18, remaining = 12},
                {icon = "Interface\\Icons\\Ability_Poisons", applications = 3, duration = 12, remaining = 9},
                {icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", duration = 18, remaining = 6},
            } },
        { name = "Mob tapped by another player", kind = "tapped", baseKind = "neutral", hp = 620, max = 950, level = 25,
            quest = {kind = "loot", progress = "2/5"} },
        { name = "Party member", kind = "party", hp = 1680, max = 2200, level = 26,
            class = "MAGE", power = 1240, powerMax = 1800, powerColor = {0.19, 0.48, 1},
            buffs = {
                {icon = "Interface\\Icons\\Spell_Holy_WordFortitude", duration = 1800, remaining = 600},
                {icon = "Interface\\Icons\\Spell_Holy_Renew", duration = 15, remaining = 11},
            } },
        { name = "Raid member", kind = "raid", hp = 2460, max = 3000, level = 28,
            class = "WARRIOR", power = 45, powerMax = 100, powerColor = {0.95, 0.20, 0.17} },
    }
    for i, sample in ipairs(self.samples) do
        local p = RP.Plates:Build(preview, true)
        p:SetPoint("TOPLEFT", 84, -92 - (i - 1) * 76)
        self.demos[i] = p
    end
    local legend = Text(preview, "Debuffs above • buffs below • tapped mobs gray/white", 10, COLORS.muted)
    legend:SetPoint("BOTTOMLEFT", 20, 14)
    local unitPreview = CreateFrame("Frame", nil, frame)
    self.unitPreviewPanel = unitPreview
    unitPreview:SetPoint("TOPLEFT", 485, -85)
    unitPreview:SetSize(430, 492)
    T:Panel(unitPreview)
    local unitTitle = Text(unitPreview, "UNITFRAMES", 11, COLORS.mint)
    unitTitle:SetPoint("TOPLEFT", 20, -16)
    local unitHint = Text(unitPreview, "Player • current target • pet", 10, COLORS.muted)
    unitHint:SetPoint("TOPLEFT", 20, -35)
    local unitLegend = Text(unitPreview,
        "Target shows any selected unit, including friends, NPCs, and pets.", 10, COLORS.muted)
    unitLegend:SetPoint("BOTTOMLEFT", 20, 14)
    unitLegend:SetWidth(390)
    unitLegend:SetWordWrap(true)
    local partyPreview = CreateFrame("Frame", nil, frame)
    self.partyPreviewPanel = partyPreview
    partyPreview:SetPoint("TOPLEFT", 485, -85); partyPreview:SetSize(430, 492)
    T:Panel(partyPreview)
    local partyTitle = Text(partyPreview, "PARTY PREVIEW", 11, COLORS.mint)
    partyTitle:SetPoint("TOPLEFT", 20, -16)
    local partyHint = Text(partyPreview, "The same liquid bars, portraits and typography", 10, COLORS.muted)
    partyHint:SetPoint("TOPLEFT", 20, -35)
    local mapHelp = CreateFrame("Frame", nil, frame)
    self.minimapHelp = mapHelp
    mapHelp:SetPoint("TOPLEFT", 485, -85); mapHelp:SetSize(430, 492)
    T:Panel(mapHelp)
    local mapTitle = Text(mapHelp, "MINIMAP CONTROLS", 11, COLORS.mint)
    mapTitle:SetPoint("TOPLEFT", 20, -16)
    local tips = {
        {"Live minimap", "Scroll or use the + and − buttons. Your usual tracking, mining and quest-route pins are shown here."},
        {"Area overview", "At the widest live zoom, scroll down once more outdoors to see more of the zone. Zoom in once to return to live tracking."},
        {"Clock", "Local and realm time use 24-hour format. Hover to see both, or click to open Blizzard’s clock settings."},
    }
    for i, tip in ipairs(tips) do
        local y = -57 - (i - 1) * 80
        local title = Text(mapHelp, tip[1], 12)
        title:SetPoint("TOPLEFT", 20, y)
        local detail = Text(mapHelp, tip[2], 11, COLORS.muted)
        detail:SetPoint("TOPLEFT", 20, y - 22)
        detail:SetWidth(380); detail:SetWordWrap(true)
    end
    self.state = Text(frame, "", 11)
    self.state:SetPoint("BOTTOMLEFT", 25, 49)
    local reset = Button(frame, "Defaults", 145, 28, function() RP:Reset() end)
    reset:SetPoint("BOTTOMLEFT", 24, 14)
    local restore = Button(frame, "Disable & restore", 190, 28, function() RP:Restore() end)
    restore:SetPoint("LEFT", reset, "RIGHT", 10, 0)
    local diagnostics = Button(frame, "Chat diagnostics", 145, 28, function() RP:Status() end)
    diagnostics:SetPoint("BOTTOMRIGHT", -25, 14)
    frame:SetScript("OnShow", function() O:RefreshControls() end)
    frame:SetScript("OnHide", function() O:RefreshPreview() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "RicoPlatesOptions") end
    self:SelectPage(1)
end

function O:Toggle(forceShow)
    self:Build()
    if forceShow or not self.frame:IsShown() then self.frame:Show(); self:RefreshControls()
    else self.frame:Hide() end
end

function O:Initialize()
    -- Deliberately lazy: the options UI and previews allocate only when opened.
end
