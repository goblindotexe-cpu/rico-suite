local _, RP = ...

-- At the engine's outermost zoom, show a separate crop of the outdoor world map.
-- Its cartography is north-up and never mixes map artwork with native blip positions.
local Overview = { tiles = {}, overlays = {} }
RP.MinimapOverview = Overview

local ZOOM_RATIO = 2.2
local TILE_LIMIT = 64

local function Read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, first, second = pcall(fn, ...)
    if ok then return first, second end
end

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

local function Positive(value)
    return Number(value) and value > 0
end

local function Table(value)
    return Public(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function Position(map)
    local point = Read(C_Map.GetPlayerMapPosition, map, "player")
    if not Table(point) then return end
    if Number(point.x) and Number(point.y) and point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1 then
        return point.x, point.y
    end
end

local function OutdoorMap()
    if not C_Map then return end
    local inside = Read(IsIndoors)
    local instance = Read(IsInInstance)
    if not Public(inside) or not Public(instance) or inside or instance then return end
    local map = Read(C_Map.GetBestMapForUnit, "player")
    local types = Enum and Enum.UIMapType
    if types and types.Zone then
        -- Small outdoor areas can have a child UI map; show the surrounding zone.
        for _ = 1, 4 do
            if not Positive(map) then return end
            local info = Read(C_Map.GetMapInfo, map)
            if not Table(info) or not Number(info.mapType) then return end
            if info.mapType == types.Zone then return map end
            if info.mapType ~= types.Micro then return end
            map = info.parentMapID
        end
    elseif Positive(map) then
        return map
    end
end

function Overview:MapArt(map)
    local artID = Read(C_Map.GetMapArtID, map)
    if not Public(artID) then return end
    if self.art and self.art.map == map and self.art.id == artID then return self.art end
    local layers = Read(C_Map.GetMapArtLayers, map)
    local layer = Table(layers) and layers[1]
    local worldWidth, worldHeight = Read(C_Map.GetMapWorldSize, map)
    if not Table(layer) or not Positive(worldWidth) or not Positive(worldHeight)
        or not Positive(layer.layerWidth) or not Positive(layer.layerHeight)
        or not Positive(layer.tileWidth) or not Positive(layer.tileHeight) then return end
    local files = Read(C_Map.GetMapArtLayerTextures, map, 1)
    if not Table(files) or not Positive(files[1]) then return end

    local base = { x = 0, y = 0, width = layer.layerWidth, height = layer.layerHeight, files = files }
    local explored = Read(C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures, map)
    self.art = { map = map, id = artID, base = base, explored = Table(explored) and explored or {},
        worldWidth = worldWidth, worldHeight = worldHeight, tileWidth = layer.tileWidth, tileHeight = layer.tileHeight }
    return self.art
end

local function CropOrigin(center, window, full)
    if window >= full then return (full - window) / 2 end
    return math.max(0, math.min(center - window / 2, full - window))
end

local function PaddedSize(size)
    local padded = 16
    while padded < size do padded = padded * 2 end
    return padded
end

local function PaintGrid(frame, pool, used, art, view, grid, explored)
    local tw, th = art.tileWidth, art.tileHeight
    local width, height, x, y, files
    if explored then
        width, height, x, y, files = grid.textureWidth, grid.textureHeight, grid.offsetX, grid.offsetY, grid.fileDataIDs
    else
        width, height, x, y, files = grid.width, grid.height, grid.x, grid.y, grid.files
    end
    if not Positive(width) or not Positive(height) or not Number(x) or not Number(y) or not Table(files) then return used end
    local columns, rows = math.ceil(width / tw), math.ceil(height / th)
    local firstColumn = math.max(0, math.floor((view.left - x) / tw))
    local lastColumn = math.min(columns - 1, math.ceil((view.right - x) / tw) - 1)
    local firstRow = math.max(0, math.floor((view.top - y) / th))
    local lastRow = math.min(rows - 1, math.ceil((view.bottom - y) / th) - 1)
    for row = firstRow, lastRow do
        for col = firstColumn, lastColumn do
            if used >= TILE_LIMIT then return used end
            local id = files[row * columns + col + 1]
            local tileX, tileY = x + col * tw, y + row * th
            local tileWidth, tileHeight = math.min(tw, x + width - tileX), math.min(th, y + height - tileY)
            local left, right = math.max(view.left, tileX), math.min(view.right, tileX + tileWidth)
            local top, bottom = math.max(view.top, tileY), math.min(view.bottom, tileY + tileHeight)
            if Positive(id) and left < right and top < bottom then
                used = used + 1
                local texture = pool[used]
                if not texture then
                    texture = frame:CreateTexture(nil, explored and "ARTWORK" or "BORDER")
                    pool[used] = texture
                end
                if id ~= texture.ricoFile then
                    texture:SetTexture(id, nil, nil, "TRILINEAR")
                    texture.ricoFile = id
                end
                if explored then
                    local onTop = Public(grid.isDrawOnTopLayer) and grid.isDrawOnTopLayer
                    texture:SetDrawLayer("ARTWORK", onTop and 1 or 0)
                end
                local fileWidth = explored and PaddedSize(tileWidth) or tw
                local fileHeight = explored and PaddedSize(tileHeight) or th
                texture:SetTexCoord((left - tileX) / fileWidth, (right - tileX) / fileWidth,
                    (top - tileY) / fileHeight, (bottom - tileY) / fileHeight)
                texture:ClearAllPoints()
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", (left - view.left) * view.scaleX, -(top - view.top) * view.scaleY)
                texture:SetSize((right - left) * view.scaleX, (bottom - top) * view.scaleY)
                texture:Show()
            end
        end
    end
    return used
end

local function HideUnused(pool, used)
    for index = used + 1, #pool do pool[index]:Hide() end
end

local function Marker(frame, size, level, r, g, b)
    local texture = frame:CreateTexture(nil, "OVERLAY", nil, level)
    texture:SetColorTexture(r, g, b, 1)
    texture:SetSize(size, size)
    return texture
end

function Overview:Create(minimap)
    local frame = CreateFrame("Frame", nil, minimap)
    frame:SetAllPoints(minimap)
    frame:SetFrameLevel(minimap:GetFrameLevel() + 12)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    if frame.SetPropagateMouseClicks then frame:SetPropagateMouseClicks(false) end
    if frame.SetPropagateMouseMotion then frame:SetPropagateMouseMotion(false) end
    frame:SetScript("OnMouseWheel", function(_, delta)
        if self.wheelHandler then self.wheelHandler(delta) end
    end)
    frame:RegisterEvent("MAP_EXPLORATION_UPDATED")
    frame:SetScript("OnEvent", function() self.art = nil end)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0.04, 0.06, 0.055, 1)
    frame.marker = Marker(frame, 11, 1, 0.015, 0.035, 0.03)
    local outline = Marker(frame, 7, 2, 0.92, 1, 0.92)
    outline:SetPoint("CENTER", frame.marker, "CENTER")
    local center = Marker(frame, 3, 3, 0.10, 0.55, 0.31)
    center:SetPoint("CENTER", frame.marker, "CENTER")

    local caption = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 9, 7)
    caption:SetTextColor(0.80, 1, 0.89)
    caption:SetShadowColor(0, 0, 0, 1)
    caption:SetShadowOffset(1, -1)
    caption:SetText("AREA OVERVIEW")
    local backing = frame:CreateTexture(nil, "OVERLAY", nil, 0)
    backing:SetPoint("TOPLEFT", caption, "TOPLEFT", -5, 3)
    backing:SetPoint("BOTTOMRIGHT", caption, "BOTTOMRIGHT", 5, -3)
    backing:SetColorTexture(0.035, 0.07, 0.055, 0.94)
    frame:Hide()
    self.frame = frame
