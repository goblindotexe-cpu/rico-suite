-- Positive evidence from readable creature GUIDs in real loot slots.
-- Preset data is never rewritten and no kill count or drop rate is inferred.
local _, R = ...
local O = { tableCache = {}, guidMetadata = {}, metadataOrder = {} }
R.Observations = O
local unpack = unpack or table.unpack
local SOURCE_LIMIT = 4000

local function NPCID(guid)
    if not R.String(guid) then return end
    local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    id = tonumber(id)
    if R.Number(id) and id > 0 and id == math.floor(id) then return id end
end

function O:Initialize()
    if not R.db then return end
    for _, key in ipairs({"observations", "observationSources", "observationOrder", "observationZones"}) do
        if not R.Table(R.db[key]) then R.db[key] = {} end
    end
end

function O:CurrentZone()
    local ok, mapID = R.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    if not ok or not R.Number(mapID) then mapID = nil end
    local gotName, name = R.Call(GetRealZoneText or GetZoneText)
    if not gotName or not R.String(name) or name == "" then name = nil end
    for id, zone in pairs(R.Data.zones or {}) do
        if (mapID and zone.uiMapID == mapID) or (name and R:Normalize(zone.name) == R:Normalize(name)) then return id end
    end
    if not name then return end
    local key = "observed:" .. tostring(mapID or R:Normalize(name):sub(1, 70))
    R.db.observationZones[key] = {id = key, name = name, uiMapID = mapID, provenance = "local_observed"}
    return key
end

