-- Class power owned by the player, displayed beside the selected unit's HUD.
-- Camelot combo points belong to the target: UnitPower(ComboPoints) is not a
-- substitute for GetComboPoints("player", "target") on this client.
local _, RP = ...
local C = { entries = {}, updates = 0 }
RP.ClassResources = C

local MAX_SEGMENTS, GAP = 12, 3
local WHITE = "Interface\\Buttons\\WHITE8X8"
local RESOURCES = {
    ROGUE = { enum = "ComboPoints", token = "COMBO_POINTS", kind = "combo", color = {1, 0.78, 0.18} },
    DRUID = { enum = "ComboPoints", token = "COMBO_POINTS", kind = "combo", energy = true, color = {1, 0.65, 0.16} },
    PALADIN = { enum = "HolyPower", token = "HOLY_POWER", color = {1, 0.84, 0.34} },
    WARLOCK = { enum = "SoulShards", token = "SOUL_SHARDS", shards = true, color = {0.72, 0.43, 1} },
    MONK = { enum = "Chi", token = "CHI", spec = "SPEC_MONK_WINDWALKER", color = {0.32, 1, 0.72} },
    MAGE = { enum = "ArcaneCharges", token = "ARCANE_CHARGES", spec = "SPEC_MAGE_ARCANE", color = {0.43, 0.68, 1} },
    EVOKER = { enum = "Essence", token = "ESSENCE", color = {0.35, 0.91, 0.80} },
    DEATHKNIGHT = { enum = "Runes", token = "RUNES", kind = "runes", color = {0.48, 0.85, 0.96} },
}

local function Number(value)
    return not RP.IsSecret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function Value(value)
    return RP.IsSecret(value) or Number(value)
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function PowerType(key)
    local value = Enum and Enum.PowerType and Enum.PowerType[key]
    if Number(value) and value >= 0 then return value end
end

local function Exists(unit)
    local ok, result = Call(UnitExists, unit)
    return ok and RP.PublicTrue(result)
end

local function Enabled()
    return RP.db and RP.db.enabled ~= false and RP.db.unitFramesEnabled ~= false
        and RP.db.showClassResources ~= false
end

local function SpecializationIs(globalName)
    local expected = _G[globalName]
    if not Number(expected) then return false end
    local getter = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
    local ok, current = Call(getter)
    return ok and Number(current) and current == expected
end

local function Capacity(powerType, targetBound)
    if not Number(powerType) or powerType < 0 then return end
    -- Camelot stores combo points on the target. Its own combo bars obtain the
    -- player's maximum without requiring a normal player-owned power pool.
    if not targetBound then
        local ok, present = Call(UnitHasPowerType, "player", powerType)
        if ok and RP.Readable(present) and present == false then return end
    end
    local gotMax, maximum = Call(UnitPowerMax, "player", powerType)
    -- An enum or a declared power type alone does not establish capacity.
    -- Player maxima are normally public. Unknown maxima stay native instead of
    -- fabricating five dots or retaining an obsolete maximum after a form swap.
    if gotMax and Number(maximum) and maximum > 0 then return maximum end
end

function C:Describe()
    if not Enabled() or not Exists("player") then return end
    local ok, _, class = Call(UnitClass, "player")
    if not ok or RP.IsSecret(class) or type(class) ~= "string" then return end
    local gotPrimary, primary = Call(UnitPowerType, "player")
    if not gotPrimary or not Number(primary) then primary = nil end
    local spec = RESOURCES[class]
    if spec and (not spec.spec or SpecializationIs(spec.spec)) then
        local formOK = not spec.energy or (primary ~= nil and primary == PowerType("Energy"))
        local powerType = PowerType(spec.enum)
        local maximum = formOK and powerType and Capacity(powerType, spec.kind == "combo")
        if maximum and primary ~= powerType then
            local kind = spec.kind or "points"
            if kind ~= "runes" or (type(GetRuneCooldown) == "function"
                and maximum == math.floor(maximum) and maximum <= MAX_SEGMENTS) then
                local step = 1
                if spec.shards and SpecializationIs("SPEC_WARLOCK_DESTRUCTION") then
                    local gotMod, modifier = Call(UnitPowerDisplayMod, powerType)
                    if gotMod and Number(modifier) and modifier > 0 then step = modifier end
                end
                return { token = spec.token, powerType = powerType, maximum = maximum,
                    kind = kind, targetBound = kind == "combo", step = step, color = spec.color }
            end
        end
    end

    -- Use Blizzard's explicit secondary-power pairing, where available, rather
    -- than treating every non-primary entry in Enum.PowerType as a real pool.
    local gotSecondary, secondary, token = Call(GetUnitSecondaryPowerInfo, "player")
    if gotSecondary and Number(secondary) and primary ~= nil and secondary ~= primary
        and RP.Readable(token) and type(token) == "string" then
        local maximum = Capacity(secondary)
        if maximum then
            local color = PowerBarColor and PowerBarColor[token]
            local rgb = color and {color.r, color.g, color.b} or {0.24, 0.53, 1}
            return { token = token, powerType = secondary, maximum = maximum,
                kind = "bar", targetBound = false, step = 1, color = rgb }
        end
    end