end

function Overview:Draw()
    local frame = self.frame
    local map = OutdoorMap()
    local x, y
    if map then x, y = Position(map) end
    if not x then return false end
    local art = self:MapArt(map)
    local radius = Read(C_Minimap and C_Minimap.GetViewRadius)
    local minimap = frame:GetParent()
    local width, height = minimap:GetWidth(), minimap:GetHeight()
    if not art or not Positive(radius) or not Positive(width) or not Positive(height) then return false end
    local last = self.lastView
    if last and last.art == art and last.x == x and last.y == y and last.radius == radius
        and last.width == width and last.height == height then return true end

    local base = art.base
    local visibleYards = radius * 2 * ZOOM_RATIO
    local spanX = base.width * visibleYards / art.worldWidth
    local spanY = base.height * visibleYards * height / (art.worldHeight * width)
    local markerX, markerY = x * base.width, y * base.height
    local left, top = CropOrigin(markerX, spanX, base.width), CropOrigin(markerY, spanY, base.height)
    local view = { left = left, top = top, right = left + spanX, bottom = top + spanY,
        scaleX = width / spanX, scaleY = height / spanY }
    local tiles = PaintGrid(frame, self.tiles, 0, art, view, base, false)
    HideUnused(self.tiles, tiles)
    if tiles == 0 then return false end
    local used = 0
    for _, overlay in ipairs(art.explored) do
        if used >= TILE_LIMIT then break end
        if Table(overlay) and Public(overlay.isShownByMouseOver) and not overlay.isShownByMouseOver then
            used = PaintGrid(frame, self.overlays, used, art, view, overlay, true)
        end
    end
    HideUnused(self.overlays, used)
    frame.marker:ClearAllPoints()
    local screenX = math.max(6, math.min(width - 6, (markerX - left) * view.scaleX))
    local screenY = math.max(6, math.min(height - 6, (markerY - top) * view.scaleY))
    frame.marker:SetPoint("CENTER", frame, "TOPLEFT", screenX, -screenY)
    self.lastView = { art = art, x = x, y = y, radius = radius, width = width, height = height }
    return true
end

function Overview:SetWheelHandler(handler)
    self.wheelHandler = handler
end

function Overview:Show(minimap)
    if not minimap or not C_Map or not C_Minimap or not OutdoorMap() then return false end
    if not self.frame then self:Create(minimap) end
    if not self:Draw() then return false end
    self.frame:Show()
    return true
end

function Overview:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

function Overview:Hide()
    if self.frame then self.frame:Hide() end
end

function Overview:Refresh()
    if not self:IsShown() then return false end
    if self:Draw() then return true end
    self:Hide()
    return false
end
