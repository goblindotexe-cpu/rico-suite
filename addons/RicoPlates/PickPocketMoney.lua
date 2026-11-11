local _, RP = ...
local Money = {}
RP.PickPocketMoney = Money

local PICK_POCKET = 921
local OPEN_WINDOW_SECONDS = 4
local MAX_COPPER = 9007199254740991
local targetUnits = { "target", "mouseover", "focus", "softenemy" }

local function Read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and RP.Readable(value) then return value end
end

local function WholeNumber(value)
    return RP.Readable(value) and type(value) == "number" and value >= 0 and value <= MAX_COPPER and value % 1 == 0
end

local function Normalize(text)
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("%s+", " "):lower()
end

local function Escape(text)
    return (text:gsub("([^%w])", "%%%1"))
end

local function AddDenominationPattern(patterns, seen, sample, number)
    if type(sample) ~= "string" then return end
    sample = Normalize(sample)
    local first, last = sample:find(tostring(number), 1, true)
    if not first then return end
    local pattern = Escape(sample:sub(1, first - 1)) .. "(%d[%d%., ]*)" .. Escape(sample:sub(last + 1))
    if not seen[pattern] then
        seen[pattern] = true
        patterns[#patterns + 1] = pattern
    end
end

local function BuildDenominations()
    local coinText = C_CurrencyInfo and C_CurrencyInfo.GetCoinText or GetCoinText
    local denominations = {
        { factor = 10000, format = GOLD_AMOUNT, fallback = "%d Gold" },
        { factor = 100, format = SILVER_AMOUNT, fallback = "%d Silver" },
        { factor = 1, format = COPPER_AMOUNT, fallback = "%d Copper" },
    }
    for _, coin in ipairs(denominations) do
        local patterns, seen = {}, {}
        coin.patterns = patterns
        for _, number in ipairs({ 1, 2, 5, 11, 21 }) do
            AddDenominationPattern(patterns, seen, Read(coinText, number * coin.factor, "\n"), number)
        end
        local template = coin.format
        if type(template) == "string" then
            for alternative = 1, 2 do
                local localized = template:gsub("|4([^:;]+):([^;]+);", function(singular, plural)
                    return alternative == 1 and singular or plural
                end)
                AddDenominationPattern(patterns, seen, Read(string.format, localized, 7), 7)
            end
        end
        AddDenominationPattern(patterns, seen, coin.fallback:format(7), 7)
        table.sort(patterns, function(a, b) return #a > #b end)
    end
    return denominations
end

local function CoinAmount(text, denominations)
    if not RP.Readable(text) or type(text) ~= "string" then return end
    text = Normalize(text)
    local copper = 0
    for _, coin in ipairs(denominations) do
        for _, pattern in ipairs(coin.patterns) do
            local first, last, digits = text:find(pattern)
            if first then
                copper = copper + tonumber((digits:gsub("[^%d]", ""))) * coin.factor
                text = text:sub(1, first - 1) .. text:sub(last + 1)
                break
            end
        end
    end
    if WholeNumber(copper) and copper > 0 and text:match("^[%s,%.;]*$") then return copper end
end

local function LiveTargets(name)
    local matching, candidates = {}, {}
    for _, unit in ipairs(targetUnits) do
        local target = Read(UnitGUID, unit)
        if type(target) == "string" and target:match("^Creature%-") and not RP.PublicTrue(Read(UnitIsDeadOrGhost, unit)) then
            candidates[target] = true
            if name and name ~= "" and Read(UnitName, unit) == name then matching[target] = true end
        end
    end
    return next(matching) and matching or candidates
end

local function NewCast(guid, name, confirmed)
    return { guid = guid, expires = GetTime() + OPEN_WINDOW_SECONDS, confirmed = confirmed, queued = 0,
        targets = LiveTargets(name) }
end

local function IsKnownDead(guid)
    for _, unit in ipairs(targetUnits) do
        if Read(UnitGUID, unit) == guid and RP.PublicTrue(Read(UnitIsDeadOrGhost, unit)) then return true end
    end
    return false
end

-- A coin slot may have no source GUID on some clients. Only infer its source
-- from other slots in the same window if they all name the same Pick Pocket target.
local function SlotSource(slot, targets)
    if type(GetLootSourceInfo) ~= "function" then return end
    local result = { pcall(GetLootSourceInfo, slot) }
    if not result[1] then return false end
    local matched
    for index = 2, #result, 2 do
        local guid = result[index]
        if not RP.Readable(guid) then return false end
        if guid and guid ~= "" then
            if not targets[guid] or (matched and matched ~= guid) or IsKnownDead(guid) then return false end
            matched = guid
        end
    end
    return matched
end

function Money:Credit(amount)
    if amount <= 0 then return end
    local total = math.min(self.db.total + amount, MAX_COPPER)
    if total == self.db.total then return end
    self.db.total = total
    if self.onChanged then self.onChanged(total) end
end

function Money:Snapshot(isFromItem)
    if not self.cast and not self.window then return end
    if RP.PublicTrue(isFromItem) or RP.PublicTrue(Read(IsFishingLoot)) then
        self.cast, self.window = nil, nil
        return
    end
    local count = Read(GetNumLootItems)
    if not WholeNumber(count) or count == 0 then return end
    local window = self.window
    if not window then
        local cast = self.cast
        if not cast or cast.opened or GetTime() > cast.expires or not next(cast.targets) then return end
        cast.opened = true
        window = { cast = cast, slots = {}, cleared = {} }
        self.window = window
    end

    local coinType = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or LOOT_SLOT_MONEY or 2
    for slot = 1, count do
        local kind = Read(GetLootSlotType, slot)
        if kind and kind ~= 0 and not window.cleared[slot] then
            local source = SlotSource(slot, window.cast.targets)
            if source == false or (source and window.source and source ~= window.source) then
                window.mixed = true
            elseif source then
                window.source = source
            end
            if kind == coinType then
                local ok, _, name = pcall(GetLootSlotInfo, slot)
                local amount = ok and CoinAmount(name, self.denominations)
                window.slots[slot] = amount and source ~= false and { amount = amount, source = source } or nil
            else
                window.slots[slot] = nil
            end
        end
    end
end

function Money:ClearSlot(slot)
    local window = self.window
    if not window or not WholeNumber(slot) or slot == 0 then return end
    local coin = window.slots[slot]
    window.slots[slot], window.cleared[slot] = nil, true
    if not coin or (not coin.source and (not window.source or window.mixed)) then return end
    local cast = window.cast
    if cast.confirmed then self:Credit(coin.amount)
    else cast.queued = cast.queued + coin.amount end
end

function Money:HandleEvent(event, arg, second, third, fourth)
    if event == "LOOT_READY" or event == "LOOT_OPENED" or event == "LOOT_SLOT_CHANGED" then
        self:Snapshot(event == "LOOT_OPENED" and second)
    elseif event == "LOOT_SLOT_CLEARED" then
        self:ClearSlot(arg)
    elseif event == "LOOT_CLOSED" then
        self.window = nil
        if self.cast and self.cast.opened and self.cast.confirmed then self.cast = nil end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self.cast, self.window = nil, nil
    elseif RP.Readable(arg) and arg == "player" then
        if event == "UNIT_SPELLCAST_SENT" then
            if RP.Readable(fourth) and fourth == PICK_POCKET and RP.Readable(third) then
                local name = RP.Readable(second) and type(second) == "string" and second or nil
                self.cast, self.window = NewCast(third, name, false), nil
            end
        elseif RP.Readable(third) and third == PICK_POCKET and RP.Readable(second) then
            local cast = self.cast
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                if not cast or cast.guid ~= second then
                    self.cast, self.window = NewCast(second, nil, true), nil
                elseif GetTime() <= cast.expires then
                    if not next(cast.targets) then cast.targets = LiveTargets() end
                    cast.confirmed = true
                    self:Credit(cast.queued)
                    cast.queued = 0
                end
            elseif cast and cast.guid == second then
                self.cast, self.window = nil, nil
            end
        end
    end
end

function Money:Initialize(db, onChanged)
    if self.events then return end
    self.db, self.onChanged = db, onChanged
    db.total = WholeNumber(db.total) and db.total or 0
    self.denominations = BuildDenominations()
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
        pcall(events.RegisterUnitEvent, events, event, "player")
    end
    for _, event in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED",
        "LOOT_CLOSED", "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, ...) self:HandleEvent(event, ...) end)
end
