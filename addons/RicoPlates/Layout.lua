-- Layout coordinates are UIParent units: x from screen center, y from bottom.
-- Only the ordinary drag anchors are moved; protected unit buttons stay intact.
local _, RP = ...
local L = {}
RP.Layout = L
local WHITE = "Interface\\Buttons\\WHITE8X8"
local abs, min, max, floor = math.abs, math.min, math.max, math.floor

local function Number(value)
    return RP.Readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function Round(value, step)
    return floor(value / step + 0.5) * step
end

function L:ClampPosition(entry, x, y)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local scale = RP.db.unitFrameScale or 1
    local halfW = min(width / 2, (entry.width or 1) * scale / 2)
    local halfH = min(height / 2, (entry.height or 1) * scale / 2)
    local footer = min((entry.extraBottom or 0) * scale, max(0, height - 2 * halfH))
    return max(-width / 2 + halfW, min(width / 2 - halfW, x)), max(halfH + footer, min(height - halfH, y))
end

function L:SnapPosition(entry, x, y)
    if not Number(x) or not Number(y) then return nil end
    local d = RP.db
    local grid = Number(d.layoutGridSize) and max(4, min(32, d.layoutGridSize)) or 8
    local threshold = Number(d.layoutSnapDistance) and max(2, min(24, d.layoutSnapDistance)) or 12
    local snappedX, snappedY = d.layoutGridSnap and Round(x, grid) or x, d.layoutGridSnap and Round(y, grid) or y
    local bestX, bestY = threshold + 0.001, threshold + 0.001
    local function Candidate(candidate, horizontal)
        local distance = abs(candidate - (horizontal and x or y))
        if horizontal and distance < bestX then snappedX, bestX = candidate, distance
        elseif not horizontal and distance < bestY then snappedY, bestY = candidate, distance end
    end
    if d.layoutFrameSnap then
        Candidate(0, true)
        Candidate(UIParent:GetHeight() / 2, false)
        local scale = d.unitFrameScale or 1
        local ownW, ownH = (entry.width or 1) * scale / 2, (entry.height or 1) * scale / 2
        local ownBottom = ownH + (entry.extraBottom or 0) * scale
        for unit, other in pairs(RP.UnitFrames.frames) do
            local pos = d.unitFramePositions[unit]
            if other ~= entry and other.enabled and pos and Number(pos.x) and Number(pos.y) then
                local w, h = (other.width or 1) * scale / 2, (other.height or 1) * scale / 2
                local bottom = h + (other.extraBottom or 0) * scale
                for _, candidate in ipairs({pos.x, pos.x - w + ownW, pos.x + w - ownW,
                    pos.x + w + grid + ownW, pos.x - w - grid - ownW}) do Candidate(candidate, true) end
                for _, candidate in ipairs({pos.y, pos.y - bottom + ownBottom, pos.y + h - ownH,
                    pos.y + h + grid + ownBottom, pos.y - bottom - grid - ownH}) do Candidate(candidate, false) end
            end
        end
    end
    return self:ClampPosition(entry, snappedX, snappedY)
end

function L:UpdateGrid(shown)
    if not shown then if self.grid then self.grid:Hide() end; return end
    if not self.grid then
        self.grid = CreateFrame("Frame", nil, UIParent)
        self.grid:SetAllPoints(UIParent)
        self.grid:SetFrameStrata("BACKGROUND")
        self.grid:EnableMouse(false)
        self.lines = {}
    end
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local step = RP.db.layoutGridSize or 8
    while width / step + height / step > 320 do step = step * 2 end
    local signature = width .. ":" .. height .. ":" .. step
    if self.signature ~= signature then
        self.signature = signature
        local index = 0
        local function Line(x, y, w, h, strong)
            index = index + 1
            local t = self.lines[index]
            if not t then t = self.grid:CreateTexture(nil, "BACKGROUND"); t:SetTexture(WHITE); self.lines[index] = t end
            t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", self.grid, "BOTTOMLEFT", x, y)
            t:SetSize(w, h); t:SetVertexColor(0.29, 0.72, 0.49, strong and 0.24 or 0.055); t:Show()
        end
        local center = width / 2
        for x = center % step, width, step do Line(x, 0, 1, height, abs(x - center) < 0.1) end
        for y = 0, height, step do Line(0, y, width, 1, abs(y - height / 2) < step / 2) end
        for i = index + 1, #self.lines do self.lines[i]:Hide() end
    end
    self.grid:Show()
end
