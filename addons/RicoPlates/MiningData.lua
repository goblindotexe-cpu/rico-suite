-- Mining reference, not a spawn database. Forever observations are recorded separately.
local _, RP = ...
local M = rawget(_G, "RicoMining") or {}
_G.RicoMining, RP.Mining = M, M
M.Data = { skillID = 186, reference = "Classic reference; verify in Forever", ores = {}, byID = {}, nodes = {} }
local D = M.Data
local rows = {
    {2770, "Copper", "Copper Vein", 1, "INV_Ore_Copper_01"},
    {2771, "Tin", "Tin Vein", 65, "INV_Ore_Tin_01"},
    {3340, "Incendicite", "Incendicite Mineral Vein", 65, "INV_Stone_01", true},
    {2775, "Silver", "Silver Vein", 75, "INV_Stone_16"},
    {4278, "Lesser Bloodstone", "Lesser Bloodstone Deposit", 75, "INV_Ore_Bloodstone_01", true},
    {2772, "Iron", "Iron Deposit", 125, "INV_Ore_Iron_01"},
    {2776, "Gold", "Gold Vein", 155, "INV_Ore_Gold_01"},
    {3858, "Mithril", "Mithril Deposit", 175, "INV_Ore_Mithril_02"},
    {7911, "Truesilver", "Truesilver Deposit", 230, "INV_Ore_TrueSilver_01"},
    {11370, "Dark Iron", "Dark Iron Deposit", 230, "INV_Ore_Mithril_01"},
    {10620, "Thorium", "Small Thorium Vein", 245, "INV_Ore_Thorium_02"},
}
for _, row in ipairs(rows) do
    local ore = {id=row[1], name=row[2], nodeName=row[3], requiredSkill=row[4],
        icon="Interface\\Icons\\" .. row[5], reference=true,quest=row[6]==true}
    D.ores[#D.ores + 1], D.byID[ore.id] = ore, ore
    D.nodes[ore.nodeName:lower()] = {oreID=ore.id, requiredSkill=ore.requiredSkill}
end
table.sort(D.ores,function(a,b) if a.requiredSkill~=b.requiredSkill then return a.requiredSkill<b.requiredSkill end return a.name<b.name end)
for name, id in pairs({["Poor Copper Vein"]=2770,["Iron Vein"]=2772,["Dark Iron Vein"]=11370,
    ["Ooze Covered Mithril Deposit"]=3858,["Ooze Covered Silver Vein"]=2775,
    ["Ooze Covered Gold Vein"]=2776,["Ooze Covered Truesilver Deposit"]=7911,
    ["Ooze Covered Thorium Vein"]=10620}) do
    D.nodes[name:lower()] = {oreID=id, requiredSkill=D.byID[id].requiredSkill}
end
D.nodes["rich thorium vein"] = {oreID=10620, requiredSkill=275}
D.nodes["ooze covered rich thorium vein"] = {oreID=10620, requiredSkill=275}
