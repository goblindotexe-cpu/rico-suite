-- Shared Rico appearance. This identical file ships with each addon so every
-- addon works independently. All liquid geometry is generated live in Lua.
local _, Addon = ...
local T = {}
Addon.Theme = T
T.font = "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local unpack = unpack or table.unpack
local sin, cos, pi = math.sin, math.cos, math.pi
T.colors = {
    text = {0.90, 0.94, 0.93}, muted = {0.55, 0.64, 0.62},
    mint = {0.40, 0.94, 0.67}, green = {0.40, 0.94, 0.67},
    amber = {1.00, 0.73, 0.34}, blue = {0.47, 0.73, 0.94},
    surface = {0.035, 0.052, 0.049}, raised = {0.055, 0.081, 0.073},
    border = {0.15, 0.22, 0.19}, accent = {0.22, 0.83, 0.49},
}
T.windows, T.panels, T.titles, T.buttons, T.rows, T.checks, T.progresses = {}, {}, {}, {}, {}, {}, {}
T.headers = {}
T.headerTint = {0.28, 0.95, 0.39}

function T:Fill(parent, r, g, b, a)
    local tex = parent:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(WHITE)
    tex:SetVertexColor(r or 0.035, g or 0.052, b or 0.049, a or 1)
    tex:SetAllPoints()
    return tex
end

local function Edge(parent, point, opposite, horizontal, color, inset)
    local tex = parent:CreateTexture(nil, "BORDER")
    tex:SetTexture(WHITE)
    local pad = inset or 0
    tex:SetPoint(point, parent, point, point:find("LEFT") and pad or -pad,
        point:find("TOP") and -pad or pad)
    tex:SetPoint(opposite, parent, opposite, opposite:find("LEFT") and pad or -pad,
        opposite:find("TOP") and -pad or pad)
    if horizontal then tex:SetHeight(1) else tex:SetWidth(1) end
    tex:SetVertexColor(unpack(color))
    return tex
end

function T:Border(parent)
    if parent.ricoBorder then return parent.ricoBorder end
    local c = self.colors.border
    local edges = {
        Edge(parent, "TOPLEFT", "TOPRIGHT", true, {0.24, 0.32, 0.28, 1}),
        Edge(parent, "BOTTOMLEFT", "BOTTOMRIGHT", true, {0.08, 0.12, 0.10, 1}),
        Edge(parent, "TOPLEFT", "BOTTOMLEFT", false, c),
        Edge(parent, "TOPRIGHT", "BOTTOMRIGHT", false, c),
    }
    parent.ricoBorder = edges
    return edges
end

function T:Panel(parent)
    if parent.ricoBackground then return parent.ricoBackground end
    parent.ricoBackground = self:Fill(parent, unpack(self.colors.surface))
    self.panels[parent] = true
    self:Border(parent)
    return parent.ricoBackground
end

-- Native Line regions, no picture, sprite sheet, video, or external assets.
-- A glow and a fine highlight trace each deforming strand of liquid.
local function Line(parent, thickness, r, g, b, alpha)
    local line = parent:CreateLine(nil, "ARTWORK")
    line:SetColorTexture(r, g, b, alpha)
    line:SetThickness(thickness)
    line:SetBlendMode("ADD")
    return line
end

local function Points(line, parent, x1, y1, x2, y2)
    line:SetStartPoint("BOTTOMLEFT", parent, x1, y1)
    line:SetEndPoint("BOTTOMLEFT", parent, x2, y2)
end

