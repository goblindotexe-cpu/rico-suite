local _, F = ...
local U = { page = 1, locationPage = 1, query = "", kind = "all", rows = {}, locationRows = {} }
F.UI = U
local T = F.Theme
local FONT = T.font
local unpack = unpack or table.unpack
local COLORS = T.colors

local function Text(parent, size, color)
    local surface = parent.ricoForeground or parent
    local text = surface:CreateFontString(nil, "OVERLAY")
    if parent.ricoForeground then
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
    end
    text:SetFont(FONT, size or 12, "")
    text:SetTextColor(unpack(color or COLORS.text))
    text:SetJustifyH("LEFT")
    return text
end

local function Button(parent, label, width, height, click)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 26)
    b:EnableMouse(true)
    b.background = T:Panel(b)
    b.label = Text(b, 11)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnClick", click)
    T:Button(b, b.background)
    return b
end

local function Input(parent, width, height)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, height or 25)
    box:SetAutoFocus(false)
    box:SetFont(FONT, 12, "")
    box:SetMaxLetters(100)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    T:Input(box)
    return box
end

local function Check(parent, label, key, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(23, 23)
    check:SetPoint("TOPLEFT", x, y)
    check.label = Text(parent, 11)
    check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.label:SetText(label)
    check:SetScript("OnClick", function(self) F:SetOption(key, self:GetChecked() and true or false) end)
    check.key = key
    T:Check(check)
    return check
end

local function Progress(parent, width, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, height)
    bar:SetMinMaxValues(0, 20)
    bar:SetValue(0)
    bar.label = Text(bar, 11)
    bar.label:SetPoint("CENTER")
    bar:EnableMouse(false)
    T:Progress(bar)
    return bar
end

local function UpdateProgress(bar, entry)
    local count = F:GetInventory(entry.id)
    bar:SetMinMaxValues(0, F.db.goal)
    bar:SetValue(count or 0)
    bar.label:SetText(count and string.format("In bags: %d / %d", count, F.db.goal) or "Bag count unavailable")
end

function U:CopySource(entry)
    if not entry then return end
    if not self.sourceBox then
        local panel = CreateFrame("Frame", nil, self.frame)
        panel:SetFrameLevel(self.frame:GetFrameLevel() + 30)
        panel:SetSize(650, 100)
        panel:SetPoint("CENTER")
        panel:EnableMouse(true)
        T:Window(panel, true)
        local text = Text(panel, 12)
        text:SetPoint("TOPLEFT", 18, -13)
        text:SetText("Source link — press Ctrl+C to copy")
        panel.edit = Input(panel, 610, 27)
        panel.edit:SetMaxLetters(1000)
        panel.edit:SetPoint("TOPLEFT", 20, -42)
        local close = Button(panel, "Close", 65, 22, function() panel:Hide() end)
        close:SetPoint("TOPRIGHT", -12, -9)
        panel:Hide()
        self.sourceBox = panel
    end
    self.sourceBox:Show()
    self.sourceBox.edit:SetText(entry.source or "See SOURCES_NL.txt")
    self.sourceBox.edit:SetFocus()
    self.sourceBox.edit:HighlightText()
end

function U:RefreshTools()
    if not self.tools or not self.tools:IsShown() then return end
    for _, check in ipairs(self.toolChecks) do check:SetChecked(F.db[check.key]) end
    if not self.keyButton then return end
    local label = F.OneKey:GetKeyLabel()
    if self.capturingKey then
        label = "Press a key…"
        if self.pendingKey then label = self.pendingKey.binding and "Release to bind…" or "Canceling…" end
    end
    self.keyButton.label:SetText(label)
    local hint = self.keyMessage
    if self.capturingKey then
        hint = "Hold modifiers first. Middle/extra mouse buttons and wheel work over this field. Esc cancels."
    end
    self.keyHint:SetText(hint or "This shortcut takes over while you hold a fishing pole outside combat.")
end

function U:StopKeyCapture(message)
    if self.capturingKey then
        self.capturingKey, self.pendingKey = nil, nil
        local capture = self.keyCapture
        capture:EnableKeyboard(false)
        capture:Hide()
    end
    self.keyMessage = message
    self:RefreshTools()
end

function U:StartKeyCapture()
    if self.capturingKey then self:StopKeyCapture(); return end
    if InCombatLockdown and InCombatLockdown() then
        self:StopKeyCapture("Change your fishing key after combat.")
        return
    end
    local capture = self.keyCapture
    if not capture then return end
    local read, focus = F.Call(GetCurrentKeyBoardFocus)
    if read and not F.IsSecret(focus) and focus and type(focus.ClearFocus) == "function" then focus:ClearFocus() end
    self.capturingKey, self.keyMessage = true, nil
    capture:Show()
    capture:EnableKeyboard(true)
    capture:SetPropagateKeyboardInput(false)
    self:RefreshTools()
end

function U:SaveFishingKey(key)
    self:StopKeyCapture()
    local ok, message = F:SetFishingKey(key)
    if not ok then self.keyMessage = message end
    self:RefreshTools()
end

function U:BuildFishingKeyControls(panel)
    local label = Text(panel, 12, COLORS.mint)
    label:SetPoint("TOPLEFT", 26, -216)
    label:SetText("Fishing key")
    self.keyButton = Button(panel, "", 170, 27, function() U:StartKeyCapture() end)
    self.keyButton:SetPoint("TOPLEFT", 24, -235)
    self.keyButton.label:SetWidth(162)
    self.keyButton.label:SetJustifyH("CENTER")
    self.keyButton.label:SetWordWrap(false)
    local clear = Button(panel, "Clear", 62, 27, function() U:SaveFishingKey("") end)
    clear:SetPoint("LEFT", self.keyButton, "RIGHT", 8, 0)
    local reset = Button(panel, "Reset to F", 84, 27, function() U:SaveFishingKey(F.defaults.fishingKey) end)
    reset:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    self.keyHint = Text(panel, 10, COLORS.muted)
    self.keyHint:SetPoint("TOPLEFT", 26, -276)
    self.keyHint:SetWidth(356)
    self.keyHint:SetWordWrap(true)

    local capture = CreateFrame("Frame", nil, panel)
    self.keyCapture = capture
    capture:SetAllPoints(self.keyButton)
    capture:SetFrameLevel(self.keyButton:GetFrameLevel() + 1)
    capture:EnableMouse(true)
    capture:EnableMouseWheel(true)
    capture:Hide()
    local function StartInput(_, input)
        if not U.capturingKey or not F.PublicString(input) then return end
        if input == "ESCAPE" then
            U.pendingKey = { input = input }
        elseif not U.pendingKey then
            local key = F.OneKey:CaptureKey(input)
            if key then U.pendingKey = { input = input, binding = key } end
        end
        U:RefreshTools()
    end
    local function FinishInput(_, input)
        local pending = U.pendingKey
        if not pending or not F.PublicString(input) or input ~= pending.input then return end
        -- Keep swallowing the event until release dispatch completes, so the
        -- new native Interact override cannot reel in during key capture.
        local function Finish()
            if not U.capturingKey or U.pendingKey ~= pending then return end
            if pending.binding then U:SaveFishingKey(pending.binding) else U:StopKeyCapture() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, Finish) else Finish() end
    end
    capture:SetScript("OnKeyDown", StartInput)
    capture:SetScript("OnKeyUp", FinishInput)
    capture:SetScript("OnMouseDown", function(frame, input)
        if F.PublicString(input) and (input == "MiddleButton" or input:match("^Button%d+$")) then
            StartInput(frame, input)
        end
    end)
    capture:SetScript("OnMouseUp", function(frame, input)
        if not F.PublicString(input) then return end
        if input == "LeftButton" then U:StopKeyCapture()
        else FinishInput(frame, input) end
    end)
    capture:SetScript("OnMouseWheel", function(frame, delta)
        if U.pendingKey or not F.Number(delta) or delta == 0 then return end
        local input = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
        StartInput(frame, input)
        FinishInput(frame, input)
    end)
    capture:RegisterEvent("PLAYER_REGEN_DISABLED")
    capture:SetScript("OnEvent", function()
        if U.capturingKey then U:StopKeyCapture("Change your fishing key after combat.") end
    end)
    panel:HookScript("OnHide", function() U:StopKeyCapture() end)