function O:RememberUnit(unit)
    if not R.db then return end
    local ok, guid = R.Call(UnitGUID, unit)
    local id = ok and NPCID(guid)
    if not id then return end
    local gotName, name = R.Call(UnitName, unit)
    if not gotName or not R.String(name) or name == "" then return end
    local gotLevel, level = R.Call(UnitLevel, unit)
    if not gotLevel or not R.Number(level) or level <= 0 then level = nil end
    if not self.guidMetadata[guid] then
        self.metadataOrder[#self.metadataOrder + 1] = guid
        if #self.metadataOrder > 1000 then self.guidMetadata[table.remove(self.metadataOrder, 1)] = nil end
    end
    self.guidMetadata[guid] = {name = name, level = level}
    local known = R.db.observations[id]
    if R.Table(known) and known.name ~= name then
        known.name, known.level = name, level
        self:Changed(id)
    end
end

function O:Changed(id)
    self.tableCache[id] = nil
    R.indexes, R.catalogs, R.rowViews = nil, nil, nil
    if R.Wishlist then R.Wishlist:InvalidateSources() end
    R:RequestRefresh()
    if R.MobLoot and R.MobLoot:IsShown() and R.MobLoot.npcID == id then
        R.MobLoot:Open(id, R:GetMob(id).name)
    end
    if R.Wishlist then R.Wishlist:Refresh() end
end

function O:Record(guid, id, items, zoneID)
    local db = R.db
    local source = db.observationSources[guid]
    if not R.Table(source) then
        source = {items = {}}
        db.observationSources[guid] = source
        db.observationOrder[#db.observationOrder + 1] = guid
        if #db.observationOrder > SOURCE_LIMIT then
            local expired = table.remove(db.observationOrder, 1)
            db.observationSources[expired], self.guidMetadata[expired] = nil, nil
        end
    end
    if not R.Table(source.items) then source.items = {} end
    local mob = db.observations[id]
    if not R.Table(mob) then
        local base, meta = R.Data.mobs[id], self.guidMetadata[guid]
        mob = {name = meta and meta.name or base and base.name or ("NPC " .. id),
            level = meta and meta.level, items = {}, zones = {}}
        db.observations[id] = mob
    end
    if not R.Table(mob.items) then mob.items = {} end
    if not R.Table(mob.zones) then mob.zones = {} end
    if zoneID then mob.zones[zoneID] = true end
    local changed = false
    for itemID, item in pairs(items) do
        local previous = tonumber(source.items[itemID]) or 0
        if item.quantity > previous then
            local row = mob.items[itemID]
            if not R.Table(row) then
                row = {itemID = itemID, occurrences = 0, quantitySeen = 0}
                mob.items[itemID] = row
            end
            if previous == 0 then row.occurrences = (tonumber(row.occurrences) or 0) + 1 end
            row.quantitySeen = (tonumber(row.quantitySeen) or 0) + item.quantity - previous
            row.name, row.icon, row.quality = item.name or row.name, item.icon or row.icon, item.quality or row.quality
            source.items[itemID] = item.quantity
            R.itemCache[itemID] = nil
            changed = true
        end
    end
    if changed then self:Changed(id) end
end

function O:Snapshot()
    if not R.db then return end
    self:Initialize()
    local fishingOK, fishing = R.Call(IsFishingLoot)
    if fishingOK and (R.IsSecret(fishing) or fishing == true) then return end
    local ok, count = R.Call(GetNumLootItems)
    if not ok or not R.Number(count) or count < 1 or count > 100 then return end
    self:RememberUnit("target"); self:RememberUnit("mouseover")
    local bySource = {}
    for slot = 1, count do
        local gotLink, link = R.Call(GetLootSlotLink, slot)
        local itemID = gotLink and R.String(link) and tonumber(link:match("item:(%d+)"))
        if R.Number(itemID) and itemID > 0 then
            local info = {R.Call(GetLootSlotInfo, slot)}
            local quantity, name, icon, quality = info[4], info[3], info[2], info[6]
            if info[1] and R.Number(quantity) and quantity > 0 then
                local values = {R.Call(GetLootSourceInfo, slot)}
                -- Native API returns alternating GUID, quantity pairs.
                local sourceItems, total, valid = {}, 0, values[1] == true
                if (#values - 1) % 2 ~= 0 or #values > 129 then valid = false end
                if valid then
                    for index = 2, #values, 2 do
                        local guid, amount = values[index], values[index + 1]
                        local id = NPCID(guid)
                        if not id or not R.Number(amount) or amount <= 0 or amount ~= math.floor(amount) then valid = false; break end
                        total = total + amount
                        sourceItems[#sourceItems + 1] = {guid = guid, id = id, amount = amount}
                    end
                end
                -- Reject partial or mixed/unreadable source attribution.
                if valid and #sourceItems > 0 and total == quantity then
                    for _, source in ipairs(sourceItems) do
                        local data = bySource[source.guid]
                        if not data then data = {id = source.id, items = {}}; bySource[source.guid] = data end
                        local item = data.items[itemID]
                        if not item then
                            item = {quantity = 0, name = R.String(name) and name or nil,
                                icon = (R.String(icon) or R.Number(icon)) and icon or nil,
                                quality = R.Number(quality) and quality or nil}
                            data.items[itemID] = item
                        end
                        item.quantity = item.quantity + source.amount
                    end
                end
            end
        end
    end
    local zoneID = next(bySource) and self:CurrentZone()
    for guid, source in pairs(bySource) do self:Record(guid, source.id, source.items, zoneID) end
end

function O:GetTable(id)
    local observed = R.db and R.db.observations and R.db.observations[id]
    if not R.Table(observed) or not R.Table(observed.items) or not next(observed.items) then return end
    if self.tableCache[id] then return self.tableCache[id] end
    local rows = {}
    for itemID, value in pairs(observed.items) do
        if R.Number(itemID) and R.Table(value) then
            rows[#rows + 1] = {itemID = itemID, name = value.name, icon = value.icon, quality = value.quality,
                occurrences = value.occurrences, quantitySeen = value.quantitySeen}
        end
    end
    table.sort(rows, function(a, b) return a.itemID < b.itemID end)
    local tbl = {key = "local:" .. id, method = "observed", provenance = "local_observed",
        source = "local_observed", rateKind = "positive_observations", label = "Your observed drops", rows = rows,
        note = "Confirmed items seen in creature-sourced loot windows. Loot method is not inferred. This is not a complete loot table or a drop-rate estimate."}
    self.tableCache[id] = tbl
    return tbl
end

O.frame = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT"}) do O.frame:RegisterEvent(event) end
O.frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then if name == R.name then O:Initialize() end
    elseif event == "PLAYER_TARGET_CHANGED" then O:RememberUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then O:RememberUnit("mouseover")
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" or event == "LOOT_SLOT_CHANGED" then O:Snapshot() end
end)
