-- The optional local Everloot cache supplies status for this installation.
local _, R = ...
R.Data.syncStatus = { schema = 1, state = "idle" }
local cache = RicoLootEverloot
if cache and cache.ApplyStatus then cache.ApplyStatus(R) end
