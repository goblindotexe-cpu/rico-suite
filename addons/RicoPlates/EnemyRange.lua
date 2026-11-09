local _, RP = ...
local E = { dimmed = setmetatable({}, { __mode = "k" }) }
RP.EnemyRange = E

local melee = { WARRIOR = true, PALADIN = true, ROGUE = true }
local autoAttack, autoShot = 6603, 75

function E:SelectSpell()
    local spellBook, spells = C_SpellBook, C_Spell
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local itemType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    self.spell, self.spellName = nil, nil
    if not (spellBook and spells and spells.IsSpellInRange and bank and itemType) then return end

    local _, class = UnitClass("player")
    local bestID, bestScore = autoAttack, -1
    for lineIndex = 1, spellBook.GetNumSpellBookSkillLines() do
        local line = spellBook.GetSpellBookSkillLineInfo(lineIndex)
        if line then
            for index = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local item = spellBook.GetSpellBookItemInfo(index, bank)
                local id = item and item.spellID
                local hunterShot = id and class == "HUNTER" and (id == autoShot or item.actionID == autoShot)
                if id and item.itemType == itemType and not item.isOffSpec and not item.isPassive
                    and (hunterShot or spells.IsSpellHarmful(id)) then
                    local spell = spells.GetSpellInfo(id)
                    local range = spell and spell.maxRange or 0
                    if hunterShot or range > 0 then
                        local score = range
                        if melee[class] then score = range <= 8 and 100 - range or -range end
                        if hunterShot then score = 100 end
                        if score > bestScore then bestID, bestScore = id, score end
                    end
                end
            end
        end
    end
    self.spell = bestID
    self.spellName = spells.GetSpellName(bestID)
end

function E:Reset(plate)
    if not self.dimmed[plate] then return end
    self.dimmed[plate] = nil
    plate.health:SetAlpha(1)
end

function E:Update(plate)
    local outOfRange = false
    if RP.db.enabled and RP.db.enemyRange ~= false and self.spell and plate.visible and plate.unit
        and RP.PublicTrue(UnitCanAttack("player", plate.unit)) then
        local ok, inRange = pcall(C_Spell.IsSpellInRange, self.spell, plate.unit)
        outOfRange = ok and RP.Readable(inRange) and inRange == false
    end
    if not outOfRange then self:Reset(plate); return end
    if not self.dimmed[plate] then
        self.dimmed[plate] = true
        plate.health:SetAlpha(0.50)
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
