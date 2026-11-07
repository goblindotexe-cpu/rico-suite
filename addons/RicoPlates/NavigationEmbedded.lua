-- A self-contained fallback loaded through the existing RicoPlates TOC.
-- GPL-3.0-or-later; SPF upstream credits and licence are in Vendor/SPF.
local hostName, RP = ...
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Existing()
    local provider = rawget(_G, "ShortestPathForever")
    if Public(provider) and type(provider) == "table" then return true end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if type(loaded) == "function" then
        local ok, loading, ready = pcall(loaded, "ShortestPathForever")
        if ok and ((Public(loading) and loading == true) or (Public(ready) and ready == true)) then return true end
    end
    return false
end
local embedded = { enabled=not Existing(), namespace={}, version="v1.22.38", host=hostName }
RP.NavigationEmbedded = embedded
local metadata = {
    Version="v1.22.38", Title="Shortest Path Forever (Rico embedded)",
    ["X-Website"]="https://github.com/cjber/shortest-path-forever",
    ["X-License"]="GPL-3.0-or-later",
}
function embedded.namespace.EmbeddedMetadata(field) return metadata[field] end