end

function U:RefreshFishingPrompt()
    if F.Warnings then F.Warnings:RefreshPrompt() end
end

function U:CreateFishingPrompt()
    if F.Warnings then F.Warnings:CreatePrompt() end
end

function U:ToggleTools()
    if not self.tools then
        local panel = CreateFrame("Frame", "RicoFishingTools", UIParent)
        self.tools = panel
        panel:SetSize(382, F.OneKey and 312 or 251)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:SetToplevel(true)
        panel:EnableMouse(true)
        panel:SetClampedToScreen(true)
        panel.ricoSkipSuiteButtons = true
        T:Window(panel)
        local title = Text(panel, 21)
        title:SetPoint("TOPLEFT", 22, -24)
        T:Title(title, "FISHING TOOLS")
        local close = Button(panel, "Close", 63, 24, function() panel:Hide() end)
        close:SetPoint("TOPRIGHT", -20, -29)
        self.toolChecks = {
            Check(panel, "Show the lure countdown", "lureTimer", 22, -88),
            Check(panel, "Warn when general bags are nearly full", "bagWarning", 22, -117),
            Check(panel, "Tell me when I loot a favorite catch", "favoriteAlerts", 22, -146),
            Check(panel, "Show fishing key prompt beside your character", "fishingPrompt", 22, -175),
        }
        if F.OneKey then self:BuildFishingKeyControls(panel) end
        panel:Hide()
        if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RicoFishingTools" end
    end
    self.tools:SetShown(not self.tools:IsShown())
    self:RefreshTools()
