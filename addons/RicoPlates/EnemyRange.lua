local _, RP = ...
local E = { dimmed = setmetatable({}, { __mode = "k" }) }
RP.EnemyRange = E

local melee = { WARRIOR = true, PALADIN = true, ROGUE = true }
local autoAttack, autoShot = 6603, 75
local dimAlpha = 0.50
local trimLayers = { "outer", "metal", "inner" }

local function IsRange(value)
    return RP.Readable(value) and type(value) == "number" and value > 0 and value < math.huge
end

function E:SelectSpell()
    local spellBook, spells = C_SpellBook, C_Spell
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local itemType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    self.spell, self.spellName, self.maxRange, self.bookSlot, self.bookBank = nil, nil, nil, nil, nil
    if not (spells and spells.GetSpellInfo and spells.IsSpellInRange) then return end

    local _, class = UnitClass("player")
    local bestID, bestScore, bestSlot = autoAttack, 0, nil
    local lines = spellBook and bank and itemType and spellBook.GetNumSpellBookSkillLines() or 0
    for lineIndex = 1, lines do
        local line = spellBook.GetSpellBookSkillLineInfo(lineIndex)
        if line then
            for index = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local item = spellBook.GetSpellBookItemInfo(index, bank)
                local id = item and item.spellID
                local hunterShot = id and class == "HUNTER" and (id == autoShot or item.actionID == autoShot)
                if id and item.itemType == itemType and not item.isOffSpec and not item.isPassive then
                    if id == autoAttack and bestID == autoAttack then bestSlot = index end
                    if hunterShot or spells.IsSpellHarmful(id) then
                        local spell = spells.GetSpellInfo(id)
                        local range = spell and spell.maxRange
                        local score = 0
                        if hunterShot then score = 100
                        elseif IsRange(range) then
                            if melee[class] then score = range <= 8 and 100 - range or 0
                            else score = range end
                        end
                        if score > bestScore then bestID, bestScore, bestSlot = id, score, index end
                    end
                end
            end
        end
    end
    local spell = spells.GetSpellInfo(bestID)
    self.spell, self.bookSlot, self.bookBank = bestID, bestSlot, bank
    self.spellName = (spell and spell.name) or (spells.GetSpellName and spells.GetSpellName(bestID))
    if spell and IsRange(spell.maxRange) then self.maxRange = spell.maxRange end
end

local function SetRegionAlpha(region, alpha, secretInRange)
    if not region then return true end
    if alpha then
        region:SetAlpha(alpha)
        return true
    end
    return region.SetAlphaFromBoolean ~= nil
        and pcall(region.SetAlphaFromBoolean, region, secretInRange, 1, dimAlpha)
end

local function SetBarAlpha(plate, alpha, secretInRange)
    if not SetRegionAlpha(plate.health, alpha, secretInRange) then return false end
    if not plate.base or plate.unitFrame then return true end
    if not SetRegionAlpha(plate.back, alpha, secretInRange) then return false end
    local trim = plate.iron
    if trim then
        for _, layer in ipairs(trimLayers) do
            for _, edge in ipairs(trim[layer]) do
                if not SetRegionAlpha(edge, alpha, secretInRange) then return false end
            end
        end
    end
    return true
end

function E:Reset(plate)
    if not self.dimmed[plate] then return end
    self.dimmed[plate] = nil
    SetBarAlpha(plate, 1)
end

local function ReadRange(check, ...)
    local ok, inRange = pcall(check, ...)
    if ok then
        if not RP.Readable(inRange) then return inRange, true end
        if type(inRange) == "boolean" then return inRange end
    end
end

function E:Check(unit)
    local inRange, secret = ReadRange(C_Spell.IsSpellInRange, self.spell, unit)
    if secret or inRange ~= nil then return inRange, secret end
    if self.bookSlot and C_SpellBook.IsSpellBookItemInRange then
        inRange, secret = ReadRange(C_SpellBook.IsSpellBookItemInRange, self.bookSlot, self.bookBank, unit)
        if secret or inRange ~= nil then return inRange, secret end
    end
    if self.maxRange and type(UnitDistanceSquared) == "function" then
        local ok, distanceSquared, checked = pcall(UnitDistanceSquared, unit)
        if ok and RP.PublicTrue(checked) and IsRange(distanceSquared)
            and distanceSquared > self.maxRange * self.maxRange then return false end
    end
end

function E:Update(plate)
    local unit = plate.unit
    if not (RP.db.enabled and RP.db.enemyRange ~= false and self.spell and plate.visible
        and RP.Readable(unit) and unit) then
        self:Reset(plate)
        return
    end
    if (plate.baseKind or plate.kind) ~= "enemy" then
        local ok, canAttack = pcall(UnitCanAttack, "player", unit)
        if not (ok and RP.PublicTrue(canAttack)) then self:Reset(plate); return end
    end

    local inRange, secret = self:Check(unit)
    if secret then
        -- WoW can render a restricted boolean without revealing it to addon Lua.
        self.dimmed[plate] = "native"
        if not SetBarAlpha(plate, nil, inRange) then self:Reset(plate) end
    elseif inRange == false then
        if self.dimmed[plate] ~= "public" then
            self.dimmed[plate] = "public"
            SetBarAlpha(plate, dimAlpha)
        end
    else
        self:Reset(plate)
    end
end

function E:Refresh()
    if not RP.db then return end
    for _, plate in pairs(RP.Plates.active) do self:Update(plate) end
    local entry = RP.UnitFrames and RP.UnitFrames.frames.target
    if entry then self:Update(entry.plate) end
end

function E:Initialize()
    local ticker = CreateFrame("Frame")
    ticker:RegisterEvent("PLAYER_ENTERING_WORLD")
    ticker:RegisterEvent("SPELLS_CHANGED")
    ticker:SetScript("OnEvent", function()
        E:SelectSpell()
        E:Refresh()
        if RP.Options then RP.Options:RefreshState() end
    end)
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.25 then return end
        elapsed = 0
        if RP.db and RP.db.enabled and RP.db.enemyRange ~= false then E:Refresh() end
    end)
    self:SelectSpell()
end
