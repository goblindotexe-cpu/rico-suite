local _, RP = ...
local Glow = {}
RP.QuestTrackerGlow = Glow

local PATH = RP.media .. "QuestTrackerPromptSmoke.tga"
local unpack = unpack or table.unpack

-- Same smoke texture and layer tints as the fishing key. Offset the clouds
-- under each corner so different portions of the wisps emerge along the edges.
local clouds = {
    { "TOPLEFT",      1, -1, 112,  96, 11, 11 },
    { "TOPRIGHT",    -1, -1,  99,  88,  9, 10 },
    { "BOTTOMLEFT",   1,  1, 100,  97, 13,  9 },
    { "BOTTOMRIGHT", -1,  1, 108, 101, 12, 13 },
}

local function Texture(frame, sublevel, blend, r, g, b, alpha)
    local region = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    region:SetTexture(PATH)
    region:SetBlendMode(blend)
    region:SetVertexColor(r, g, b, alpha)
    region:Hide()
    return region
end

local function AddPart(halo, cloud, left, right, top, bottom)
    local u1, u2 = (left - cloud.left) / cloud.width, (right - cloud.left) / cloud.width
    local v1, v2 = (cloud.top - top) / cloud.height, (cloud.top - bottom) / cloud.height
    if cloud.mirror then u1, u2 = 1 - u1, 1 - u2 end

    local smoke = Texture(halo.frame, -2, "BLEND", 0.54, 0.70, 0.62, 0.40)
    local light = Texture(halo.frame, -1, "ADD", 0.31, 1, 0.62, 1)
    smoke:SetTexCoord(u1, u2, v1, v2)
    light:SetTexCoord(u1, u2, v1, v2)
    light:SetAllPoints(smoke)
    halo.parts[#halo.parts + 1] = {
        anchor = cloud.anchor, below = cloud.below, smoke = smoke, light = light,
        left = left, right = right, top = top, bottom = bottom,
    }
end

local function AddCloud(halo, anchor, xDirection, yDirection, width, height, insetX, insetY)
    local x, y = xDirection * insetX, yDirection * insetY
    local cloud = {
        anchor = anchor, below = yDirection > 0, mirror = xDirection < 0,
        width = width, height = height, left = x - width / 2, top = y + height / 2,
    }
    local right, bottom = x + width / 2, y - height / 2
    local sideLeft = xDirection > 0 and cloud.left or 0
    local sideRight = xDirection > 0 and 0 or right
    -- Crop each cloud at the panel corner so even translucent panels keep
    -- their contents clear. The two pieces have no overlapping pixels.
    if cloud.below then
        AddPart(halo, cloud, cloud.left, right, 0, bottom)
        AddPart(halo, cloud, sideLeft, sideRight, cloud.top, 0)
    else
        AddPart(halo, cloud, cloud.left, right, cloud.top, 0)
        AddPart(halo, cloud, sideLeft, sideRight, 0, bottom)
    end
end

local function Update(halo)
    local shown = halo.strength > 0 and not halo.suppressed
    for _, part in ipairs(halo.parts) do
        part.smoke:SetAlpha(halo.strength)
        part.light:SetAlpha(halo.strength * 0.55)
        part.smoke:SetShown(shown)
        part.light:SetShown(shown)
    end
end

local function SetStrength(halo, strength)
    if halo.strength == strength then return end
    halo.strength = strength
    Update(halo)
end

local function SetSuppressed(halo, suppressed)
    if halo.suppressed == suppressed then return end
    halo.suppressed = suppressed
    Update(halo)
end

local function AnchorParts(halo)
    for _, part in ipairs(halo.parts) do
        local frame = part.below and halo.bottomFrame or halo.frame
        part.smoke:ClearAllPoints()
        part.smoke:SetPoint("TOPLEFT", frame, part.anchor, part.left, part.top)
        part.smoke:SetPoint("BOTTOMRIGHT", frame, part.anchor, part.right, part.bottom)
    end
end

local function SetBottomFrame(halo, bottomFrame)
    if halo.bottomFrame == bottomFrame then return end
    halo.bottomFrame = bottomFrame
    AnchorParts(halo)
end

function Glow:Create(frame)
    local halo = { frame = frame, parts = {}, strength = 0, suppressed = false,
        SetStrength = SetStrength, SetSuppressed = SetSuppressed, SetBottomFrame = SetBottomFrame }
    for _, cloud in ipairs(clouds) do AddCloud(halo, unpack(cloud)) end
    AnchorParts(halo)
    return halo
end