function T:Liquid(parent, settings)
    local config = settings or {}
    local liquid = CreateFrame("Frame", nil, parent)
    liquid:SetAllPoints()
    liquid:EnableMouse(false)
    liquid:SetClipsChildren(true)
    liquid.clock, liquid.accumulator = 0, 0
    liquid.width, liquid.height = config.width or parent:GetWidth(), config.height or parent:GetHeight()
    liquid.tint = config.color or {0.28, 0.95, 0.39}
    liquid.fps = config.health and 20 or config.compact and 24 or 30
    liquid.segments = (config.health or config.compact) and 24 or 80
    liquid.strands = config.health and 3 or config.compact and 2 or 5
    liquid.bubbleCount = config.bubbleCount or (config.health and 3 or 14)
    liquid.bubbleScale = config.bubbleScale or (config.health and 1 or 2.2)
    liquid.ribbons, liquid.bubbles, liquid.wash = {}, {}, {}
    for i = 1, ((config.health or config.compact) and 12 or 32) do
        local wash = liquid:CreateTexture(nil, "BACKGROUND")
        wash:SetTexture(WHITE)
        liquid.wash[i] = wash
    end
    for strand = 1, liquid.strands do
        local ribbon = {}
        for j = 1, liquid.segments do
            ribbon[j] = {glow = Line(liquid, config.compact and 2.5 or config.health and 5.0 or 9.0, 1, 1, 1, 0.10),
                core = Line(liquid, config.health and 0.85 or 1.1, 1, 1, 1, 0.42)}
        end
        liquid.ribbons[strand] = ribbon
    end
    for i = 1, (config.compact and liquid.bubbleCount or config.health and 5 or 14) do
        local bubble = {lines = {}, visible = true}
        for j = 1, (config.health and 12 or 20) do bubble.lines[j] = Line(liquid, 0.8, 0.5, 1, 0.6, 0.4) end
        liquid.bubbles[i] = bubble
    end

    function liquid:Paint()
        local width, height, time = self.width, self.height, self.clock
        if width <= 0 or height <= 0 then return end
        local r, g, b = unpack(self.tint)
        if self.lastWidth ~= width or self.lastHeight ~= height or self.lastTint ~= self.tint then
            self.lastWidth, self.lastHeight, self.lastTint = width, height, self.tint
            for i, wash in ipairs(self.wash) do
                local y = (i - 1) / #self.wash
                local light = 0.08 + 0.25 * sin(y * pi) ^ 2 + 0.08 * (1 - y)
                wash:ClearAllPoints()
                wash:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, y * height)
                wash:SetSize(width, height / #self.wash + 0.35)
                wash:SetVertexColor(r * light, g * light, b * light, config.health and 0.42 or 1)
            end
        end
        local function Wave(x, strand)
            -- Different wavelengths and currents keep the liquid asymmetric:
            -- broad folds, small eddies and slow highlights rather than a wire grid.
            local phase = strand * 2.399
            local u = x / (config.health and 68 or 145)
            return height * (0.50
                + (0.22 + strand * 0.012) * sin(u * (1.1 + strand * 0.13) + phase - time * (0.19 + strand * 0.017))
                + 0.095 * sin(u * (2.8 + strand * 0.11) - phase * 0.7 + time * 0.23)
                + 0.035 * cos(u * 5.2 + phase + time * 0.31))
        end
        for strand, ribbon in ipairs(self.ribbons) do
            local x1, y1 = 0, Wave(0, strand)
            for j, part in ipairs(ribbon) do
                local x2 = width * j / self.segments
                local y2 = Wave(x2, strand)
                local shine = 0.14 + 0.28 * sin(x2 * 0.021 + time * 0.38 + strand * 1.7) ^ 4
                part.glow:SetColorTexture(r, g, b, config.health and 0.12 or 0.10)
                part.core:SetColorTexture(0.32 + r * 0.68, 0.26 + g * 0.74, 0.20 + b * 0.80, shine)
                Points(part.glow, self, x1, y1, x2, y2)
                Points(part.core, self, x1, y1, x2, y2)
                x1, y1 = x2, y2
            end
        end
        for i, bubble in ipairs(self.bubbles) do
            local enabled = i <= self.bubbleCount
            if enabled ~= bubble.visible then
                for _, line in ipairs(bubble.lines) do line:SetShown(enabled) end
                bubble.visible = enabled
            end
            if enabled then
                local life = (time * (0.045 + i * 0.002) + i * 0.173) % 1
                local radius = (1.4 + (i * 7 % 5) * 0.52) * self.bubbleScale
                local x = width * ((i * 0.271) % 0.96) + sin(time * 0.24 + i) * (config.health and 4 or 14)
                local y = -radius + life * (height + radius * 2)
                local opacity = math.min(1, life * 6, (1 - life) * 6) * 0.56
                for j, line in ipairs(bubble.lines) do
                    local a1, a2 = (j - 1) * pi * 2 / #bubble.lines, j * pi * 2 / #bubble.lines
                    local highlight = a1 >= pi / 6 and a1 <= pi * 5 / 6 and 1 or 0.30
                    line:SetColorTexture(0.30 + r * 0.7, 0.30 + g * 0.7, 0.25 + b * 0.75, opacity * highlight)
                    Points(line, self, x + cos(a1) * radius, y + sin(a1) * radius,
                        x + cos(a2) * radius, y + sin(a2) * radius)
                end
            end
        end
    end
    local function Tick(self, elapsed)
        self.accumulator = self.accumulator + elapsed
        if self.accumulator < 1 / self.fps then return end
        self.clock = (self.clock + self.accumulator) % 3600
        self.accumulator = 0
        self:Paint()
    end
    function liquid:Start()
        self:Show()
        self:Paint()
        self:SetScript("OnUpdate", Tick)
    end
    function liquid:Stop()
        self:SetScript("OnUpdate", nil)
    end
    liquid:SetScript("OnShow", function(self) if not config.manual then self:Start() end end)
    liquid:SetScript("OnHide", function(self) self:Stop() end)
    if not config.manual then liquid:Start() end
    return liquid
end

function T:Header(parent, title, options)
    local settings = options or {}
    local height = settings.height or 26
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(height)
    header:EnableMouse(false)
    header:SetClipsChildren(true)
    header.ricoLiquid = self:Liquid(header, {
        width = settings.width or parent:GetWidth(), height = height,
        color = self.headerTint, compact = height < 40,
        bubbleCount = height <= 4 and 0 or height < 40 and 3 or 14,
    })
    header:SetScript("OnSizeChanged", function(_, width, newHeight)
        if width > 0 then header.ricoLiquid.width = width end
        if newHeight > 0 then header.ricoLiquid.height = newHeight end
    end)
    if title then
        local foreground = CreateFrame("Frame", nil, header)
        foreground:SetAllPoints()
        foreground:SetFrameLevel(header:GetFrameLevel() + 2)
        foreground:EnableMouse(false)
        local caption = foreground:CreateFontString(nil, "OVERLAY")
        header.ricoCaption, header.ricoCaptionSize = caption, settings.fontSize or 13
        caption:SetFont(self.font, header.ricoCaptionSize, "OUTLINE")
        caption:SetTextColor(unpack(self.colors.text))
        caption:SetShadowColor(0, 0, 0, 0.9)
        caption:SetShadowOffset(1, -1)
        caption:SetPoint("CENTER")
        caption:SetText(title)
    end
    self.headers[header] = true
    return header
end

function T:Window(frame, compact)
    if frame.ricoWindow then return end
    frame.ricoWindow = true
    local bg = self:Panel(frame)
    bg:SetVertexColor(0.018, 0.028, 0.025, 0.99)
    for i = 1, 4 do
        local shadow = self:Fill(frame, 0, 0, 0, 0.10)
        shadow:ClearAllPoints()
        shadow:SetDrawLayer("BACKGROUND", -8 + i)
        shadow:SetPoint("TOPLEFT", -i * 2, i * 2)
        shadow:SetPoint("BOTTOMRIGHT", i * 2, -i * 2)
    end
    local header = self:Header(frame, nil, {height = compact and 3 or 76, width = frame:GetWidth() - 2})
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    frame.ricoHeader, frame.ricoLiquid = header, header.ricoLiquid
    if not compact then
        local separator = self:Fill(frame, 0.11, 0.19, 0.15, 1)
        separator:ClearAllPoints()
        separator:SetPoint("TOPLEFT", 20, -76)
        separator:SetPoint("TOPRIGHT", -20, -76)
        separator:SetHeight(1)
    end
    -- Root labels must render above child panel backgrounds and the liquid.
    -- Otherwise WoW can hide headings behind opaque sibling frames.
    frame.ricoForeground = CreateFrame("Frame", nil, frame)
    frame.ricoForeground:SetAllPoints(frame)
    frame.ricoForeground:SetFrameLevel(frame:GetFrameLevel() + 4)
    frame.ricoForeground:EnableMouse(false)
    self.windows[frame] = true
    if _G.RicoSuite and _G.RicoSuite.AttachWindow then _G.RicoSuite:AttachWindow(Addon, frame, compact) end
end

function T:Title(text, suffix)
    self.titles[text] = suffix
    text:SetFont(self.font, 26, "OUTLINE")
    text:SetTextColor(unpack(self.colors.text))
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -2)
    local c = self.colors.mint
    text:SetText(string.format("RICO |cff%02x%02x%02x%s|r", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), suffix))
