local _, RP = ...
local embedded = RP.NavigationEmbedded
if not (embedded and embedded.enabled and embedded.loaded) then return end

local nav = embedded.namespace
local MARKER = "Interface\\AddOns\\RicoPlates\\Media\\NavigationMarker.tga"
local MINT = {0.40, 0.94, 0.67}
local INK = {0.90, 0.97, 0.94}
local unpack = unpack or table.unpack

local function SetMarker(texture, size)
    texture:SetTexture(MARKER)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetSize(size, size)
end

local function SetType(text, size, color)
    text:SetFont(RP.Theme.font, size, "OUTLINE")
    text:SetTextColor(unpack(color))
end

local function SkinCompass()
    local compass = ShortestPathForeverCompass
    local theme = RP.Theme
    if not (compass and theme) or compass.ricoSkin then return end

    local face = compass:CreateTexture(nil, "BACKGROUND", nil, -2)
    face:SetPoint("TOPLEFT", 1, -1)
    face:SetPoint("TOPRIGHT", -1, -1)
    face:SetHeight(46)
    face:SetColorTexture(0.026, 0.050, 0.043, 0.90)
    if CreateColor and face.SetGradient then
        face:SetGradient("VERTICAL", CreateColor(0.025, 0.053, 0.043, 0.73), CreateColor(0.014, 0.029, 0.025, 0.96))
    end

    local edge = compass:CreateTexture(nil, "BORDER")
    edge:SetPoint("BOTTOMLEFT", face)
    edge:SetPoint("BOTTOMRIGHT", face)
    edge:SetHeight(1)
    edge:SetColorTexture(0.23, 0.51, 0.40, 0.78)
    if CreateColor and edge.SetGradient then
        edge:SetGradient("HORIZONTAL", CreateColor(0.24, 0.54, 0.42, 0.20), CreateColor(0.33, 0.72, 0.54, 0.75))
    end

    local strip = CreateFrame("Frame", nil, compass)
    strip:SetPoint("TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", -1, -1)
    strip:SetHeight(3)
    strip:EnableMouse(false)
    theme:Liquid(strip, {width=compass:GetWidth() - 2,height=3,compact=true,segments=16,bubbleCount=0,color=MINT})
    compass.ricoSkin = strip

    for _, tick in ipairs(compass.ticks) do
        if tick.major then
            tick:SetColorTexture(0.56, 0.89, 0.75, 1)
            SetType(tick.label, 11, INK)
        else
            tick:SetColorTexture(0.40, 0.66, 0.56, 0.90)
        end
    end
    compass.Center:SetColorTexture(0.62, 1, 0.81, 1)
    compass.Center:SetSize(2, 8)
    SetMarker(compass.Goal, 23)
    compass.Bend:SetVertexColor(0.50, 1, 0.84)
    compass.Next:SetVertexColor(0.45, 0.85, 0.72)
    SetType(compass.Distance, 12, MINT)
    SetType(compass.Time, 10, INK)
end

local function SkinDestination()
    local destination = ShortestPathForeverDestinationPin
    if not (destination and RP.Theme) or destination.ricoSkin then return end
    destination.ricoSkin = true
    SetMarker(destination.Pin, 30)
    SetType(destination.Distance, 13, MINT)
    SetType(destination.Step, 11, INK)
end

local function OwnsRoute()
    return nav.JourneyOwner() == "RicoPlates"
end

local breadcrumbColor = CreateColor(unpack(MINT))
local function TintBreadcrumbs(buffer)
    if not OwnsRoute() then return end
    for index = 1, buffer.n do
        if buffer.dot[index] then buffer.color[index] = breadcrumbColor end
    end
end

-- Reuse the client's floating waypoint position and fade. Ownership follows the
-- embedded guide so a normal quest, corpse or manually tracked pin keeps its art.
local nativeSkin, nativePending
local function RefreshNativeMarker()
    local frame = SuperTrackedFrame
    local tracking = C_SuperTrack and C_SuperTrack.GetHighestPrioritySuperTrackingType
    local waypointType = Enum and Enum.SuperTrackingType and Enum.SuperTrackingType.UserWaypoint
    local active = false
    if frame and frame.Icon and RP.CanUseFrame(frame) and tracking and waypointType and OwnsRoute() then
        local ok, kind = pcall(tracking)
        if ok and RP.Readable(kind) and kind == waypointType then
            local named, title = pcall(nav.JourneyGuide.WaypointNames)
            active = named and RP.Readable(title) and type(title) == "string" and title ~= ""
        end
    end
    if active then
        if not nativeSkin then
            local marker = frame:CreateTexture(nil, "OVERLAY", nil, 2)
            marker:SetPoint("CENTER", frame.Icon, "CENTER")
            SetMarker(marker, 28)
            nativeSkin = {marker=marker,icon=frame.Icon}
        end
        if nativeSkin.alpha == nil then
            nativeSkin.alpha = nativeSkin.icon:GetAlpha()
            nativeSkin.icon:SetAlpha(0)
        end
        nativeSkin.marker:Show()
    elseif nativeSkin and nativeSkin.alpha ~= nil then
        nativeSkin.marker:Hide()
        nativeSkin.icon:SetAlpha(nativeSkin.alpha)
        nativeSkin.alpha = nil
    end
end

local function QueueNativeMarker()
    if nativePending then return end
    nativePending = true
    C_Timer.After(0, function()
        nativePending = nil
        RefreshNativeMarker()
    end)
end

hooksecurefunc(nav, "RefreshCompass", SkinCompass)
hooksecurefunc(nav, "RefreshDestinationPin", SkinDestination)
hooksecurefunc(nav.Strokes, "Minimap", TintBreadcrumbs)
hooksecurefunc(nav, "GuideChanged", QueueNativeMarker)
hooksecurefunc(nav, "JourneyChanged", QueueNativeMarker)

local events = CreateFrame("Frame")
events:RegisterEvent("SUPER_TRACKING_CHANGED")
events:RegisterEvent("USER_WAYPOINT_UPDATED")
events:RegisterEvent("NAVIGATION_FRAME_CREATED")
events:SetScript("OnEvent", QueueNativeMarker)
