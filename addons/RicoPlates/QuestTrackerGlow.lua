local _, RP = ...
local Glow = {}
RP.QuestTrackerGlow = Glow

local RADIUS = 10
local FIRST_TEXEL = 0.5 / 32
local PATH = RP.media .. "QuestTrackerGlow.tga"
local unpack = unpack or table.unpack

-- Edges sample an axis of the same radial texture used for the corners.
-- The edge and corner falloff therefore match at every join.
local edges = {
    { "TOPLEFT", 0, RADIUS, "TOPRIGHT", 0, 0, FIRST_TEXEL, FIRST_TEXEL, 1, 0 },
    { "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", 0, -RADIUS, FIRST_TEXEL, FIRST_TEXEL, 0, 1 },
    { "TOPLEFT", -RADIUS, 0, "BOTTOMLEFT", 0, 0, 1, 0, FIRST_TEXEL, FIRST_TEXEL },
    { "TOPRIGHT", 0, 0, "BOTTOMRIGHT", RADIUS, 0, 0, 1, FIRST_TEXEL, FIRST_TEXEL },
}
local corners = {
    { "BOTTOMRIGHT", "TOPLEFT", 1, 0, 1, 0 },
    { "BOTTOMLEFT", "TOPRIGHT", 0, 1, 1, 0 },
    { "TOPRIGHT", "BOTTOMLEFT", 1, 0, 0, 1 },
    { "TOPLEFT", "BOTTOMRIGHT", 0, 1, 0, 1 },
}
local joinedSides = { "TOP", "BOTTOM", false, false, "TOP", "TOP", "BOTTOM", "BOTTOM" }

local function AddTexture(frame, regions, left, right, top, bottom)
    local texture = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    texture:SetTexture(PATH)
    texture:SetTexCoord(left, right, top, bottom)
    texture:SetBlendMode("ADD")
    texture:SetVertexColor(0.50, 0.88, 0.70)
    texture:Hide()
    regions[#regions + 1] = texture
    return texture
end

local function Update(halo)
    local alpha = halo.strength * 0.62
    for index, texture in ipairs(halo.regions) do
        texture:SetAlpha(alpha)
        texture:SetShown(alpha > 0 and joinedSides[index] ~= halo.joinedEdge)
    end
end

local function SetStrength(halo, strength)
    if halo.strength == strength then return end
    halo.strength = strength
    Update(halo)
end

local function SetJoinedEdge(halo, edge)
    if halo.joinedEdge == edge then return end
    halo.joinedEdge = edge
    Update(halo)
end

function Glow:Create(frame)
    local halo = { regions = {}, strength = 0, SetStrength = SetStrength, SetJoinedEdge = SetJoinedEdge }
    for _, edge in ipairs(edges) do
        local a, x1, y1, b, x2, y2, left, right, top, bottom = unpack(edge)
        local texture = AddTexture(frame, halo.regions, left, right, top, bottom)
        texture:SetPoint("TOPLEFT", frame, a, x1, y1)
        texture:SetPoint("BOTTOMRIGHT", frame, b, x2, y2)
    end
    for _, corner in ipairs(corners) do
        local point, anchor, left, right, top, bottom = unpack(corner)
        local texture = AddTexture(frame, halo.regions, left, right, top, bottom)
        texture:SetSize(RADIUS, RADIUS)
        texture:SetPoint(point, frame, anchor)
    end
    return halo
end
