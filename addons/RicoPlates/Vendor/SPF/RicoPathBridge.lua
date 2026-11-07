-- Generated embedded SPF chunk; upstream source and licence retained.
local hostName, host = ...
local embedded = host.NavigationEmbedded
if embedded and embedded.enabled then
    (function(...)
-- RicoPlates compatibility bridge for Shortest Path Forever v1.22.38.
-- GPL-3.0-or-later. Rico quest/mining journeys suppress unverified walks.
-- The original dependency archive, checksums and this patch are documented in
-- RICO-INTEGRATION.md. No game input, movement automation or network calls.
local _, ns = ...
local OWNERS = { RicoPlates=true, RicoMining=true }
local B = { version = 1, minor = 2, providerVersion = "v1.22.38" }
ShortestPathForever.RicoRoutes = B

function B.CanStart(owner)
    if not OWNERS[owner] then return false end
    if ns.Corpse and ns.Corpse.Active and ns.Corpse.Active() then return false end
    local current = ns.JourneyOwner and ns.JourneyOwner()
    if current ~= nil and current ~= owner then return false end
    return current == owner or not (ns.HasJourney and ns.HasJourney())
end

local function Number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Text(value, limit)
    if not Public(value) or type(value) ~= "string" then return nil end
    -- Plain local diagnostics only: no stacks, rich-text links or texture tags.
    return value:gsub("[%c|]", " "):sub(1, limit)
end
local function Ours(owner)
    local current = ns.JourneyOwner and ns.JourneyOwner()
    return OWNERS[current] == true and (owner == nil or current == owner)
        and not (ns.Corpse and ns.Corpse.Active and ns.Corpse.Active())
end

local function Verified(leg)
    if type(leg) ~= "table" or leg.mode ~= "walk" or leg.measured ~= true
        or leg.walkDrawn ~= true or leg.walkError ~= nil then return false end
    local points = leg.walkPoints
    if type(points) ~= "table" or #points < 2 then return false end
    for _, point in ipairs(points) do
        if type(point) ~= "table" or not Number(point.map) or not Number(point.x) or not Number(point.y) then return false end
    end
    return true
end

function ns.RicoRouteBlocked()
    if not Ours() then return false end
    local plan, index = ns.JourneyPlan()
    local leg = plan and plan.legs and plan.legs[index]
    return not leg or (leg.mode == "walk" and not Verified(leg))
end

-- Keep the upstream painter and its pools; omit sketches or failed walking
-- searches instead of converting them into a straight, supposedly usable road.
local paint = ns.SetJourneyRoute
ns.SetJourneyRoute = function(destination, plan)
    if not Ours() or type(plan) ~= "table" or type(plan.legs) ~= "table" then return paint(destination, plan) end
    local verified = { legs = {} }
    for key, value in pairs(plan) do if key ~= "legs" then verified[key] = value end end
    for _, leg in ipairs(plan.legs) do
        if leg.mode ~= "walk" or Verified(leg) then verified.legs[#verified.legs + 1] = leg end
    end
    return paint(destination, verified)
end

-- This is the common handoff to both the screen arrow and native waypoint.
-- Pause retains ownership and the goal; the next verified To resumes normally.
local guideTo = ns.JourneyGuide.To
ns.JourneyGuide.To = function(node, points, goal, leg)
    if Ours() and ((leg and leg.mode == "walk" and not Verified(leg)) or (not leg and ns.RicoRouteBlocked())) then
        return ns.JourneyGuide.Pause()
    end
    return guideTo(node, points, goal, leg)
end

local pinWanted = ns.DestinationPinWanted
ns.DestinationPinWanted = function()
    if ns.RicoRouteBlocked() then return false end
    return pinWanted()
end

-- A public, bounded snapshot for Rico's Details panel. Do not expose coordinates,
-- saved character data or stacks, and never read restricted position values.
function B.GetDiagnostics()
    local db = Public(ns.db) and type(ns.db) == "table" and ns.db or nil
    local diagnostics = {
        providerVersion = B.providerVersion,
        initialized = db ~= nil and Public(ns.charDB) and type(ns.charDB) == "table",
        journeyEnabled = db ~= nil and Public(db.journey) and db.journey == true,
        arrowEnabled = db ~= nil and Public(db.arrow) and db.arrow == true,
        mapRoutesEnabled = db ~= nil and Public(db.mapRoutes) and db.mapRoutes == true,
        positionAvailable = false, terrainAvailable = false, combat = false,
        caughtErrorCount = 0,
    }
    if type(InCombatLockdown) == "function" then
        local ok, combat = pcall(InCombatLockdown)
        diagnostics.combat = ok and Public(combat) and combat == true
    end
    if type(ns.JourneyPosition) == "function" then
        local ok, x, y, _, map = pcall(ns.JourneyPosition)
        if ok and Number(x) and Number(y) and Number(map) then
            diagnostics.positionAvailable = true
            if ns.Path and type(ns.Path.HasData) == "function" then
                local found, available = pcall(ns.Path.HasData, map)
                diagnostics.terrainAvailable = found and Public(available) and available == true
            end
        end
    end
    if type(ns.CaughtErrors) == "function" then
        local ok, errors = pcall(ns.CaughtErrors)
        if ok and Public(errors) and type(errors) == "table" then
            -- The provider keeps at most five records, in oldest-first order.
            for index = 1, 5 do
                local entry = errors[index]
                if Public(entry) and type(entry) == "table" then
                    diagnostics.caughtErrorCount = diagnostics.caughtErrorCount + 1
                    diagnostics.lastErrorLabel = Text(entry.label, 80)
                    diagnostics.lastErrorMessage = Text(entry.message, 300)
                end
            end
        end
    end
    return diagnostics
end

local FAILURES = {
    nodata = "No walking terrain data is available for this area.",
    outside = "The destination lies outside the navigator's walking terrain coverage.",
    offmesh = "Your position or destination could not be matched to walkable terrain.",
    unreachable = "The navigator found no connected walking path to this destination.",
    error = "Walking route calculation failed. Open Details to view the navigator error.",
    no_geometry = "The walking search finished without a usable route. Try another destination.",
    no_plan = "The navigator could not plan a route from here. Try another destination.",
}
local function Failure(reason)
    return FAILURES[reason] or "No verified walking route is available from here."
end

function B.GetStatus(owner)
    if not OWNERS[owner] then return {ready=false, state="idle", verified=false, message="This bridge supports Rico quest and mining routes."} end
    if not Ours(owner) then return {ready=true, state="idle", verified=false, message="No route owned by this Rico module is active."} end
    local plan, index = ns.JourneyPlan()
    local pending, _, problem = ns.JourneyStatus()
    if not plan or not plan.legs then
        local reason = problem or (pending == false and "no_plan" or nil)
        return {ready=true, state=reason and "no_path" or "searching", verified=false, searchPending=pending == true,
            message=reason and Failure(reason) or "Finding a terrain-checked route…", reason=reason}
    end
    local leg = plan.legs[index]
    if not leg then
        return {ready=true, state=problem and "no_path" or "searching", verified=false, searchPending=pending == true,
            reason=problem, message=problem and Failure(problem) or "Preparing the next route step…"}
    end
    if leg.mode == "walk" then
        if Verified(leg) then
            return {ready=true, state="active", verified=true, mode="walk", message="Following a terrain-checked walking route."}
        end
        -- A failed endpoint/cost search can leave a preview plan with no
        -- leg.walkError. Report that failure instead of 'searching' forever.
        local reason = leg.walkError or problem or (pending == false and not leg.walkDeferred and "no_geometry" or nil)
        return {ready=true, state=reason and "no_path" or "searching", verified=false, mode="walk", reason=reason,
            searchPending=pending == true, message=reason and Failure(reason)
                or "Checking walkable terrain before showing this route…"}
    end
    return {ready=true, state="active", verified=true, mode=leg.mode,
        message="Follow the marked travel step; walking directions appear after terrain verification."}
end

    end)(hostName, embedded.namespace)
end
if embedded and embedded.enabled and ShortestPathForever and ShortestPathForever.API and ShortestPathForever.RicoRoutes then
    ShortestPathForever.RicoEmbedded = { host=hostName, version=embedded.version }
    embedded.loaded = true
end
