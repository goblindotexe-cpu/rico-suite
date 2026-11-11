local _, RP = ...
local Money = {}
RP.PickPocketMoney = Money

local PICK_POCKET = 921
local OPEN_WINDOW_SECONDS = 4
local UNSOURCED_WINDOW_SECONDS = 1.25
local CLOSED_WINDOW_SECONDS = 1.5
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
    local coinTexture = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString
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
        AddDenominationPattern(patterns, seen, Read(coinTexture, 7 * coin.factor), 7)
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

local function ReceiptPattern(template)
    if type(template) ~= "string" then return end
    template = Normalize(template)
    local parts, start, captures, personal = { "^" }, 1, 0
    while true do
        local first, last, argument = template:find("%%(%d*)%$?s", start)
        if not first then break end
        parts[#parts + 1] = Escape(template:sub(start, first - 1))
        parts[#parts + 1] = "(.+)"
        captures = captures + 1
        if (tonumber(argument) or captures) == 1 then personal = captures end
        start = last + 1
    end
    if not personal then return end
    parts[#parts + 1] = Escape(template:sub(start)) .. "$"
    return { pattern = table.concat(parts), personal = personal }
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
    local now = GetTime()
    return { guid = guid, expires = now + OPEN_WINDOW_SECONDS, confirmedAt = confirmed and now or nil,
        targets = LiveTargets(name) }
end

local function HasLiveTarget(targets)
    for _, unit in ipairs(targetUnits) do
        local guid = Read(UnitGUID, unit)
        if guid and targets[guid] then
            local dead = Read(UnitIsDeadOrGhost, unit)
            if dead == false or dead == 0 then return true end
        end
    end
    return false
end

local function IsKnownDead(guid)
    for _, unit in ipairs(targetUnits) do
        if Read(UnitGUID, unit) == guid and RP.PublicTrue(Read(UnitIsDeadOrGhost, unit)) then return true end
    end
    return false
end

local function SlotSource(slot, targets)
    if type(GetLootSourceInfo) ~= "function" then return end
    local result = { pcall(GetLootSourceInfo, slot) }
    if not result[1] then return end
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

local function MatchesRecentCast(window)
    local confirmedAt = window.cast.confirmedAt
    return window.liveTarget and not window.mixed and confirmedAt
        and math.abs(window.openedAt - confirmedAt) <= UNSOURCED_WINDOW_SECONDS
end

function Money:Credit(amount)
    if amount <= 0 then return end
    local total = math.min(self.db.total + amount, MAX_COPPER)
    if total == self.db.total then return end
    self.db.total = total
    if self.onChanged then self.onChanged(total) end
end

function Money:Settle(window)
    if not window or not window.cast.confirmedAt then return end
    for _, coin in pairs(window.slots) do
        if coin.amount and not coin.credited and (coin.cleared or coin.received) and
            (coin.source or (not window.mixed and window.source) or MatchesRecentCast(window)) then
            coin.credited = true
            self:Credit(coin.amount)
        end
    end
    if window.closedAt and window.emptyReceipt and not window.sawSlots and MatchesRecentCast(window) then
        local amount = window.emptyReceipt
        window.emptyReceipt, window.emptyCredited = nil, true
        self:Credit(amount)
    end
end

function Money:Snapshot(isFromItem, canOpen, autoLoot)
    if not self.cast and not self.window then return end
    if RP.PublicTrue(isFromItem) or RP.PublicTrue(Read(IsFishingLoot)) then
        self.cast, self.window = nil, nil
        return
    end
    local count = Read(GetNumLootItems)
    if not WholeNumber(count) then return end
    local window = self.window
    if window and window.closedAt then
        if canOpen then self.cast, self.window = nil, nil end
        return
    end
    if not window then
        local cast = self.cast
        local now = GetTime()
        if not canOpen or not cast or cast.opened or now > cast.expires or not next(cast.targets) then return end
        cast.opened = true
        window = { cast = cast, slots = {}, cleared = {}, openedAt = now, liveTarget = HasLiveTarget(cast.targets) }
        self.window = window
    end
    window.autoLoot = window.autoLoot or RP.PublicTrue(autoLoot)
    window.sawSlots = window.sawSlots or count > 0

    local coinType = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or LOOT_SLOT_MONEY or 2
    for slot = 1, count do
        local kind = Read(GetLootSlotType, slot)
        if kind ~= 0 and not window.cleared[slot] then
            local source = SlotSource(slot, window.cast.targets)
            if source == false or (source and window.source and source ~= window.source) then
                window.mixed = true
            elseif source then
                window.source = source
            end
            if source == false then
                window.slots[slot] = nil
            elseif kind == coinType or not kind then
                local ok, _, name, _, _, _, _, _, _, _, isCoin = pcall(GetLootSlotInfo, slot)
                if ok and (kind == coinType or RP.PublicTrue(isCoin)) then
                    local coin = window.slots[slot] or {}
                    coin.amount = CoinAmount(name, self.denominations) or coin.amount
                    coin.source = source or coin.source
                    window.slots[slot] = coin
                end
            end
        end
    end
end

function Money:ClearSlot(slot)
    local window = self.window
    if not window or window.closedAt or not WholeNumber(slot) or slot == 0 then return end
    window.cleared[slot] = true
    local coin = window.slots[slot]
    if not coin then return end
    coin.cleared = true
    self:Settle(window)
end

function Money:Receive(text)
    local window = self.window
    if not window or not RP.Readable(text) or type(text) ~= "string" then return end
    local now = GetTime()
    if window.closedAt and now - window.closedAt > CLOSED_WINDOW_SECONDS then return end

    text = Normalize(text)
    local amount
    for _, receipt in ipairs(self.receiptPatterns) do
        local captures = { text:match(receipt.pattern) }
        amount = CoinAmount(captures[receipt.personal], self.denominations)
        if amount then break end
    end
    if not amount then return end

    local unnamed, ambiguous
    for _, coin in pairs(window.slots) do
        if coin.amount == amount then
            coin.received = true
            self:Settle(window)
            return
        elseif not coin.amount then
            ambiguous = unnamed ~= nil
            unnamed = coin
        end
    end
    if unnamed and not ambiguous then
        unnamed.amount, unnamed.received = amount, true
    elseif window.autoLoot and not window.sawSlots and not window.emptyCredited and
        now - window.openedAt <= CLOSED_WINDOW_SECONDS then
        window.emptyReceipt = amount
    end
    self:Settle(window)
end

function Money:HandleEvent(event, arg, second, third, fourth)
    if event == "LOOT_READY" or event == "LOOT_OPENED" or event == "LOOT_SLOT_CHANGED" then
        local canOpen = event ~= "LOOT_SLOT_CHANGED"
        self:Snapshot(event == "LOOT_OPENED" and second, canOpen, canOpen and arg)
    elseif event == "LOOT_SLOT_CLEARED" then
        self:ClearSlot(arg)
    elseif event == "CHAT_MSG_MONEY" then
        self:Receive(arg)
    elseif event == "LOOT_CLOSED" then
        local window = self.window
        if window and not window.closedAt then
            -- A combat opener can dismiss the window before the money receipt arrives.
            window.closedAt = GetTime()
            self:Settle(window)
        end
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
                    cast.confirmedAt = cast.confirmedAt or GetTime()
                    self:Settle(self.window)
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
    self.receiptPatterns = { ReceiptPattern(YOU_LOOT_MONEY or "You loot %s"), ReceiptPattern(YOU_LOOT_MONEY_GUILD) }
    local events = CreateFrame("Frame")
    self.events = events
    for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
        pcall(events.RegisterUnitEvent, events, event, "player")
    end
    for _, event in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED",
        "LOOT_CLOSED", "CHAT_MSG_MONEY", "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, ...) self:HandleEvent(event, ...) end)
end
