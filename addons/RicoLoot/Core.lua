-- RicoLoot: source browser with separate, positive-only local drop observations.
-- Copyright (C) 2026 Rico. Distributed under GNU GPL version 3 or later.
local addonName, R = ...
_G.RicoLoot = R
R.name, R.version = addonName, "1.5.1"
R.defaults = { zoneID = 0, tableIndex = 1, includeReference = true, x = 0, y = 0 }
R.decoded, R.decodedOrder, R.itemCache, R.requestedItems = {}, {}, {}, {}
local unpack = unpack or table.unpack

function R.IsSecret(value) return issecretvalue and issecretvalue(value) or false end
function R.Number(value)
    return not R.IsSecret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
function R.String(value) return not R.IsSecret(value) and type(value) == "string" end
function R.Table(value)
    return not R.IsSecret(value) and type(value) == "table"
        and (not canaccesstable or canaccesstable(value))
end
function R.Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
function R:Print(message)
    if DEFAULT_CHAT_FRAME and self.String(message) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff56dfc4RicoLoot|r: " .. message)
    end
end

-- Translate presentation metadata without changing the supplied source data.
local displayText = {
    ["Bekende Forever-bètadrops"] = "Known Forever beta drops",
    ["Classic DB 2023 · Buit"] = "Classic DB 2023 · Loot",
    ["Classic DB 2023 · Villen"] = "Classic DB 2023 · Skinning",
    ["Classic DB 2023 · Zakkenrollen"] = "Classic DB 2023 · Pickpocket",
    ["Classic · aanvullende relaties zonder kans"] = "Classic · additional entries without rates",
    ["Classic-referentie: buit"] = "Classic reference: loot",
    ["Forever: waargenomen loot"] = "Forever: observed loot",
    ["LootInsight / CMaNGOS Classic-referentie"] = "LootInsight / CMaNGOS Classic reference",
    ["pfQuest Vanilla-coördinaten via LootInsight"] = "pfQuest Vanilla coordinates via LootInsight",
    ["Lootified: bekende Forever-bètadrops"] = "Lootified: known Forever beta drops",
    ["CMaNGOS Classic-DB z2815 (Classic-referentie)"] = "CMaNGOS Classic DB z2815 (Classic reference)",
    ["Everloot — Forever-waarnemingen"] = "Everloot — Forever observations",
    ["Aanvullende corpse-lootrelaties uit LootInsight 2.18.0 (uitgave 17 oktober 2026); moment van de onderliggende Classic-import onbekend. Apart gehouden van de SQL-basiskansen. Geen bevestiging voor Forever."] = "Additional corpse loot entries from LootInsight 2.18.0 (October 17, 2026); the date of the underlying Classic import is unknown. Kept separate from SQL base rates. Not confirmed for Forever.",
    ["Bekende drops uit de Forever-bèta. Geen volledige loottabel en geen bevestigde Forever-percentages."] = "Known drops from the Forever beta. Not a complete loot table or confirmed Forever rates.",
    ["Classic DB-basiskans (1× lootrollen), basissnapshot 2023-10-09; niet bevestigd voor Forever. Percentages beschrijven uitsluitend aantoonbare DB-selectiepaden vóór servermodifiers, loot-slotlimieten en persoonlijke buitverdeling. Questvoorwaarden, andere voorwaarden, herhaalde/overlappende referenties en afhankelijke poolselectie blijven onbekend. De 437 latere repository-updates zijn niet toegepast."] = "Classic DB base rate (1× loot rolls), baseline snapshot October 9, 2023; not confirmed for Forever. Rates describe documented database selection paths before server modifiers, loot slot limits and personal loot distribution. Quest and other conditions, repeated or overlapping references and dependent pool selection remain unknown. The 437 later repository updates are not applied.",
    ["Exacte Classic-zonetoewijzingen; geen bewijs van actuele Forever-spawns."] = "Exact Classic zone assignments; not evidence of current Forever spawns.",
    ["Gedateerde bekende Forever-bossdrops, geen volledige tabel. De gemengde bron bewijst geen algemene Forever-kans; percentages zijn daarom weggelaten."] = "Dated known Forever boss drops; not a complete table. The mixed source does not establish a general Forever rate, so rates are omitted.",
    ["Vooraf geladen Classic 1.12 corpse-lootrelaties, inclusief grijze items en questitems. Geen bevestiging voor Forever. Deze bron bevat geen percentages, skinning of pickpocket-tabellen."] = "Prefilled Classic 1.12 corpse loot entries, including poor-quality and quest items. Not confirmed for Forever. This source has no rates, skinning or pickpocket tables.",
    ["Vooraf geladen Classic-buit; niet geverifieerd in Forever. Ontbrekend percentage is onbekend, geen 0%."] = "Prefilled Classic loot; not verified in Forever. A missing rate is unknown, not 0%.",
    ["Data from Everloot (https://everloot.app), CC BY-SA 4.0. Kans = vensters met item / geobserveerde lootvensters; geen kans per kill."] = "Data from Everloot (https://everloot.app), CC BY-SA 4.0. Rate = windows containing the item / observed loot windows; not a rate per kill.",
    ["Zeer kleine steekproef: 8 lootvensters van 3 installaties voor deze mob; niet 3 bevestigingen per item. Moblevels zijn samengenomen. Geen bevestigde Forever-locatie in deze bron; een zonekoppeling kan uit de Classic-referentie komen. Data from Everloot (https://everloot.app), CC BY-SA 4.0."] = "Very small sample: 8 loot windows from 3 installations for this creature; not 3 confirmations per item. Creature levels are combined. This source has no confirmed Forever location; zone mappings may come from the Classic reference. Data from Everloot (https://everloot.app), CC BY-SA 4.0.",
}
function R:DisplayText(value)
    return self.String(value) and (displayText[value] or value) or ""