end

function C:ReadPower(descriptor)
    if descriptor.kind == "runes" then
        local states = {}
        for i = 1, descriptor.maximum do
            -- Event rune indices may be secret. Only our public slot indices
            -- reach the API; the native bool sink decides each fill's opacity.
            local ok, _, _, ready = Call(GetRuneCooldown, i)
            if not ok or (not RP.IsSecret(ready) and type(ready) ~= "boolean") then return end
            states[i] = ready
        end
        return { runes = states }
    end
    local ok, current
    if descriptor.targetBound then ok, current = Call(GetComboPoints, "player", "target")
    else ok, current = Call(UnitPower, "player", descriptor.powerType) end
    if not ok or not Value(current) then return end
    local fill = current
    if descriptor.step ~= 1 then
        local gotRaw, raw = Call(UnitPower, "player", descriptor.powerType, true)
        if not gotRaw or not Value(raw) then return end
        fill = raw
    end
    return { current = current, fill = fill }
end

function C:Hide(entry)
    local row = entry and entry.classResources
    if not row then return end
    row.active, row.resource, row.count = false, nil, 0
    row.targetBound, row.mode = false, nil
    row.text:SetText("")
    row:Hide()
end

local function Texture(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetTexture(WHITE)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return texture
end

local function Socket(segment)
    local socket = segment.socket
    socket.parts = {}
    for i = 1, 9 do socket.parts[i] = Texture(socket, "BACKGROUND", {1, 1, 1}) end
    -- These facets live in a child clipped to the native fill texture. Partial
    -- shards and restricted combo values are shaped by the engine, never Lua.
    segment.fillClip = CreateFrame("Frame", nil, segment)
    segment.fillClip:SetPoint("TOPLEFT", segment.fill, "TOPLEFT")
    segment.fillClip:SetPoint("BOTTOMRIGHT", segment.fill, "BOTTOMRIGHT")
    segment.fillClip:SetClipsChildren(true)
    segment.fillClip:EnableMouse(false)
    local face = CreateFrame("Frame", nil, segment.fillClip)
    face:SetAllPoints(segment)
    face:EnableMouse(false)
    segment.facets = {}
    local function Facet(alpha)
        local texture = Texture(face, "OVERLAY", {1, 1, 1, 1})
        texture:SetAlpha(alpha)
        segment.facets[#segment.facets + 1] = {texture = texture, alpha = alpha}
        return texture
    end
    local top = Facet(0.52)
    top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0); top:SetHeight(1)
    local left = Facet(0.21)
    left:SetPoint("TOPLEFT", 0, -1); left:SetPoint("BOTTOMLEFT", 0, 1); left:SetWidth(1)
    local glint = Facet(0.32)
    glint:SetPoint("TOPLEFT", 1, -1); glint:SetSize(2, 2)
    local facet = Facet(0.10)
    facet:SetPoint("CENTER", -1, 1); facet:SetSize(3, 6); facet:SetRotation(math.pi / 4)
    local shade = Texture(face, "OVERLAY", {0.005, 0.008, 0.012, 1})
    shade:SetAlpha(0.36)
    shade:SetPoint("BOTTOMLEFT", 0, 0); shade:SetPoint("BOTTOMRIGHT", 0, 0); shade:SetHeight(1)
    segment.facets[#segment.facets + 1] = {texture = shade, alpha = 0.36}
end

local function LayoutSocket(segment, width, height)
    local parts = segment.socket.parts
    local function Piece(index, x, y, w, h, color)
        local texture = parts[index]
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", segment.socket, "TOPLEFT", x, -y)
        texture:SetSize(math.max(1, w), math.max(1, h))
        texture:SetVertexColor(color[1], color[2], color[3], 1)
    end
    -- Cut corners create individual metal-set jewels instead of a solid row
    -- of square boxes. The empty face stays recessed and distinctly unlit.
    Piece(1, 1, 0, width - 2, height, {0.012, 0.014, 0.016})
    Piece(2, 0, 2, width, height - 4, {0.012, 0.014, 0.016})
    Piece(3, 2, 1, width - 4, height - 2, {0.24, 0.21, 0.15})
    Piece(4, 1, 3, width - 2, height - 6, {0.24, 0.21, 0.15})
    Piece(5, 3, 1, width - 6, 1, {0.69, 0.57, 0.32})
    Piece(6, 1, 3, 1, height - 6, {0.48, 0.39, 0.22})
    Piece(7, width - 2, 3, 1, height - 6, {0.10, 0.10, 0.09})
    Piece(8, 3, height - 2, width - 6, 1, {0.075, 0.079, 0.076})
    Piece(9, 2, 2, width - 4, height - 4, {0.055, 0.065, 0.070})
    segment:ClearAllPoints()
    segment:SetPoint("CENTER", segment.socket, "CENTER")
    segment:SetSize(math.max(1, width - 4), math.max(1, height - 4))
end

local function SetFacetAlpha(segment, ready, reset)
    for _, facet in ipairs(segment.facets) do
        if reset then facet.texture:SetAlpha(facet.alpha)
        elseif facet.texture.SetAlphaFromBoolean then
            local ok = pcall(facet.texture.SetAlphaFromBoolean, facet.texture, ready, facet.alpha, 0)
            if not ok then return false end
        elseif RP.Readable(ready) then facet.texture:SetAlpha(ready and facet.alpha or 0)
        else return false end
    end
    return true
end

function C:Layout(entry)
    local row = entry and entry.classResources
    local anchor = entry and entry.classResourceAnchor
    if not row or not anchor then return end
    if row.anchor ~= anchor then
        row:ClearAllPoints()
        row:SetAllPoints(anchor)
        row.anchor = anchor
    end
    local width, height = anchor:GetWidth(), anchor:GetHeight()
    if not Number(width) or not Number(height) or width <= 0 or height <= 0 then return false end
    local count = row.segmentCount or 1
    if row.layoutWidth == width and row.layoutHeight == height and row.layoutCount == count
        and row.layoutAggregate == row.aggregate then return true end
    local gap = count > 8 and 2 or GAP
    local desired = math.min(height, 12)
    local available = math.max(width, math.min(128, desired * count + gap * (count - 1)))
    local size = row.aggregate and width or math.min(desired, (available - gap * (count - 1)) / count)
    local gemHeight = row.aggregate and math.min(12, height) or size
    local start = (width - (size * count + gap * (count - 1))) / 2
    for i, segment in ipairs(row.segments) do
        segment.socket:ClearAllPoints()
        segment.socket:SetPoint("LEFT", row, "LEFT", start + (i - 1) * (size + gap), 0)
        segment.socket:SetSize(size, gemHeight)
        LayoutSocket(segment, size, gemHeight)
    end
    row.layoutWidth, row.layoutHeight, row.layoutCount = width, height, count
    row.layoutAggregate = row.aggregate
    return true
end

function C:Create(entry)
    if entry.classResources then return entry.classResources end
    local row = CreateFrame("Frame", nil, entry.button)
    row:EnableMouse(false)
    row:SetFrameLevel(entry.button:GetFrameLevel() + 12)
    row.segments, row.segmentCount, row.count, row.active = {}, 1, 0, false
    entry.classResources = row
    for i = 1, MAX_SEGMENTS do
        local socket = CreateFrame("Frame", nil, row)
        socket:EnableMouse(false)
        local segment = CreateFrame("StatusBar", nil, socket)
        segment.socket = socket
        segment:EnableMouse(false)
        segment:SetStatusBarTexture(WHITE)
        segment:SetMinMaxValues(0, 1)
        segment:SetValue(0)
        segment.fill = segment:GetStatusBarTexture()
        Socket(segment)
        socket:Hide()
        row.segments[i] = segment
    end
    local front = CreateFrame("Frame", nil, row)
    front:EnableMouse(false)
    front:SetAllPoints(row)
    front:SetFrameLevel(row:GetFrameLevel() + 8)
    row.text = front:CreateFontString(nil, "OVERLAY")
    row.text:SetFont(RP.Theme.font, 9, "OUTLINE")
    row.text:SetTextColor(0.96, 0.98, 1)
    row.text:SetAllPoints(front)
    self:Hide(entry)
    self:Layout(entry)
    return row
end

function C:Paint(entry, descriptor, data)
    local row = entry.classResources or self:Create(entry)
    local aggregate = descriptor.kind == "bar" or descriptor.maximum > MAX_SEGMENTS
        or descriptor.maximum ~= math.floor(descriptor.maximum)
    row.segmentCount = aggregate and 1 or descriptor.maximum
    row.aggregate = aggregate
    if not self:Layout(entry) then self:Hide(entry); return false end
    for i, segment in ipairs(row.segments) do
        if i <= row.segmentCount then
            segment.fill:SetAlpha(1)
            segment:SetStatusBarColor(descriptor.color[1], descriptor.color[2], descriptor.color[3])
            segment.socket.parts[9]:SetVertexColor(0.025 + descriptor.color[1] * 0.035,
                0.030 + descriptor.color[2] * 0.035, 0.035 + descriptor.color[3] * 0.035, 1)
            if not SetFacetAlpha(segment, nil, true) then self:Hide(entry); return false end
            if descriptor.kind == "runes" then
                segment:SetMinMaxValues(0, 1)
                segment:SetValue(1)
                local ready = data.runes[i]
                if segment.fill.SetAlphaFromBoolean then
                    local ok = pcall(segment.fill.SetAlphaFromBoolean, segment.fill, ready, 1, 0)
                    if not ok then self:Hide(entry); return false end
                elseif RP.Readable(ready) then segment:SetValue(ready and 1 or 0)
                else self:Hide(entry); return false end
                if not SetFacetAlpha(segment, ready) then self:Hide(entry); return false end
            else
                local lo = aggregate and 0 or (i - 1) * descriptor.step
                local hi = (aggregate and descriptor.maximum or i) * descriptor.step
                segment:SetMinMaxValues(lo, hi)
                -- The same secret current value goes straight to every native
                -- bar. Fixed public ranges do the clipping, not addon Lua.
                segment:SetValue(data.fill)
            end
            segment.socket:Show()
            segment:Show()
        else segment.socket:Hide() end
    end
    row.text:SetText("")
    if aggregate then row.text:SetFormattedText("%g/%g", data.current, descriptor.maximum) end
    row.active, row.resource, row.count = true, descriptor.token, descriptor.maximum
    row.targetBound, row.mode = descriptor.targetBound, aggregate and "bar" or descriptor.kind
    row:Show()
    return true
end

local function Available(entry)
    return entry and entry.enabled and not entry.preview and entry.plate and entry.plate.visible
        and Exists(entry.unit)
end

function C:SetOwner(token, entry)
    if self.ownedToken == token and self.owner == entry then return end
    self.ownedToken, self.owner = token, entry
    if RP.OnClassResourceDisplayChanged then RP:OnClassResourceDisplayChanged(token, entry) end
end

function C:OwnsResource(token)
    return RP.Readable(token) and type(token) == "string" and self.ownedToken == token and self.owner ~= nil
end

function C:GetStatus()
    if not Enabled() then return "Class resources: off" end
    local row = self.owner and self.owner.classResources
    if self.ownedToken and row and row.active and Number(row.count) then
        return "Class resources: " .. self.ownedToken .. " | capacity " .. tostring(row.count)
            .. " | HUD " .. self.owner.unit
    end
    return "Class resources: no active source with public capacity / no available HUD"
end

function C:Update()
    self.updates = self.updates + 1
    if not Available(self.entries.target) and not Available(self.entries.player) then
        for _, entry in pairs(self.entries) do self:Hide(entry) end
        self:SetOwner(nil, nil)
        return
    end
    local descriptor = self:Describe()
    local data = descriptor and self:ReadPower(descriptor)
    local chosen
    if descriptor and data and (not descriptor.targetBound or Exists("target")) then
        if Available(self.entries.target) then chosen = self.entries.target
        elseif Available(self.entries.player) then chosen = self.entries.player end
    end
    for _, entry in pairs(self.entries) do if entry ~= chosen then self:Hide(entry) end end
    if chosen then
        local ok, painted = pcall(self.Paint, self, chosen, descriptor, data)
        if ok and painted then self:SetOwner(descriptor.token, chosen); return end
        self:Hide(chosen)
    end
    self:SetOwner(nil, nil)
end

function C:Attach(entry)
    if not entry or entry.preview or (entry.unit ~= "player" and entry.unit ~= "target") then return end
    if not self.initialized then self:Initialize() end
    if not entry.classResources then self:Create(entry) end
    self.entries[entry.unit] = entry
    self:Update()
end

function C:Detach(entry)
    if not entry then return end
    self:Hide(entry)
    if self.entries[entry.unit] == entry then self.entries[entry.unit] = nil; self:Update() end
end

function C:Preview(entry)
    if not entry or not entry.preview then return end
    local descriptor = entry.unit == "target" and self:Describe()
    local data = descriptor and self:ReadPower(descriptor)
    if descriptor and data then
        local ok, painted = pcall(self.Paint, self, entry, descriptor, data)
        if ok and painted then return end
    end
    self:Hide(entry)
end

function C:Initialize()
    if self.initialized then return end
    self.initialized = true
    local frame = CreateFrame("Frame")
    self.eventFrame = frame
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED",
        "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_POINT_CHARGE",
        "UPDATE_SHAPESHIFT_FORM", "PLAYER_TALENT_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
        "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
        "RUNE_POWER_UPDATE", "RUNE_TYPE_UPDATE"}) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, unit)
        if event:sub(1, 5) == "UNIT_" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            if RP.IsSecret(unit) or (unit ~= nil and unit ~= "player") then return end
        end
        -- Rune event payloads are intentionally not inspected or indexed.
        C:Update()
    end)
end