end

function T:PaintButton(button)
    local bg = button.ricoButtonBackground
    if not bg then return end
    local enabled = button:IsEnabled()
    local a = self.colors.accent
    local factor = button.selected and 0.25 or button.ricoHover and 0.18 or 0.065
    local c = not enabled and {0.030, 0.042, 0.037}
        or {0.025 + a[1] * factor, 0.025 + a[2] * factor, 0.025 + a[3] * factor}
    bg:SetVertexColor(c[1], c[2], c[3], 1)
    if button.label then
        button.label:SetTextColor(unpack(enabled and (button.ricoLabelColor or self.colors.text) or self.colors.muted))
    end
    local border = button.ricoBorder
    if border then
        local active = enabled and (button.ricoHover or button.selected)
        for _, edge in ipairs(border) do
            edge:SetVertexColor(0.07 + a[1] * (active and 0.55 or 0.17), 0.07 + a[2] * (active and 0.55 or 0.17), 0.07 + a[3] * (active and 0.55 or 0.17), 1)
        end
    end
end

function T:Button(button, background)
    self.buttons[button] = true
    local parent = button:GetParent()
    if parent and parent.ricoForeground then button:SetFrameLevel(parent:GetFrameLevel() + 5) end
    button.ricoButtonBackground = background or button.background or button.bg or self:Panel(button)
    self:Border(button)
    if not button.ricoButton then
        button.ricoButton = true
        button:SetScript("OnEnter", function(b) b.ricoHover = true; T:PaintButton(b) end)
        button:SetScript("OnLeave", function(b) b.ricoHover = nil; T:PaintButton(b) end)
        button:HookScript("OnEnable", function(b) T:PaintButton(b) end)
        button:HookScript("OnDisable", function(b) T:PaintButton(b) end)
    end
    self:PaintButton(button)