end

local accents = { ["á"]="a",["à"]="a",["â"]="a",["ä"]="a",["ã"]="a",["å"]="a",
    ["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",
    ["ó"]="o",["ò"]="o",["ô"]="o",["ö"]="o",["õ"]="o",["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",
    ["ç"]="c",["ñ"]="n",["Á"]="a",["É"]="e",["Ö"]="o",["Ü"]="u",["ß"]="ss" }
function R:Normalize(value)
    if not self.String(value) then return "" end
    local s = value:sub(1, 250):lower()
    s = s:gsub("[\194-\244][\128-\191]+", accents)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ZoneKey(value)
    return R.Number(value) or R.String(value)
end
local function HasZone(mob, zoneID)
    if zoneID == 0 then return true end
    for _, id in ipairs(mob.zones or {}) do if id == zoneID then return true end end
    return false
end
local function SourceRank(tbl)
    if tbl.provenance == "local_observed" then return 0 end
    if tbl.provenance == "forever_observed" then return 1 end
    if tbl.provenance == "forever_reference" then return 2 end
    return 3
end

local function ResolveZoneName(zone)
    if zone and zone.nameFromMap then
        local ok, info = R.Call(C_Map and C_Map.GetMapInfo, zone.uiMapID)
        if ok and R.Table(info) and R.String(info.name) and info.name ~= "" then
            zone.name = info.name
            zone.nameFromMap = nil
        end
    end
    return zone
end

function R:GetZone(id)
    return ResolveZoneName(self.Data.zones[id]) or (self.db and self.db.observationZones and self.db.observationZones[id])
end
function R:GetAllZones()
    local zones = {}
    for id, zone in pairs(self.Data.zones or {}) do zones[id] = ResolveZoneName(zone) end
    for id, zone in pairs(self.db and self.db.observationZones or {}) do zones[id] = zone end
    return zones
end
function R:GetMob(id)
    local base = self.Data.mobs[id]
    local observed = self.db and self.db.observations and self.db.observations[id]
    local tbl = self.Observations and self.Observations:GetTable(id)
    if not tbl then return base end
    local mob = {}
    for key, value in pairs(base or {}) do mob[key] = value end
    mob.id, mob.name = id, observed.name or (base and base.name) or ("NPC " .. id)
    mob.minLevel, mob.maxLevel = mob.minLevel or observed.level, mob.maxLevel or observed.level
    mob.tables, mob.zones = {tbl}, {}
    for _, value in ipairs(base and base.tables or {}) do mob.tables[#mob.tables + 1] = value end
    local seen = {}
    for _, value in ipairs(base and base.zones or {}) do mob.zones[#mob.zones + 1] = value; seen[value] = true end
    for value in pairs(observed.zones or {}) do if not seen[value] then mob.zones[#mob.zones + 1] = value end end
    return mob
end
function R:GetAllMobs()
    local mobs = {}
    for id in pairs(self.Data.mobs or {}) do mobs[id] = self:GetMob(id) end
    for id in pairs(self.db and self.db.observations or {}) do mobs[id] = self:GetMob(id) end
    return mobs
end
function R:GetSourceInfo(tbl)
    if tbl and tbl.provenance == "local_observed" then
        return {name = "Your recorded creature loot", note = tbl.note}
    end
    return self.Data.sources[tbl and tbl.source] or {}
end

function R:GetTables(mob)
    if not mob then return {} end
    local result = {}
    for _, tbl in ipairs(mob.tables or {}) do
        if tbl.provenance ~= "classic_reference" or self.db.includeReference then result[#result + 1] = tbl end
    end
    table.sort(result, function(a, b)
        local ar, br = SourceRank(a), SourceRank(b)
        if ar ~= br then return ar < br end
        return tostring(a.key or a.method or "") < tostring(b.key or b.method or "")
    end)
    return result
end

-- Only small NPC/name/zone indexes are built. Loot relations stay packed until
-- a particular creature/source table is selected; no million-row login scan.
function R:BuildIndexes()
    if self.indexes then return end
    local indexes = { mobs = {}, zones = {}, byMap = {}, byZoneName = {} }
    for id, zone in pairs(self:GetAllZones()) do
        zone.id = zone.id or id
        zone._search = self:Normalize(zone.name)
        indexes.zones[#indexes.zones + 1] = zone
        if self.Number(zone.uiMapID) then indexes.byMap[zone.uiMapID] = id end
        indexes.byZoneName[zone._search] = id
        for _, alias in ipairs(zone.aliases or {}) do indexes.byZoneName[self:Normalize(alias)] = id end
    end
    for id, mob in pairs(self:GetAllMobs()) do
        mob.id = mob.id or id
        mob._search = self:Normalize(mob.name)
        indexes.mobs[#indexes.mobs + 1] = mob
    end
    table.sort(indexes.mobs, function(a, b)
        if a._search ~= b._search then return a._search < b._search end
        return a.id < b.id
    end)
    table.sort(indexes.zones, function(a, b) return a._search < b._search end)
    self.indexes = indexes
end

function R:GetCatalog()
    self:BuildIndexes()
    local mode = self.db.includeReference and "all" or "forever"
    self.catalogs = self.catalogs or {}
    if self.catalogs[mode] then return self.catalogs[mode] end
    local catalog = { mobs = {}, zones = {}, zoneCounts = {} }
    for _, mob in ipairs(self.indexes.mobs) do
        if #self:GetTables(mob) > 0 then
            catalog.mobs[#catalog.mobs + 1] = mob
            local seen = {}
            for _, key in ipairs(mob.zones or {}) do
                if not seen[key] then
                    catalog.zoneCounts[key] = (catalog.zoneCounts[key] or 0) + 1
                    seen[key] = true
                end
            end
        end
    end
    for _, zone in ipairs(self.indexes.zones) do
        if (catalog.zoneCounts[zone.id] or 0) > 0 then
            catalog.zones[#catalog.zones + 1] = { id=zone.id, name=zone.name, count=catalog.zoneCounts[zone.id] }
        end
    end
    self.catalogs[mode] = catalog
    return catalog
end

function R:GetZones(query)
    local catalog, result = self:GetCatalog(), {}
    local q = self:Normalize(query)
    local all = { id=0, name="All zones", count=#catalog.mobs }
    if q == "" or self:Normalize(all.name):find(q, 1, true) then result[#result + 1] = all end
    for _, zone in ipairs(catalog.zones) do
        if q == "" or self:Normalize(zone.name):find(q, 1, true) or tostring(zone.id) == q then result[#result + 1] = zone end
    end
    return result
end

function R:GetMobs(zoneID, query)
    local q, result = self:Normalize(query), {}
    if not ZoneKey(zoneID) then zoneID = self.db.zoneID or 0 end
    for _, mob in ipairs(self:GetCatalog().mobs) do
        if HasZone(mob, zoneID) and (q == "" or mob._search:find(q, 1, true) or tostring(mob.id) == q) then
            result[#result + 1] = mob
        end
    end
    return result
end

function R:GetSelectedMob()
    local mob = self.db.mobID and self:GetMob(self.db.mobID)
    if mob and HasZone(mob, self.db.zoneID) and #self:GetTables(mob) > 0 then return mob end
end
function R:GetSelectedTable()
    local tables = self:GetTables(self:GetSelectedMob())
    local index = self.Number(self.db.tableIndex) and math.floor(self.db.tableIndex) or 1
    if index < 1 or index > #tables then index = 1 end
    self.db.tableIndex = index
    return tables[index]
end

function R:SetZone(id)
    if not ZoneKey(id) or (id ~= 0 and not self:GetZone(id)) then return false end
    self.db.zoneID, self.db.tableIndex, self.db.openedOnce = id, 1, true
    if not self:GetSelectedMob() then
        local list = self:GetMobs(id, "")
        self.db.mobID = list[1] and list[1].id or nil
    end
    self:RequestRefresh()
    return true
end
function R:SelectMob(id)
    if not self.Number(id) then return false end
    local mob = self:GetMob(id)
    if not mob or #self:GetTables(mob) == 0 then return false end
    if not HasZone(mob, self.db.zoneID) then self.db.zoneID = 0 end
    self.db.mobID, self.db.tableIndex = id, 1
    self:RequestRefresh()
    return true
end
function R:SetTable(index)
    if not self.Number(index) then return false end
    index = math.floor(index)
    if not self:GetTables(self:GetSelectedMob())[index] then return false end
    self.db.tableIndex = index
    self:RequestRefresh()
    return true
end
function R:SetOption(key, value)
    if key ~= "includeReference" or self.IsSecret(value) or type(value) ~= "boolean" then return false end
    self.db.includeReference, self.db.tableIndex = value, 1
    if not self:GetSelectedMob() then self.db.mobID = nil end
    self:RequestRefresh()
    return true
end

function R:UseCurrentZone()
    self:BuildIndexes()
    local ok, mapID = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    local seen = {}
    if ok and self.Number(mapID) then
        for _ = 1, 8 do
            if not self.Number(mapID) or seen[mapID] then break end
            seen[mapID] = true
            local gotInfo, info = self.Call(C_Map and C_Map.GetMapInfo, mapID)
            local publicInfo = gotInfo and self.Table(info)
            local nativeName = publicInfo and self.String(info.name) and self:Normalize(info.name) or nil
            local id = self.indexes.byMap[mapID]
            if id then
                local gotLocale, locale = self.Call(GetLocale)
                local expected = self:GetZone(id)
                -- A known English name mismatch signals a reused map ID.
                local english = gotLocale and self.String(locale) and (locale == "enUS" or locale == "enGB")
                if not english or not nativeName or nativeName == expected._search
                    or self.indexes.byZoneName[nativeName] == id then
                    self:SetZone(id); return true
                end
            end
            if nativeName and self.indexes.byZoneName[nativeName] then
                self:SetZone(self.indexes.byZoneName[nativeName]); return true
            end
            if publicInfo and self.Number(info.parentMapID) then mapID = info.parentMapID else mapID = nil end
        end
    end
    local zoneGetters = { GetRealZoneText, GetZoneText }
    for index = 1, 2 do
        local getter = zoneGetters[index]
        local valid, name = self.Call(getter)
        if valid and self.String(name) then
            local id = self.indexes.byZoneName[self:Normalize(name)]
            if id then self:SetZone(id); return true end
        end
    end
    return false, "No reliable mapping is available for your current zone. Select a zone manually."
end

function R:SelectTarget()
    local ok, guid = self.Call(UnitGUID, "target")
    if not ok or not self.String(guid) then return false, "No readable creature is selected." end
    local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return false, "Select an NPC or creature." end
    if self:SelectMob(tonumber(id)) then return true end
    return false, "This target is not in the enabled sources. Search by name or enable the Classic reference."
end

local function ParseNumber(text)
    local n = text ~= "" and tonumber(text) or nil
    return R.Number(n) and n or nil
end
function R:DecodeRows(tbl)
    if not tbl then return {} end
    if tbl.rows then return tbl.rows end
    if self.decoded[tbl] then return self.decoded[tbl] end
    local rows = {}
    if type(tbl.packed) == "string" then
        for raw in tbl.packed:gmatch("[^;]+") do
            local fields = {}
            for field in (raw .. "|"):gmatch("(.-)|") do fields[#fields + 1] = field end
            local id = ParseNumber(fields[1] or "")
            if id and id > 0 and id == math.floor(id) then
                rows[#rows + 1] = { itemID=id, percent=ParseNumber(fields[2] or ""),
                    quest=fields[3] == "1", conditionID=ParseNumber(fields[4] or ""),
                    occurrences=ParseNumber(fields[5] or ""), sampleSize=ParseNumber(fields[6] or ""),
                    quantityMin=ParseNumber(fields[7] or ""), quantityMax=ParseNumber(fields[8] or "") }
            end
        end
    end
    self.decoded[tbl] = rows
    self.decodedOrder[#self.decodedOrder + 1] = tbl
    if #self.decodedOrder > 6 then self.decoded[table.remove(self.decodedOrder, 1)] = nil end
    return rows
end

function R:GetChance(row, tbl)
    if not row then return nil end
    local n, count = row.sampleSize or (tbl and tbl.sampleSize), row.occurrences
    if (row.rateKind or (tbl and tbl.rateKind)) == "observed" then
        if self.Number(n) and n > 0 and self.Number(count) and count >= 0 and count <= n then
            return count / n * 100
        end
        return nil -- Never promote a supplied number without its observation denominator.
    end
    local chance = row.percent
    if self.Number(chance) and chance >= 0 and chance <= 100 then return chance end
end
function R:FormatChance(row, tbl)
    local chance = self:GetChance(row, tbl)
    if tbl and tbl.provenance == "local_observed" then return tostring(row.occurrences or 0) .. " seen" end
    if chance == nil then return "—" end
    local text
    if chance > 0 and chance < 0.01 then text = "<0.01%"
    else text = (string.format("%.2f", chance):gsub("%.00$", "")) .. "%" end
    if row.quest or (row.conditionID and row.conditionID ~= 0) then text = text .. "*" end
    return text
end

function R:GetLootRows(tbl, query, sort)
    local q = self:Normalize(query)
    sort = sort == "name" and "name" or sort == "quality" and "quality" or "chance"
    if not self.rowViews or self.rowViews.tbl ~= tbl then self.rowViews = { tbl=tbl, sorted={} } end
    local sorted = self.rowViews.sorted[sort]
    if not sorted then
      sorted = {}
      for _, row in ipairs(self:DecodeRows(tbl)) do
        local item = self.Data.items[row.itemID] or {}
        local name = row.name or item.name or ("Item " .. tostring(row.itemID))
        if not row._search then row._search = self:Normalize(name) end
        if row._quality == nil then row._quality = row.quality or item.quality or -1 end
        sorted[#sorted + 1] = row
      end
      table.sort(sorted, function(a, b)
        if sort == "chance" or sort == nil then
            local ac, bc = self:GetChance(a, tbl), self:GetChance(b, tbl)
            if ac ~= bc then
                if ac == nil then return false elseif bc == nil then return true else return ac > bc end
            end
        elseif sort == "quality" then
            local aq, bq = a._quality, b._quality
            if aq ~= bq then return aq > bq end
        end
        local an, bn = a._search or "", b._search or ""
        if an ~= bn then return an < bn end
        return a.itemID < b.itemID
      end)
      self.rowViews.sorted[sort] = sorted
    end
    -- Only the selected table has cached sort views. A search is one scan of
    -- already sorted source names; no native calls or full re-sort per keypress.
    if q == "" then return sorted end
    local result = {}
    for _, row in ipairs(sorted) do
        if row._search:find(q, 1, true) or tostring(row.itemID) == q then result[#result + 1] = row end
    end
    return result
end

function R:GetItem(row)
    local id = row.itemID
    local base = self.Data.items[id] or {}
    local cached = self.itemCache[id]
    if cached then return cached end
    local item = { id=id, name=row.name or base.name or ("Item " .. id), quality=row.quality or base.quality or 1,
        icon=row.icon or base.icon or "Interface\\Icons\\INV_Misc_QuestionMark", link="item:" .. id }
    local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
    local result = { self.Call(getter, id) }
    if result[1] and self.String(result[2]) then
        item.name = result[2]
        if self.String(result[3]) then item.link = result[3] end
        if self.Number(result[4]) then item.quality = result[4] end
        if self.Number(result[11]) or self.String(result[11]) then item.icon = result[11] end
        self.itemCache[id] = item
    else
        local gotIcon, icon = self.Call(C_Item and C_Item.GetItemIconByID or GetItemIcon, id)
        if gotIcon and (self.Number(icon) or self.String(icon)) then item.icon = icon end
        if not self.requestedItems[id] and C_Item and C_Item.RequestLoadItemDataByID then
            self.requestedItems[id] = true
            self.Call(C_Item.RequestLoadItemDataByID, id)
        end
    end
    return item
end

local methodNames = { loot="Normal loot", skinning="Skinning", pickpocket="Pickpocket", observed="Observed creature loot" }
function R:GetTableLabel(tbl)
    if not tbl then return "No loot table" end
    if tbl.provenance == "local_observed" then return "Your observed drops" end
    local provenance = tbl.provenance == "classic_reference" and "Classic reference"
        or tbl.provenance == "forever_observed" and "Forever observations" or "Forever source"
    local caption = self.String(tbl.label) and tbl.label ~= "" and self:DisplayText(tbl.label)
        or methodNames[tbl.method] or tbl.method or "Loot"
    local label = provenance .. " · " .. caption
    if tbl.level then label = label .. " · level " .. tostring(tbl.level) end
    return label
end
function R:GetTableSummary(tbl)
    if not tbl then return "No data for this selection." end
    local total = #self:DecodeRows(tbl)
    if tbl.provenance == "local_observed" then return total .. " confirmed item types · your own observations · no drop rate inferred." end
    if tbl.provenance == "classic_reference" then
        return total .. " items · Classic source; drops and rates may differ in Forever. * = conditional."
    elseif tbl.rateKind == "observed" then
        return total .. " observed items · rate per opened loot window; not a complete or official drop rate."
    end
    return total .. " source items · unknown rates remain blank; Forever completeness is not guaranteed."
end
function R:GetChanceDetails(row, tbl)
    if not row or not tbl then return "No drop-rate data." end
    local lines = { self:GetTableLabel(tbl) }
    if tbl.provenance == "local_observed" then
        lines[#lines + 1] = string.format("Seen on %d different creature sources; at least %d item units observed.", row.occurrences or 0, row.quantitySeen or 0)
        lines[#lines + 1] = "Only confirmed positive sightings are stored. Unseen items are not excluded and no kill-based rate is inferred."
    end
    local n = row.sampleSize or tbl.sampleSize
    if tbl.rateKind == "observed" or row.rateKind == "observed" then
        if self.Number(n) and self.Number(row.occurrences) and n > 0 then
            lines[#lines + 1] = string.format("Observed in %d of %d loot windows: %s.", row.occurrences, n, self:FormatChance(row, tbl))
            lines[#lines + 1] = "This does not count every kill or guarantee a drop rate per kill."
            if n < 100 then lines[#lines + 1] = "Small sample: the rate may change significantly." end
        end
    elseif self:GetChance(row, tbl) ~= nil then
        local precise = string.format("%.8g", self:GetChance(row, tbl)) .. "%"
        lines[#lines + 1] = (tbl.provenance == "classic_reference" and "Source base rate: " or "Source rate: ") .. precise
        lines[#lines + 1] = tbl.provenance == "classic_reference"
            and "Rate from the Classic reference; not confirmed for Forever."
            or "Rate from the named Forever source; not an official server guarantee."
    end
    if self:GetChance(row, tbl) == nil then lines[#lines + 1] = "No reliable overall rate is available; unknown does not mean 0%." end
    if row.quest then lines[#lines + 1] = "Quest drop: availability depends on your quest status." end
    if row.conditionID and row.conditionID ~= 0 then lines[#lines + 1] = "Conditional source entry (condition " .. row.conditionID .. "); not an unconditional drop rate." end
    if row.quantityMin and row.quantityMax then
        lines[#lines + 1] = "Source quantity: " .. row.quantityMin .. "–" .. row.quantityMax .. "."
    end
    if row.note then lines[#lines + 1] = self:DisplayText(row.note) end
    if tbl.note then lines[#lines + 1] = self:DisplayText(tbl.note) end
    local source = self:GetSourceInfo(tbl)
    if source.name then lines[#lines + 1] = "Source: " .. self:DisplayText(source.name) end
    if tbl.date or source.date then lines[#lines + 1] = "Source date: " .. (tbl.date or source.date) end
    return table.concat(lines, "\n")
end
function R:GetSourceURL(tbl)
    if not tbl then return "" end
    if tbl.provenance == "local_observed" then return "" end
    local source = self:GetSourceInfo(tbl)
    return tbl.url or source.url or "See SOURCES_NL.txt"
end
function R:GetCoverageText()
    local c = self:GetCatalog()
    return #c.mobs .. " creatures · " .. #c.zones .. " zones · sources + your observations · "
        .. (self.db.includeReference and "Classic reference included" or "Forever sources only")
end

function R:GetDatabaseStatus()
    local snapshot = self.Data.remoteSnapshot
    if not self.Table(snapshot) or not self.String(snapshot.dataAsOf) then
        return "Everloot: bundled snapshot. Run the external database updater to refresh it."
    end
    local stamp = snapshot.dataAsOf:sub(1, 16):gsub("T", " ")
    return string.format("Everloot · source updated %s UTC · %d creatures · %d observed drop entries.",
        stamp, snapshot.npcCount or 0, snapshot.dropCount or 0)
end

function R:RequestRefresh()
    local browserShown = self.UI and self.UI.frame and self.UI.frame:IsShown()
    local mobLootShown = self.MobLoot and self.MobLoot.frame and self.MobLoot.frame:IsShown()
    if self.refreshPending or not (browserShown or mobLootShown) then return end
    self.refreshPending = true
    local function apply()
        R.refreshPending = nil
        if R.UI and R.UI.frame and R.UI.frame:IsShown() then R.UI:Refresh() end
        if R.MobLoot and R.MobLoot.frame and R.MobLoot.frame:IsShown() then R.MobLoot:RefreshItems() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.04, apply) else apply() end
end

function R:Initialize()
    if self.initialized then return end
    if not self.Table(RicoLootDB) then RicoLootDB = {} end
    self.db = RicoLootDB
    if self.Observations then self.Observations:Initialize() end
    for key, value in pairs(self.defaults) do if self.db[key] == nil then self.db[key] = value end end
    if type(self.db.includeReference) ~= "boolean" then self.db.includeReference = true end
    if not ZoneKey(self.db.zoneID) or (self.db.zoneID ~= 0 and not self:GetZone(self.db.zoneID)) then self.db.zoneID = 0 end
    if not self.Number(self.db.x) then self.db.x = 0 end
    if not self.Number(self.db.y) then self.db.y = 0 end
    if not self.Number(self.db.tableIndex) then self.db.tableIndex = 1 end
    if not self.Number(self.db.mobID) then self.db.mobID = nil end
    if self.Observations then self.Observations:Initialize() end
    if self.Wishlist then self.Wishlist:Initialize() end
    self.initialized = true
end

function R:Command(message)
    self:Initialize()
    local command = self:Normalize(message)
    if command == "wishlist" or command == "favorites" then
        if self.Wishlist then self.Wishlist:Show() end
        return
    elseif command == "status" then
        self:Print("v" .. self.version .. " · " .. self:GetCoverageText())
        self:Print(self:GetDatabaseStatus())
        self:Print("Confirmed creature loot is saved locally. Source rates remain separate from your sightings.")
        return
    elseif command == "database" or command == "db" then
        if self.Database then self.Database:Show(); return end
        self:Print(self:GetDatabaseStatus())
        self:Print("New database files take effect after /reload. Your observed drops remain separate.")
        self:Print("Data from Everloot (https://everloot.app), CC BY-SA 4.0.")
        return
    elseif command == "resetpositie" or command == "position" then
        self.db.x, self.db.y = 0, 0
        if self.UI and self.UI.frame then self.UI.frame:ClearAllPoints(); self.UI.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
        return
    end
    if not self.db.openedOnce then
        self:UseCurrentZone()
        self.db.openedOnce = true
    end
    if command == "target" or command == "doel" then
        local ok, reason = self:SelectTarget()
        if not ok then self:Print(reason) end
        self.UI:Toggle(true)
    elseif command == "zone" then
        local ok, reason = self:UseCurrentZone()
        if not ok then self:Print(reason) end
        self.UI:Toggle(true)
    else self.UI:Toggle() end
end

R.frame = CreateFrame("Frame")
R.frame:RegisterEvent("ADDON_LOADED")
R.frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
R.frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if R.String(arg) and arg == addonName then R:Initialize() end
    elseif R.initialized and R.Number(arg) and R.requestedItems[arg] then
        R.itemCache[arg] = nil
        R:RequestRefresh()
    end
end)
SLASH_RICOLOOT1, SLASH_RICOLOOT2 = "/rl", "/ricoloot"
SlashCmdList.RICOLOOT = function(message) R:Command(message) end
