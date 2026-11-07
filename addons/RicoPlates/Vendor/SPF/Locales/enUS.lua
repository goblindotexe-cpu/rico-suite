-- Generated embedded SPF chunk; upstream source and licence retained.
local hostName, host = ...
local embedded = host.NavigationEmbedded
if embedded and embedded.enabled then
    (function(...)
---@class SPFNamespace
local ns = select(2, ...)

-- English phrases are the keys, so a phrase with no translation reads as English.
---@type table<string, string>
local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L = L

    end)(hostName, embedded.namespace)
end