end

function T:Input(box)
    box.ricoInput = true
    for _, key in ipairs({"Left", "Middle", "Right", "LeftTexture", "MiddleTexture", "RightTexture"}) do
        if box[key] and box[key].Hide then box[key]:Hide() end
    end
    box:SetFont(self.font, 12, "")
    box:SetTextColor(unpack(self.colors.text))
    box:SetTextInsets(8, 8, 0, 0)
    local bg = self:Panel(box)
    bg:SetVertexColor(0.012, 0.022, 0.018, 1)
    box:HookScript("OnEditFocusGained", function(self)
        for _, edge in ipairs(self.ricoBorder) do edge:SetVertexColor(0.23, 0.58, 0.36, 1) end
    end)
    box:HookScript("OnEditFocusLost", function(self)
        for _, edge in ipairs(self.ricoBorder) do edge:SetVertexColor(unpack(T.colors.border)) end
    end)
end

function T:Check(check)
    self.checks[check] = true
    check:SetNormalTexture(WHITE)
    check:GetNormalTexture():SetVertexColor(0.055, 0.10, 0.072, 1)
    check:SetPushedTexture(WHITE)
    check:GetPushedTexture():SetVertexColor(0.12, 0.30, 0.18, 1)
    check:SetHighlightTexture(WHITE)
    check:GetHighlightTexture():SetVertexColor(0.25, 0.75, 0.43, 0.14)
    check:SetCheckedTexture(WHITE)
    local checked = check:GetCheckedTexture()
    checked:ClearAllPoints()
    checked:SetPoint("TOPLEFT", 6, -6)
    checked:SetPoint("BOTTOMRIGHT", -6, 6)
    checked:SetVertexColor(0.36, 0.92, 0.55, 1)
    self:Border(check)
end

function T:Row(row, selected, hover)
    self.rows[row] = {selected = selected, hover = hover}
    row.background = row.background or self:Panel(row)
    if not row.ricoSelection then
        row.ricoSelection = row:CreateTexture(nil, "BORDER")
        row.ricoSelection:SetTexture(WHITE)
        row.ricoSelection:SetPoint("TOPLEFT", 0, -3)
        row.ricoSelection:SetPoint("BOTTOMLEFT", 0, 3)
        row.ricoSelection:SetWidth(2)
        row.ricoSelection:SetVertexColor(unpack(self.colors.mint))
    end
    local a = self.colors.accent
    local factor = selected and 0.17 or hover and 0.10 or 0.025
    local c = {0.026 + a[1] * factor, 0.026 + a[2] * factor, 0.026 + a[3] * factor}
    row.background:SetVertexColor(c[1], c[2], c[3], 1)
    row.ricoSelection:SetShown(selected and true or false)
