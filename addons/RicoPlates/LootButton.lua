-- An ordinary information button. It never targets a unit or changes the
-- secure unit button underneath it; RicoLoot owns the separate NPC loot view.
local _, RP = ...
local L = { plates = setmetatable({}, { __mode = "k" }), hudExtraPadding = 0 }
RP.LootButton = L
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GAP = 8

-- A small native gold-and-oak chest. It remains visible on clients that do not
-- ship a particular icon filename, and scales with the nameplate's HP height.
local function Chest(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(16, 14)
    icon:SetPoint("CENTER")
    icon:EnableMouse(false)
    local function Piece(x, y, width, height, r, g, b)
        local t = icon:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE)
        t:SetPoint("TOPLEFT", x, -y)
        t:SetSize(width, height)
        t:SetVertexColor(r, g, b, 1)
        return t
    end
    Piece(0, 2, 16, 11, 0.07, 0.045, 0.018)
    Piece(1, 5, 14, 7, 0.37, 0.20, 0.055)
    Piece(1, 2, 14, 4, 0.71, 0.45, 0.10)
    Piece(2, 1, 12, 2, 0.88, 0.65, 0.20)
    Piece(3, 1, 10, 1, 1, 0.86, 0.43)
    Piece(1, 6, 14, 1, 0.13, 0.075, 0.02)
    Piece(3, 3, 2, 9, 0.88, 0.65, 0.21)
    Piece(11, 3, 2, 9, 0.88, 0.65, 0.21)
    Piece(3, 3, 1, 8, 1, 0.84, 0.42)
    Piece(11, 3, 1, 8, 1, 0.84, 0.42)
    Piece(6, 5, 4, 5, 0.96, 0.75, 0.27)
    Piece(7, 6, 2, 3, 0.21, 0.13, 0.035)
    Piece(1, 12, 14, 1, 0.72, 0.47, 0.12)
    return icon
end

local function Public(value)
    if RP.IsSecret(value) then return nil end
    if type(value) == "table" and canaccesstable and not canaccesstable(value) then return nil end
    return value
end

local function Field(object, key)
    object = Public(object)
    if object == nil then return end
    local ok, value = pcall(function() return object[key] end)
    if ok then return Public(value) end
end

local function Call(object, method, ...)
    local getter = Field(object, method)
    if type(getter) ~= "function" then return end
    local ok, value = pcall(getter, object, ...)
    if ok then return Public(value) end
end

local function UnitValue(getter, unit)
    if type(Public(getter)) ~= "function" then return end
    local ok, value = pcall(getter, unit)
    if ok then return Public(value) end
end

local function Usable(frame, unprotected)
    return Public(frame) ~= nil and Call(frame, "IsForbidden") == false
        and (not unprotected or Call(frame, "IsProtected") == false)
end

local function API()
    local addon = Field(_G, "RicoLoot")
    if type(Field(addon, "OpenMobLoot")) == "function" then return addon end
end

local function OwnsUnit(p, unit)
    if p.unitFrame then
        local entry = RP.UnitFrames and RP.UnitFrames.frames.target
        return unit == "target" and entry and entry.enabled == true
            and entry.plate == p and entry.button == p.base and Usable(entry.button)
    end
    if not RP.Plates or RP.Plates.active[unit] ~= p or not Usable(p.base) then return false end
    local getter = Field(C_NamePlate, "GetNamePlateForUnit")
    local base = UnitValue(getter, unit)
    return base ~= nil and base == p.base
end

-- Resolve from the clicked plate, including after a pooled frame or target
-- token was reused. Never inspect restricted GUIDs and never use a target
-- fallback for an overhead plate.
function L:Resolve(p)
    if not RP.db or not RP.db.enabled or not Usable(p) or p.preview or p.unitFrame or p.visible ~= true then return end
    local unit = Public(p.unit)
    if type(unit) ~= "string" or unit == "" or not OwnsUnit(p, unit) then return end
    if UnitValue(UnitExists, unit) ~= true or UnitValue(UnitIsPlayer, unit) ~= false
        or UnitValue(UnitPlayerControlled, unit) ~= false then return end
    local guid = UnitValue(UnitGUID, unit)
    if type(guid) ~= "string" then return end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    id = tonumber(id)
    if not id or id < 1 or id > 4294967295 then return end
    local name = UnitValue(UnitName, unit)
    if type(name) ~= "string" or name == "" then name = nil end
    return id, name
end

local function ClearTooltip(button)
    if not button or not button.tooltipOwned then return end
    button.tooltipOwned = nil
    if Usable(GameTooltip) and (Call(GameTooltip, "IsOwned", button) == true
        or Call(GameTooltip, "GetOwner") == button) then
        pcall(GameTooltip.Hide, GameTooltip)
    end
end