end

function U:Build()
    if self.frame then return end
    self.building = true
    local frame = CreateFrame("Frame", "RicoFishingWindow", UIParent)
    self.frame = frame
    frame:SetSize(880, 610)
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
    T:Title(title, "FISHING")
    local sub = Text(frame, 11, COLORS.amber)
    sub:SetPoint("TOPLEFT", 24, -57)
    sub:SetText(#F.Data.order .. " catalog items • " .. F.Data.counts.observedItems
        .. " direct Forever beta reports • partial loot coverage")
    local close = Button(frame, "Close", 72, 28, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -24, -29)
    if F.SessionLog then
        local log = Button(frame, "Catch log", 99, 28, function() F.SessionLog:Toggle() end)
        log:SetPoint("RIGHT", close, "LEFT", -8, 0)
    end
    if F.OneKey then
        self.oneKeyCheck = Check(frame, "One-key fishing while holding a pole", "oneKey", 428, -33)
        self.oneKeyStatus = Text(frame, 10, COLORS.mint)
        self.oneKeyStatus:SetPoint("TOPLEFT", 432, -58)
        self.oneKeyStatus:SetWidth(230)
        self.oneKeyStatus:SetWordWrap(false)
    end
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RicoFishingWindow" end

    local listPanel = CreateFrame("Frame", nil, frame)
    listPanel:SetPoint("TOPLEFT", 14, -80)
    listPanel:SetSize(310, 478)
    T:Panel(listPanel)
    local search = Input(frame, 282, 26)
    self.search = search
    search:SetPoint("TOPLEFT", 28, -88)
    search:SetText("")
    search:SetScript("OnTextChanged", function(self)
        if U.building then return end
        U.query, U.page = self:GetText(), 1
        U:Refresh()
    end)
    local searchHint = Text(frame, 10, COLORS.muted)
    searchHint:SetPoint("TOPLEFT", 25, -120)
    searchHint:SetText("Search by item name or item ID")
    local filterKinds = {"all", "fish", "other_loot", "trinket"}
    local filterLabels = {all = "All items", fish = "Fish", other_loot = "Bycatch", trinket = "Trinkets"}
    local filter = Button(frame, "All items", 88, 23, function()
        local current = 1
        for i, kind in ipairs(filterKinds) do if U.kind == kind then current = i end end
        U.kind = filterKinds[current % #filterKinds + 1]
        U.page = 1
        U.filter.label:SetText(filterLabels[U.kind])
        U:Refresh()
    end)
    filter:SetPoint("TOPLEFT", 224, -119)
    self.filter = filter
    for index = 1, 10 do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(288, 34)
        row:SetPoint("TOPLEFT", 23, -153 - (index - 1) * 35)
        row:EnableMouse(true)
        row.background = T:Panel(row)
        T:Row(row, false, false)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(25, 25)
        row.icon:SetPoint("LEFT", 5, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.name = Text(row, 11)
        row.name:SetPoint("TOPLEFT", 37, -4)
        row.name:SetWidth(242)
        row.name:SetWordWrap(false)
        if F.SessionLog then
            row.name:SetWidth(222)
            row.star = Text(row, 12, COLORS.amber)
            row.star:SetPoint("TOPRIGHT", -8, -3)
            row.star:SetText("★")
            row.star:Hide()
        end
        row.status = Text(row, 9, COLORS.muted)
        row.status:SetPoint("BOTTOMLEFT", 37, 3)
        row:SetScript("OnEnter", function(self)
            self.hovered = true
            T:Row(self, self.selected, true)
        end)
        row:SetScript("OnLeave", function(self)
            self.hovered = false
            T:Row(self, self.selected, false)
        end)
        row:SetScript("OnClick", function(self) if self.entry then U.locationPage = 1; F:Select(self.entry.id) end end)
        self.rows[index] = row
    end
    self.noResults = Text(frame, 12, COLORS.muted)
    self.noResults:SetPoint("TOPLEFT", 28, -170)
    self.noResults:SetWidth(270)
    self.noResults:SetWordWrap(true)
    local previous = Button(frame, "Previous", 65, 24, function() U.page = math.max(1, U.page - 1); U:Refresh() end)
    previous:SetPoint("TOPLEFT", 24, -514)
    local nextPage = Button(frame, "Next", 65, 24, function() U.page = U.page + 1; U:Refresh() end)
    nextPage:SetPoint("TOPLEFT", 245, -514)
    self.pageText = Text(frame, 11, COLORS.muted)
    self.pageText:SetPoint("TOP", frame, "TOPLEFT", 165, -520)
    self.hudCheck = Check(frame, "Show goal tracker", "hud", 22, -567)
    if F.Warnings then
        local tools = Button(frame, "Fishing tools", 102, 25, function() U:ToggleTools() end)
        tools:SetPoint("TOPLEFT", 207, -567)
    end

    self.itemIcon = frame:CreateTexture(nil, "ARTWORK")
    self.itemIcon:SetSize(42, 42)
    self.itemIcon:SetPoint("TOPLEFT", 350, -88)
    self.itemName = Text(frame, 18)
    self.itemName:SetPoint("TOPLEFT", 404, -87)
    self.itemName:SetWidth(F.SessionLog and 332 or 440)
    self.itemName:SetWordWrap(false)
    if F.SessionLog then
        self.favorite = Button(frame, "Favorite", 94, 24, function()
            F.SessionLog:ToggleFavorite(F.db.selected)
            U:Refresh()
        end)
        self.favorite:SetPoint("TOPRIGHT", -28, -87)
    end
    self.itemStatus = Text(frame, 11)
    self.itemStatus:SetPoint("TOPLEFT", 404, -114)
    self.itemStatus:SetWidth(440)
    self.itemNote = Text(frame, 11, COLORS.muted)
    self.itemNote:SetPoint("TOPLEFT", 351, -146)
    self.itemNote:SetWidth(490)
    self.itemNote:SetHeight(52)
    self.itemNote:SetWordWrap(true)
    local source = Button(frame, "Source", 52, 22, function() U:CopySource(F:GetEntry(F.db.selected)) end)
    source:SetPoint("TOPRIGHT", -28, -177)
    local goalLabel = Text(frame, 12)
    goalLabel:SetPoint("TOPLEFT", 352, -217)
    goalLabel:SetText("Bag goal")
    self.goal = Input(frame, 65, 25)
    self.goal:SetPoint("TOPLEFT", 455, -210)
    self.goal:SetMaxLetters(4)
    self.goal:SetNumeric(true)
    self.goal:SetScript("OnEnterPressed", function(self) F:SetGoal(tonumber(self:GetText())); self:ClearFocus() end)
    local setGoal = Button(frame, "Set goal", 74, 25, function() F:SetGoal(tonumber(U.goal:GetText())); U.goal:ClearFocus() end)
    setGoal:SetPoint("TOPLEFT", 532, -210)
    local reset = Button(frame, "New session", 122, 25, function() F:ResetSession() end)
    reset:SetPoint("TOPRIGHT", -28, -210)
    self.progress = Progress(frame, 490, 23)
    self.progress:SetPoint("TOPLEFT", 350, -249)
    self.sessionText = Text(frame, 11, COLORS.muted)
    self.sessionText:SetPoint("TOPLEFT", 352, -282)
    self.sessionText:SetWidth(487)
    self.sessionText:SetHeight(33)
    self.sessionText:SetWordWrap(true)
    local locations = Text(frame, 14)
    locations:SetPoint("TOPLEFT", 351, -330)
    locations:SetText("Fishing areas")
    local backLoc = Button(frame, "<", 25, 23, function() U.locationPage = math.max(1, U.locationPage - 1); U:Refresh() end)
    backLoc:SetPoint("TOPRIGHT", -63, -325)
    local nextLoc = Button(frame, ">", 25, 23, function() U.locationPage = U.locationPage + 1; U:Refresh() end)
    nextLoc:SetPoint("TOPRIGHT", -28, -325)
    if F.SpotStats then
        local compare = Button(frame, "Compare spots", 114, 23, function() F.SpotStats:Toggle() end)
        compare:SetPoint("RIGHT", backLoc, "LEFT", -9, 0)
    end
    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(490, 46)
        row:SetPoint("TOPLEFT", 350, -360 - (index - 1) * 50)
        T:Panel(row)
        row.name = Text(row, 11)
        row.name:SetPoint("TOPLEFT", 8, -6)
        row.name:SetWidth(348)
        row.name:SetWordWrap(false)
        row.status = Text(row, 10, COLORS.muted)
        row.status:SetPoint("BOTTOMLEFT", 8, 6)
        row.status:SetWidth(348)
        row.status:SetWordWrap(false)
        row.open = Button(row, "Map", 50, 26, function()
            if row.location then F.Map:OpenZone(row.location) end
        end)
        row.open:SetPoint("RIGHT", -65, 0)
        row.follow = Button(row, "Track", 50, 26, function()
            if row.location then F.Map:SetWaypoint(F:GetEntry(F.db.selected), row.location, row.x, row.y) end
        end)
        row.follow:SetPoint("RIGHT", -7, 0)
        self.locationRows[index] = row
    end
    self.locationStatus = Text(frame, 10, COLORS.muted)
    self.locationStatus:SetPoint("TOPLEFT", 353, -515)
    self.locationStatus:SetWidth(485)
    self.pinsCheck = Check(frame, "Show map and minimap markers for this catch", "pins", 350, -541)
    self.reportedCheck = Check(frame, "Include unconfirmed source locations", "reportedPins", 350, -575)
    frame:Hide()
    self.building = false
end

function U:RefreshLocations(entry)
    local locations = entry.locations or {}
    local pages = math.max(1, math.ceil(#locations / 3))
    self.locationPage = math.max(1, math.min(pages, self.locationPage))
    for index, row in ipairs(self.locationRows) do
        local location = locations[(self.locationPage - 1) * 3 + index]
        row.location = location
        row:SetShown(location ~= nil)
        if location then
            local x, y = location.x, location.y
            local first = location.points and location.points[1]
            if not F.Map:ValidPoint(x, y) and first then x, y = first.x or first[1], first.y or first[2] end
            row.x, row.y = x, y
            row.name:SetText(location.zone or tostring(location.mapID or "Unknown area"))
            local label = location.observed and "Catch report (beta)" or "Unconfirmed source location"
            if F.Map:ValidPoint(x, y) then label = label .. string.format(" • ~%.1f, %.1f", x * 100, y * 100)
            else label = label .. " • area only" end
            row.status:SetText(label)
            row.status:SetTextColor(unpack(location.observed and COLORS.green or COLORS.amber))
            local usable = F.Map:MapUsable(location)
            row.open:SetEnabled(usable)
            row.follow:SetEnabled(usable and F.Map:Allowed(location) and F.Map:ValidPoint(x, y))
        end
    end
    self.locationStatus:SetText(#locations > 0 and string.format("Areas %d/%d • markers show fishing areas, not guaranteed spawns", self.locationPage, pages)
        or "No reliable source area known yet; no location assumed.")
end

function U:Refresh()
    if not F.db or self.building then return end
    self:RefreshTools()
    self:RefreshFishingPrompt()
    local entry = F:GetEntry(F.db.selected)
    if not entry then return end
    if self.hud then
        self.hud:SetShown(F.db.hud)
        if F.db.hud then
            self.hud.name:SetText(entry.name)
            UpdateProgress(self.hud.progress, entry)
            local oneKey = F.OneKey
            local hint = "/rf opens the guide"
            if oneKey and oneKey.mode == "reel" then
                hint = oneKey:GetKeyLabel() .. " when the bobber splashes"
            elseif oneKey and oneKey.mode == "cast" then
                hint = oneKey:GetKeyLabel() .. " to cast"
            end
            self.hud.detail:SetText("This session: " .. (F.session.items[entry.id] or 0) .. " • " .. hint)
        end
    end
    if not self.frame or not self.frame:IsShown() then return end
    local catalog = F:GetCatalog(self.query, self.kind)
    local pages = math.max(1, math.ceil(#catalog / 10))
    self.page = math.max(1, math.min(pages, self.page))
    for index, row in ipairs(self.rows) do
        local item = catalog[(self.page - 1) * 10 + index]
        row.entry = item
        row:SetShown(item ~= nil)
        if item then
            row.icon:SetTexture(F:GetIcon(item.id))
            row.name:SetText(item.name)
            if row.star then row.star:SetShown(F.SessionLog:IsFavorite(item.id)) end
            row.status:SetText(item.observed and "Forever catch report" or "Reference; unconfirmed")
            row.status:SetTextColor(unpack(item.observed and COLORS.green or COLORS.amber))
            row.selected = item.id == F.db.selected
            T:Row(row, row.selected, row.hovered)
        end
    end
    self.noResults:SetShown(#catalog == 0)
    self.noResults:SetText(self.kind == "trinket" and "No trinket with a confirmed Forever fishing source found yet. This does not mean none exist."
        or "No matching items in this source catalog.")
    self.pageText:SetText(string.format("%d / %d • %d items", self.page, pages, #catalog))
    self.itemIcon:SetTexture(F:GetIcon(entry.id))
    self.itemName:SetText(entry.name)
    if self.favorite then
        self.favorite.selected = F.SessionLog:IsFavorite(entry.id)
        self.favorite.label:SetText(self.favorite.selected and "Favorited" or "Favorite")
        T:PaintButton(self.favorite)
    end
    self.itemStatus:SetText(entry.observed and "Direct Forever catch report • beta" or "Forever reference • not independently confirmed")
    self.itemStatus:SetTextColor(unpack(entry.observed and COLORS.green or COLORS.amber))
    self.itemNote:SetText(entry.observed and "This catch was reported in the Forever beta and has not been reconfirmed in the release version. Each location has its own source status."
        or "This fish appears in a Forever reference database. These locations have not all been retested in Forever, so their map markers are off by default.")
    self.goal:SetText(tostring(F.db.goal))
    UpdateProgress(self.progress, entry)
    local rate = F:GetSessionRate()
    self.sessionText:SetText(string.format("This catch: %d received • session: %d items from %d fishing loot windows%s",
        F.session.items[entry.id] or 0, F.session.quantity, F.session.loots, rate and string.format(" • %.0f items/hour", rate) or ""))
    self:RefreshLocations(entry)
    for _, check in ipairs({self.hudCheck, self.pinsCheck, self.reportedCheck}) do check:SetChecked(F.db[check.key]) end
    if self.oneKeyCheck then
        self.oneKeyCheck:SetChecked(F.db.oneKey)
        self.oneKeyStatus:SetText(F.OneKey:GetStatus())
    end
end

function U:Toggle(force)
    self:Build()
    self.frame:SetShown(force == nil and not self.frame:IsShown() or force == true)
    self:Refresh()
end

function U:Initialize()
    if self.hud then return end
    local hud = CreateFrame("Frame", "RicoFishingTracker", UIParent)
    self.hud = hud
    hud:SetSize(292, 76)
    hud:SetFrameStrata("MEDIUM")
    hud:SetPoint("CENTER", UIParent, "BOTTOM", F.db.hudX, F.db.hudY)
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function(self) self:StartMoving() end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if F.Number(x) and F.Number(y) then F.db.hudX, F.db.hudY = x - UIParent:GetWidth() / 2, y end
    end)
    T:Window(hud, true)
    hud.name = Text(hud, 11)
    hud.name:SetPoint("TOPLEFT", 10, -10)
    hud.name:SetWidth(210)
    hud.name:SetWordWrap(false)
    local open = Button(hud, "Guide", 55, 21, function() U:Toggle() end)
    open:SetPoint("TOPRIGHT", -7, -5)
    hud.progress = Progress(hud, 272, 21)
    hud.progress:SetPoint("TOPLEFT", 10, -31)
    hud.detail = Text(hud, 10, COLORS.muted)
    hud.detail:SetPoint("TOPLEFT", 10, -58)
    hud.detail:SetWidth(272)
    if F.OneKey then self:CreateFishingPrompt() end
    self:Refresh()
end