end

function T:Progress(bar)
    self.progresses[bar] = true
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0.12, 0.58, 0.31, 1)
    self:Panel(bar):SetVertexColor(0.014, 0.033, 0.021, 1)
    local sheen = bar:CreateTexture(nil, "OVERLAY")
    sheen:SetTexture(WHITE)
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(1)
    sheen:SetVertexColor(0.5, 1, 0.66, 0.24)
end

-- Refresh already-created controls as well as future windows. The profile
-- manager only walks addon-owned menu trees; native combat aura widgets are
-- never inspected here.
function T:RefreshWindow(frame)
    local function Walk(widget, depth)
        if not widget or depth > 10 then return end
        if widget.IsForbidden and widget:IsForbidden() then return end
        if widget.GetObjectType and widget:GetObjectType() == "EditBox" and widget.GetFont then
            local _, size, flags = widget:GetFont()
            if type(size) == "number" then widget:SetFont(self.font, size, flags or "") end
        end
        if widget.GetRegions then
            for _, region in ipairs({widget:GetRegions()}) do
                if region.GetObjectType and region:GetObjectType() == "FontString" then
                    local _, size, flags = region:GetFont()
                    if type(size) == "number" then region:SetFont(self.font, size, flags or "") end
                end
            end
        end
        if widget.GetChildren then for _, child in ipairs({widget:GetChildren()}) do Walk(child, depth + 1) end end
    end
    Walk(frame, 0)
    for text, suffix in pairs(self.titles) do self:Title(text, suffix) end
end

function T:ApplyAppearance(appearance)
    if type(appearance) ~= "table" or type(appearance.accent) ~= "table" then return end
    local accent = appearance.accent
    self.font = appearance.font == "Arial" and "Fonts\\ARIALN.TTF" or "Fonts\\FRIZQT__.TTF"
    local function Color(key, r, g, b)
        local color = self.colors[key]
        color[1], color[2], color[3] = r, g, b
    end
    Color("accent", accent[1], accent[2], accent[3])
    Color("mint", 0.18 + accent[1] * 0.82, 0.18 + accent[2] * 0.82, 0.18 + accent[3] * 0.82)
    Color("green", unpack(self.colors.mint))
    Color("border", 0.035 + accent[1] * 0.21, 0.035 + accent[2] * 0.21, 0.035 + accent[3] * 0.21)
    Color("surface", 0.022 + accent[1] * 0.035, 0.022 + accent[2] * 0.035, 0.022 + accent[3] * 0.035)
    Color("raised", 0.028 + accent[1] * 0.060, 0.028 + accent[2] * 0.060, 0.028 + accent[3] * 0.060)
    for parent in pairs(self.panels) do
        if parent.ricoWindow then parent.ricoBackground:SetVertexColor(0.012 + accent[1] * 0.018, 0.012 + accent[2] * 0.018, 0.012 + accent[3] * 0.018, 0.99)
        elseif parent.ricoInput then parent.ricoBackground:SetVertexColor(0.009, 0.015, 0.012, 1)
        else parent.ricoBackground:SetVertexColor(unpack(self.colors.surface)) end
        for _, edge in ipairs(parent.ricoBorder or {}) do edge:SetVertexColor(unpack(self.colors.border)) end
    end
    for button in pairs(self.buttons) do self:PaintButton(button) end
    for row, state in pairs(self.rows) do self:Row(row, state.selected, state.hover) end
    for check in pairs(self.checks) do
        if check:GetCheckedTexture() then check:GetCheckedTexture():SetVertexColor(unpack(self.colors.mint)) end
        if check:GetHighlightTexture() then check:GetHighlightTexture():SetVertexColor(accent[1], accent[2], accent[3], 0.14) end
    end
    for bar in pairs(self.progresses) do bar:SetStatusBarColor(accent[1] * 0.72, accent[2] * 0.72, accent[3] * 0.72, 1) end
    self.headerTint = {accent[1], accent[2], accent[3]}
    for header in pairs(self.headers) do
        header.ricoLiquid.tint = self.headerTint
        if header.ricoLiquid:IsVisible() then header.ricoLiquid:Paint() end
        if header.ricoCaption then header.ricoCaption:SetFont(self.font, header.ricoCaptionSize, "OUTLINE") end
    end
    for frame in pairs(self.windows) do self:RefreshWindow(frame) end
end
