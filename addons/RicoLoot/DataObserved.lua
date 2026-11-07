-- The optional local Everloot cache supplies the public observations.
local _, R = ...
local cache = RicoLootEverloot
if cache and cache.ApplyObserved then cache.ApplyObserved(R) end