function L:Layout(p)
    local button = Field(p, "lootButton")
    if not button or not Usable(p) or not Usable(button, true) then return end
    if p.unitFrame then button:Hide(); return end
    local anchor, point, offset, y = p, "RIGHT", GAP, 0
    local height = p.style and p.style.height or RP.db.height
    local width = math.max(22, height)
    button:SetSize(width, height)
    if button.icon then button.icon:SetScale(math.max(0.6, (height - 3) / 16)) end
    if button.layoutAnchor ~= anchor or button.layoutPoint ~= point
        or button.layoutOffset ~= offset or button.layoutY ~= y then
        button:ClearAllPoints()
        button:SetPoint("LEFT", anchor, point, offset, y)
        button.layoutAnchor, button.layoutPoint = anchor, point
        button.layoutOffset, button.layoutY = offset, y
    end
    if not p.unitFrame and p.quest and Usable(p.quest.text, true) then
        local textAnchor = button.active and button or p
        local textGap = button.active and 6 or 8
        if button.textAnchor ~= textAnchor then
            p.quest.text:ClearAllPoints()
            p.quest.text:SetPoint("LEFT", textAnchor, "RIGHT", textGap, 0)
            button.textAnchor = textAnchor
        end
    end
end

local function ConsumeClicks(button)
    local propagates = Call(button, "CanPropagateMouseClicks")
    if propagates == false then return true end
    -- This setter carries additional client restrictions even on an ordinary
    -- frame. A new combat-time button uses only the public default false.
    if propagates == true and not RP:IsInCombat() then
        local setter = Field(button, "SetPropagateMouseClicks")
        if type(setter) == "function" then pcall(setter, button, false) end
        return Call(button, "CanPropagateMouseClicks") == false
    end
    return false
end

function L:Build(p)
    if not Usable(p) or p.preview or p.unitFrame then return end
    self.plates[p] = true
    local button = p.lootButton
    if not button then
        local ok, created = pcall(CreateFrame, "Button", nil, p)
        if not ok or not Usable(created, true) then return end
        button, p.lootButton = created, created
        button:Hide()
    end
    if not Usable(button, true) or not ConsumeClicks(button) then return end
    if not button.configured then
        button:SetSize(22, RP.db.height)
        local level = Call(p.front, "GetFrameLevel")
        if type(level) == "number" then button:SetFrameLevel(level + 3) end
        button:EnableMouse(true)
        button:RegisterForClicks("LeftButtonUp")
        button.back = button:CreateTexture(nil, "BACKGROUND")
        button.back:SetTexture(WHITE)
        button.back:SetVertexColor(0.025, 0.035, 0.045, 1)
        button.back:SetAllPoints()
        button.icon = Chest(button)
        button.iron = RP.Plates:CreateIronTrim(button)
        button:SetScript("OnEnter", function(self)
            L:Refresh(p)
            if not self.active or not Usable(GameTooltip) then return end
            local _, name = L:Resolve(p)
            self.back:SetVertexColor(0.19, 0.15, 0.065, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("View full loot table", 1, 0.84, 0.42)
            if name then GameTooltip:AddLine(name, 0.92, 0.95, 0.98) end
            GameTooltip:AddLine("Open this creature's complete available loot table.", 0.65, 0.76, 0.80, true)
            GameTooltip:Show()
            self.tooltipOwned = true
        end)
        button:SetScript("OnLeave", function(self)
            self.back:SetVertexColor(0.025, 0.035, 0.045, 1)
            ClearTooltip(self)
        end)
        button:SetScript("OnHide", function(self) ClearTooltip(self) end)
        button:SetScript("OnClick", function(self, mouseButton)
            if Public(mouseButton) ~= "LeftButton" or not self.active or not Usable(self, true) then return end
            local id, name = L:Resolve(p)
            local addon = API()
            if not id or not addon then L:Detach(p); return end
            local ok = pcall(addon.OpenMobLoot, addon, id, name)
            if not ok then RP:Print("RicoLoot could not open the loot table.") end
        end)
        button.configured = true
    end
    self:Layout(p)
    return button
end

function L:Refresh(p)
    if p.unitFrame then self:Detach(p); return end
    if Usable(p) and not p.preview and (not p.unitFrame or p.unit == "target") then self.plates[p] = true end
    if not API() or not self:Resolve(p) then self:Detach(p); return end
    local button = self:Build(p)
    if not button then self:Detach(p); return end
    button.active = true
    self:Layout(p)
    button:Show()
end

function L:Detach(p)
    local button = Field(p, "lootButton")
    if not button then return end
    button.active = false
    ClearTooltip(button)
    if Usable(button, true) then button:Hide() end
    self:Layout(p)
end

function L:Initialize()
    if self.eventFrame then return end
    local frame = CreateFrame("Frame")
    self.eventFrame = frame
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" and Public(name) ~= "RicoLoot" then return end
        for p in pairs(L.plates) do L:Refresh(p) end
    end)
end
