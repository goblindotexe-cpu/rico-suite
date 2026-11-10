-- Fixed UI unit frames. Secure wrappers own clicks and unit visibility; all
-- changing bars, auras and portraits are ordinary children. The optional loot
-- information button consumes only its own click, without a secure action.
local _, RP = ...
local U = { frames = {}, unlocked = false, errors = 0 }
RP.UnitFrames = U
local ORDER = { "player", "target", "pet" }
local SPECS = {
    player = { option = "showPlayerFrame", label = "Player", name = "RicoPlatesPlayerFrame" },
    target = { option = "showTargetFrame", label = "Target", name = "RicoPlatesTargetFrame" },
    pet = { option = "showPetFrame", label = "Pet", name = "RicoPlatesPetFrame" },
}
local WHITE, FONT = "Interface\\Buttons\\WHITE8X8", RP.Theme.font

local function Exists(unit)
    return RP.PublicTrue(UnitExists(unit))
end

local function Text(parent, size)
    local text = (parent.ricoForeground or parent):CreateFontString(nil, "OVERLAY")
    if parent.ricoForeground then
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
    end
    text:SetFont(FONT, size or 11, "OUTLINE")
    text:SetTextColor(0.90, 0.94, 0.98)
    return text
end

local function Fill(parent, r, g, b, a)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetTexture(WHITE)
    texture:SetVertexColor(r, g, b, a)
    texture:SetAllPoints()
    return texture
end

local function Profile(unit, party)
    party = party or (type(unit) == "string" and unit:match("^party[1-4]$"))
    local small = unit == "pet"
    return {
        unitFrame = true,
        width = party and (RP.db.partyFrameWidth or 200) or math.floor(RP.db.unitFrameWidth * (small and 0.82 or 1)),
        height = party and (RP.db.partyFrameHeight or 20) or (RP.db.unitFrameHeight - (small and 4 or 0)),
        fontSize = small and 11 or 12,
        powerHeight = (small or party) and 10 or 12,
    }
end

function U:Error(message)
    self.errors = self.errors + 1
    self.lastError = RP.Readable(message) and type(message) == "string" and message:sub(1, 200)
        or "Could not construct unit frame"
end

local function Badge(icon)
    if icon.ricoBadge then return end
    icon.bg:SetVertexColor(0.014, 0.023, 0.019, 1)
    icon.tex:ClearAllPoints()
    icon.tex:SetPoint("TOPLEFT", icon, "TOPLEFT", 3, -3)
    icon.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 3)
    local badge = {edges = {}}
    icon.ricoBadge = badge
    local function Edge(point, relative, opposite, horizontal)
        local texture = icon:CreateTexture(nil, "BORDER")
        texture:SetTexture(WHITE)
        texture:SetPoint(point, icon, relative, 0, 0)
        texture:SetPoint(opposite, icon, opposite, 0, 0)
        if horizontal then texture:SetHeight(1) else texture:SetWidth(1) end
        texture:SetVertexColor(0.34, 0.27, 0.14, 1)
        badge.edges[#badge.edges + 1] = texture
    end
    Edge("TOPLEFT", "TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", false)
    badge.highlight = icon:CreateTexture(nil, "OVERLAY")
    badge.highlight:SetTexture(WHITE)
    badge.highlight:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -1)
    badge.highlight:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -2, -1)
    badge.highlight:SetHeight(1)
    badge.highlight:SetVertexColor(0.73, 0.61, 0.33, 0.8)
end

function U:LayoutIcons(entry)
    local p, portrait = entry.plate, entry.portrait
    local mirrored = entry.unit == "target"
    local corner = mirrored and "RIGHT" or "LEFT"
    p.levelBox:ClearAllPoints()
    p.levelBox:SetSize(26, 18)
    p.levelBox:SetFrameLevel(entry.portraitFront:GetFrameLevel() + 2)
    p.levelBox:SetPoint("TOP" .. corner, portrait, "TOP" .. corner, mirrored and 4 or -4, 4)
    p.classIcon:ClearAllPoints()
    Badge(p.classIcon)
    p.classIcon:SetSize(22, 22)
    p.classIcon:SetFrameLevel(entry.portraitFront:GetFrameLevel() + 2)
    p.classIcon:SetPoint(mirrored and "TOPLEFT" or "TOPRIGHT", portrait,
        "TOP" .. corner, mirrored and 6 or -6, -24)
    p.factionIcon:ClearAllPoints()
    Badge(p.factionIcon)
    p.factionIcon:SetSize(22, 22)
    p.factionIcon:SetFrameLevel(entry.portraitFront:GetFrameLevel() + 2)
    if p.classIcon:IsShown() then
        p.factionIcon:SetPoint(mirrored and "TOPLEFT" or "TOPRIGHT", p.classIcon,
            mirrored and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, -4)
    else
        p.factionIcon:SetPoint(mirrored and "TOPLEFT" or "TOPRIGHT", portrait,
            "TOP" .. corner, mirrored and 6 or -6, -26)
    end
    p.quest:ClearAllPoints()
    p.quest:SetFrameLevel(entry.portraitFront:GetFrameLevel() + 3)
    local questAnchor = RP.db.showLevel and p.levelBox or portrait
    p.quest:SetPoint(mirrored and "LEFT" or "RIGHT", questAnchor, corner, mirrored and 5 or -5, 0)
    p.quest.text:ClearAllPoints()
    p.quest.text:SetPoint(mirrored and "RIGHT" or "LEFT", p, mirrored and "LEFT" or "RIGHT", mirrored and -8 or 8, 0)
    p.name:ClearAllPoints()
    p.name:SetPoint(mirrored and "BOTTOMRIGHT" or "BOTTOMLEFT", p, mirrored and "TOPRIGHT" or "TOPLEFT", 0, 8)
    p.name:SetWidth(0)
    p.name:SetWordWrap(false)
    p.name:SetJustifyH(mirrored and "RIGHT" or "LEFT")
    if RP.LootButton then RP.LootButton:Layout(p) end
end

function U:LayoutVisual(entry)
    local small = entry.unit == "pet"
    local portraitSize = (small or entry.partyFrame) and 56 or 72
    local style = Profile(entry.unit, entry.partyFrame)
    local mirrored = entry.unit == "target"
    local headroom = style.fontSize + 13 + (RP.db.showDebuffs and RP.db.debuffSize + 4 or 0)
    entry.plate.style = style
    RP.Plates:Layout(entry.plate)
    entry.portrait:SetSize(portraitSize, portraitSize)
    entry.portrait:ClearAllPoints()
    entry.portrait:SetPoint(mirrored and "TOPRIGHT" or "TOPLEFT", entry.button,
        mirrored and "TOPRIGHT" or "TOPLEFT", mirrored and -28 or 28, -headroom)
    entry.plate:ClearAllPoints()
    entry.plate:SetPoint(mirrored and "TOPRIGHT" or "TOPLEFT", entry.portrait,
        mirrored and "TOPLEFT" or "TOPRIGHT", mirrored and -8 or 8, -4)
    entry.width = portraitSize + style.width + 46
    local castHeight = entry.unit == "player" and 0 or math.max(12, style.fontSize) + 4
    local barHeight = style.height + style.powerHeight + castHeight + 14
        + (RP.db.showBuffs and RP.db.buffSize + 4 or 0)
    entry.height = headroom + math.max(portraitSize + (small and 6 or 22), barHeight) + 5
    -- Keep the existing body center/height stable when the optional footer is
    -- toggled. Its extra extent belongs below the HUD rather than in its anchor.
    entry.extraBottom = entry.unit == "target" and not entry.preview and RP.db.showTargetOfTarget and 44 or 0
    if entry.classResourceAnchor then
        entry.classResourceAnchor:SetSize(portraitSize, 14)
        entry.classResourceAnchor:ClearAllPoints()
        entry.classResourceAnchor:SetPoint("TOP", entry.portrait, "BOTTOM", 0, -8)
        if RP.ClassResources then RP.ClassResources:Layout(entry) end
    end
    self:LayoutIcons(entry)
end

local function PortraitBezel(entry)
    local parent = entry.portraitFront
    local bronze, light = {0.34, 0.27, 0.14, 1}, {0.73, 0.61, 0.33, 1}
    local bezel = {metal = {}, lights = {}, ironColors = {}}
    for i, edge in ipairs(entry.portraitIron.metal) do bezel.ironColors[i] = {edge:GetVertexColor()} end
    entry.bezel = bezel
    local function Rect(point, relative, x, y, width, height, color)
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        t:SetPoint(point, parent, relative, x, y)
        t:SetSize(width, height)
        t:SetVertexColor(unpack(color))
        if color == bronze then bezel.metal[#bezel.metal + 1] = t end
        if color == light then bezel.lights[#bezel.lights + 1] = t end
        return t
    end
    local shadow = {0.07, 0.09, 0.075, 1}
    for _, side in ipairs({"LEFT", "RIGHT"}) do
        local sign = side == "LEFT" and 1 or -1
        for _, vertical in ipairs({"TOP", "BOTTOM"}) do
            local direction = vertical == "TOP" and -1 or 1
            local corner = vertical .. side
            Rect(corner, corner, -sign * 2, -direction * 2, 18, 3, bronze)
            Rect(corner, corner, -sign * 2, -direction * 2, 3, 18, bronze)
            Rect(corner, corner, sign, direction, 12, 1, light)
            Rect(corner, corner, sign, direction, 1, 12, light)
            Rect(corner, corner, sign * 5, direction * 5, 2, 2, shadow)
            Rect(corner, corner, sign * 5, direction * 5, 1, 1, light)
        end
    end
    local crest = Rect("TOP", "TOP", 0, 4, 8, 8, bronze)
    crest:SetRotation(math.pi / 4)
    local gem = Rect("TOP", "TOP", 0, 2, 4, 4, {0.24, 0.66, 0.43, 1})
    gem:SetRotation(math.pi / 4)
    bezel.crest, bezel.gem = crest, gem
    Rect("BOTTOM", "BOTTOM", 0, -3, 24, 2, bronze)
    Rect("BOTTOM", "BOTTOM", 0, -2, 18, 1, light)

    local crown = CreateFrame("Frame", nil, parent)
    crown:SetSize(24, 16)
    crown:SetPoint("BOTTOM", parent, "TOP", 0, -1)
    crown:EnableMouse(false)
    local function CrownPiece(x, y, width, height, r, g, b)
        local t = crown:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE)
        t:SetPoint("BOTTOMLEFT", crown, "BOTTOMLEFT", x, y)
        t:SetSize(width, height)
        t:SetVertexColor(r, g, b, 1)
        return t
    end
    CrownPiece(1, 1, 22, 5, 0.16, 0.085, 0.015)
    CrownPiece(2, 2, 20, 4, 0.72, 0.43, 0.075)
    CrownPiece(3, 5, 18, 3, 0.90, 0.64, 0.20)
    CrownPiece(1, 6, 4, 5, 0.84, 0.55, 0.12)
    CrownPiece(10, 6, 4, 8, 1.00, 0.78, 0.28)
    CrownPiece(19, 6, 4, 5, 0.84, 0.55, 0.12)
    CrownPiece(2, 3, 20, 1, 1.00, 0.86, 0.43)
    CrownPiece(2, 10, 2, 2, 1.00, 0.91, 0.57)
    CrownPiece(11, 13, 2, 2, 1.00, 0.94, 0.65)
    CrownPiece(20, 10, 2, 2, 1.00, 0.91, 0.57)
    bezel.crownGem = CrownPiece(10, 3, 4, 4, 1.00, 0.44, 0.08)
    bezel.crown = crown
    crown:Hide()

    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(62, 12)
    badge:SetPoint("BOTTOM", parent, "BOTTOM", 0, 3)
    badge:EnableMouse(false)
    Fill(badge, 0.018, 0.021, 0.018, 0.95)
    badge.label = Text(badge, 8)
    badge.label:SetAllPoints()
    badge.label:SetJustifyH("CENTER")
    badge:Hide()
    entry.rankBadge = badge
end

function U:UpdateClassification(entry, previewClassification)
    if not entry or not entry.bezel then return end
    local rank = "normal"
    if RP.IsSecret(previewClassification) then
        rank = "normal"
    elseif previewClassification ~= nil then
        if RP.Readable(previewClassification) and type(previewClassification) == "string" then rank = previewClassification end
    elseif not entry.preview and not RP.PublicTrue(UnitIsPlayer(entry.unit)) and type(UnitClassification) == "function" then
        local ok, value = pcall(UnitClassification, entry.unit)
        if ok and RP.Readable(value) and type(value) == "string" then rank = value end
    end
    local labels = {elite = "ELITE", rareelite = "RARE ELITE", worldboss = "BOSS", rare = "RARE"}
    if not labels[rank] then rank = "normal" end
    entry.classification = rank
    local elite = rank == "elite" or rank == "rareelite" or rank == "worldboss"
    local rare = rank == "rare"
    local metal = elite and {0.63, 0.39, 0.10, 1} or rare and {0.38, 0.46, 0.54, 1} or {0.34, 0.27, 0.14, 1}
    local light = elite and {1.00, 0.84, 0.39, 1} or rare and {0.78, 0.88, 0.96, 1} or {0.73, 0.61, 0.33, 1}
    for _, t in ipairs(entry.bezel.metal) do t:SetVertexColor(unpack(metal)) end
    for _, t in ipairs(entry.bezel.lights) do t:SetVertexColor(unpack(light)) end
    for i, t in ipairs(entry.portraitIron.metal) do
        if elite or rare then t:SetVertexColor(unpack(i == 1 and light or metal))
        else t:SetVertexColor(unpack(entry.bezel.ironColors[i])) end
    end
    if entry.plate then
        for _, icon in ipairs({entry.plate.classIcon, entry.plate.factionIcon}) do
            if icon.ricoBadge then
                for _, edge in ipairs(icon.ricoBadge.edges) do edge:SetVertexColor(unpack(metal)) end
                icon.ricoBadge.highlight:SetVertexColor(light[1], light[2], light[3], 0.8)
            end
        end
    end
    entry.bezel.crest:SetShown(not elite)
    entry.bezel.gem:SetShown(not elite)
    entry.bezel.gem:SetVertexColor(rare and 0.28 or 0.24, rare and 0.65 or 0.66, rare and 1.00 or 0.43, 1)
    entry.bezel.crown:SetShown(elite)
    if rank == "rareelite" then entry.bezel.crownGem:SetVertexColor(0.28, 0.65, 1.00, 1)
    elseif rank == "worldboss" then entry.bezel.crownGem:SetVertexColor(0.95, 0.15, 0.10, 1)
    else entry.bezel.crownGem:SetVertexColor(1.00, 0.60, 0.12, 1) end
    entry.rankBadge.label:SetText(labels[rank] or "")
    entry.rankBadge.label:SetTextColor(unpack(light))
    entry.rankBadge:SetShown(rank ~= "normal")
    if entry.status then
        entry.status:ClearAllPoints()
        entry.status:SetPoint("BOTTOM", entry.portraitFront, "BOTTOM", 0, rank ~= "normal" and 18 or 4)
    end
end

function U:CreateVisual(parent, unit, preview)
    local entry = { button = parent, unit = unit, preview = preview,
        partyFrame = type(unit) == "string" and unit:match("^party[1-4]$") ~= nil }
    entry.portrait = RP.Portraits:Create(parent)
    entry.portrait:Hide()
    entry.portraitFront = CreateFrame("Frame", nil, entry.portrait)
    entry.portraitFront:SetAllPoints(entry.portrait)
    entry.portraitFront:SetFrameLevel(entry.portrait:GetFrameLevel() + 5)
    entry.portraitFront:EnableMouse(false)
    entry.portraitIron = RP.Plates:CreateIronTrim(entry.portraitFront)
    PortraitBezel(entry)
    entry.status = Text(entry.portraitFront, 9)
    entry.status:SetPoint("BOTTOM", entry.portraitFront, "BOTTOM", 0, 4)
    self:UpdateClassification(entry, "normal")
    entry.plate = RP.Plates:Build(parent, preview, Profile(unit))
    entry.plate.unit, entry.plate.base = unit, parent
    entry.plate.lootPortrait = entry.portrait
    entry.plate.levelSkull = entry.plate.levelBox:CreateTexture(nil, "OVERLAY")
    entry.plate.levelSkull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    entry.plate.levelSkull:SetSize(20, 20)
    entry.plate.levelSkull:SetPoint("CENTER")
    entry.plate.levelSkull:Hide()
    entry.plate:Hide()
    if unit == "player" or unit == "target" then
        entry.classResourceAnchor = CreateFrame("Frame", nil, parent)
        entry.classResourceAnchor:EnableMouse(false)
    end
    self:LayoutVisual(entry)
    if entry.classResourceAnchor and RP.ClassResources then RP.ClassResources:Create(entry) end
    if RP.Features and RP.Features.AttachBadges then RP.Features:AttachBadges(entry) end
    if RP.Aggro then RP.Aggro:AttachPortrait(entry) end
    return entry
end

function U:ClearVisuals(entry)
    if entry.unit == "target" then self:ClearTargetTarget() end
    self:HideUnitTooltip(entry)
    self:UpdateClassification(entry, "normal")
    local p = entry.plate
    p.visible = false
    if RP.EnemyRange then RP.EnemyRange:Reset(p) end
    if RP.Aggro then RP.Aggro:Forget(p) end
    p.classIcon:Hide(); p.factionIcon:Hide()
    p.classIcon.classToken, p.factionIcon.factionToken = nil, nil
    if RP.ClassResources then RP.ClassResources:Detach(entry) end
    if RP.QuestieIcons then RP.QuestieIcons:Detach(p) end
    if RP.LootButton then RP.LootButton:Detach(p) end
    RP.Plates:StopBubbles(p)
    RP.Plates:UpdateHealPreview(p.healPreview)
    if RP.HealerHots then RP.HealerHots:Hide(entry) end
    if RP.Auras then RP.Auras:Detach(p) end
    RP.Plates:SetPowerVisible(p, false)
    RP.Plates:SetCastVisible(p, false)
    p.quest:Hide()
    p.quest.text:SetText("")
    p:Hide()
    RP.Portraits:Clear(entry.portrait)
    entry.portrait:Hide()
    entry.status:SetText("")
    if entry.unit == "target" and not entry.preview and RP.Quest then RP.Quest:Forget("target") end
end

function U:UpdateStatus(entry)
    local unit = entry.unit
    local connected = UnitIsConnected and UnitIsConnected(unit)
    if RP.Readable(connected) and connected == false then
        entry.status:SetText("Offline")
    elseif UnitIsDeadOrGhost and RP.PublicTrue(UnitIsDeadOrGhost(unit)) then
        entry.status:SetText("Dead")
    else
        entry.status:SetText("")
    end
end

local function PublicNumber(value)
    return RP.Readable(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function DifficultyColor(unit, level, previewPlayerLevel)
    local color
    if previewPlayerLevel == nil and C_PlayerInfo
        and type(C_PlayerInfo.GetContentDifficultyCreatureForPlayer) == "function"
        and type(GetDifficultyColor) == "function" then
        local ok, difficulty = pcall(C_PlayerInfo.GetContentDifficultyCreatureForPlayer, unit)
        if ok and RP.IsSecret(difficulty) then return end
        if ok and difficulty ~= nil then
            local gotColor, result = pcall(GetDifficultyColor, difficulty)
            if gotColor then color = result end
        end
    end
    if RP.IsSecret(color) then return end
    if color == nil and PublicNumber(level) then
        local playerLevel = previewPlayerLevel
        if playerLevel == nil then
            local getter = UnitEffectiveLevel or UnitLevel
            local ok, result = pcall(getter, "player")
            if ok then playerLevel = result end
        end
        if PublicNumber(playerLevel) and type(GetRelativeDifficultyColor) == "function" then
            local ok, result = pcall(GetRelativeDifficultyColor, playerLevel, level)
            if ok then color = result end
        elseif type(GetQuestDifficultyColor) == "function" then
            local ok, result = pcall(GetQuestDifficultyColor, level)
            if ok then color = result end
        end
    end
    if not RP.Readable(color) or type(color) ~= "table"
        or (canaccesstable and not canaccesstable(color)) then return end
    local ok, r, g, b = pcall(function() return color.r, color.g, color.b end)
    if ok and PublicNumber(r) and PublicNumber(g) and PublicNumber(b) then return r, g, b end
end

function U:UpdateLevel(entry, previewLevel, previewPlayerLevel)
    local p = entry.plate
    p.levelSkull:Hide()
    p.level:SetTextColor(0.94, 0.95, 0.98)
    p.levelBox.bg:SetVertexColor(0.035, 0.045, 0.060, 1)
    if not RP.db.showLevel then p.levelBox:Hide(); return end
    local level = previewLevel
    if level == nil then
        local ok, result = pcall(UnitEffectiveLevel or UnitLevel, entry.unit)
        if ok then level = result end
    end
    p.levelBox:Show()
    if RP.IsSecret(level) then
        p.level:SetFormattedText("%d", level); p.level:Show(); return
    end
    if not PublicNumber(level) then p.level:SetText("?"); p.level:Show(); return end
    if level <= 0 then
        p.level:Hide(); p.levelSkull:Show()
        p.levelBox.bg:SetVertexColor(0.18, 0.025, 0.025, 1)
        return
    end
    p.level:SetFormattedText("%d", level); p.level:Show()
    local kind = p.baseKind or p.kind
    if entry.unit == "target" and (kind == "enemy" or kind == "neutral") then
        local r, g, b = DifficultyColor(entry.unit, level, previewPlayerLevel)
        if r then
            p.level:SetTextColor(r, g, b)
            p.levelBox.bg:SetVertexColor(r * 0.14, g * 0.14, b * 0.14, 1)
        end
    end
end

function U:RefreshUnit(unit, refreshPortrait)
    local entry = self.frames[unit]
    return self:RefreshVisual(entry, refreshPortrait)
end

-- Party visuals reuse the same renderer while their native secure buttons keep
-- ownership of visibility/clicks. They do not enter the movable HUD registry.
function U:RefreshVisual(entry, refreshPortrait)
    if not entry or not entry.enabled then return end
    local unit = entry.unit
    if not Exists(unit) then self:ClearVisuals(entry); return end
    local p = entry.plate
    local kind, _, isPlayer, baseKind = RP.Plates:Classify(unit)
    -- HUD visibility follows the selected unit, never the overhead friendly
    -- player/NPC/group filters. The player's own health is consistently green.
    if unit == "player" then kind, baseKind = "friendly", "friendly" end
    p.unit, p.isPlayer, p.baseKind, p.visible = unit, isPlayer, baseKind or kind, true
    if unit == "target" and not entry.preview and RP.EnemyRange then RP.EnemyRange:Update(p) end
    RP.Plates:SetColor(p, kind)
    RP.Plates:UpdateIdentity(p)
    self:LayoutIcons(entry)
    RP.Plates:UpdateHealth(p)
    if not entry.preview and RP.HealerHots then
        RP.HealerHots:Attach(entry, unit, p.front, p.health, entry.partyFrame and "standard" or "unit", refreshPortrait)
    end
    RP.Plates:UpdatePower(p)
    RP.Plates:UpdateTarget(p)
    self:UpdateLevel(entry)
    self:UpdateClassification(entry)
    RP.Plates:UpdateCast(p)
    p:Show()
    RP.Plates:StartBubbles(p)
    if RP.Auras and not entry.nativeAuras then
        -- A target token can now refer to another unit while still equal to
        -- the previous public string. Explicitly invalidate its aura contents.
        if refreshPortrait then RP.Auras:Detach(p) end
        RP.Auras:Attach(p, unit)
    end
    RP.Plates:PaintQuest(p, nil)
    if unit == "target" and not isPlayer and RP.Quest then
        RP.Plates:PaintQuest(p, RP.Quest:GetUnitInfo(unit))
    end
    entry.portrait:Show()
    if RP.Aggro then RP.Aggro:Refresh(p) end
    RP.Portraits:SetUnit(entry.portrait, unit, refreshPortrait)
    self:UpdateStatus(entry)
    if RP.QuestieIcons and unit == "target" then RP.QuestieIcons:Attach(p) end
    if RP.ClassResources and entry.classResourceAnchor then RP.ClassResources:Attach(entry) end
    if unit == "target" then self:RefreshTargetTarget() end
end

function U:RefreshAll(refreshPortrait)
    for _, unit in ipairs(ORDER) do self:RefreshUnit(unit, refreshPortrait) end
end

function U:OnQuestInfoChanged(unit, info)
    if unit ~= "target" then return end
    local entry = self.frames.target
    if entry and entry.enabled and entry.plate.visible then RP.Plates:PaintQuest(entry.plate, info) end
end

function U:ShowUnitTooltip(entry)
    if RP.Features and RP.Features.HideBadgeTooltip then RP.Features:HideBadgeTooltip() end
    if not entry or not entry.enabled or not Exists(entry.unit) then self:HideUnitTooltip(entry); return end
    if not self.unitTooltip then
        local tooltip = CreateFrame("GameTooltip", "RicoPlatesUnitTooltip", UIParent, "GameTooltipTemplate")
        local healthBar = tooltip.StatusBar
        if healthBar then
            -- The native watcher can fill this bar with secret HP. The
            -- template's color script compares those values even though it
            -- uses a fixed green color here.
            healthBar:SetScript("OnValueChanged", nil)
            healthBar:SetStatusBarColor(0, 1, 0)
        end
        tooltip:SetFrameStrata("TOOLTIP")
        tooltip:SetClampedToScreen(true)
        tooltip:EnableMouse(false)
        RP.Theme:Panel(tooltip):SetVertexColor(0.014, 0.022, 0.018, 1)
        tooltip:SetAlpha(1)
        self.unitTooltip = tooltip
    end
    local tooltip = self.unitTooltip
    tooltip:SetOwner(entry.button, "ANCHOR_NONE")
    tooltip:ClearLines()
    local ok, result = pcall(tooltip.SetUnit, tooltip, entry.unit)
    if not ok or (RP.Readable(result) and result == false) then tooltip:Hide(); return end
    -- Anchor below the complete HUD, not at the pointer or over its bars.
    tooltip:ClearAllPoints()
    if entry.partyFrame then tooltip:SetPoint("TOPLEFT",entry.button,"TOPRIGHT",12,0)
    else tooltip:SetPoint("TOPLEFT", entry.button, "BOTTOMLEFT", 0, -12) end
    tooltip:Show()
end

function U:HideUnitTooltip(entry)
    local tooltip = self.unitTooltip
    if tooltip and (not entry or tooltip:IsOwned(entry.button)) then tooltip:Hide() end
end

function U:Create(unit)
    if RP:IsInCombat() then self.pending = true; return nil end
    if self.frames[unit] then return self.frames[unit] end
    local spec = SPECS[unit]
    -- The always-visible anchor can be moved outside combat even when the
    -- native unit watch hides an absent target/pet's secure button.
    local anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:EnableMouse(false)
    local button = CreateFrame("Button", spec.name, anchor, "SecureUnitButtonTemplate")
    button:Hide()
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("CENTER", anchor, "CENTER")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("unit", unit)
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "togglemenu")
    button.unit = unit
    -- Preserve SecureUnitButtonTemplate's native OnClick handler.
    local entry = self:CreateVisual(button, unit, false)
    entry.anchor = anchor
    self.frames[unit] = entry
    button:HookScript("OnShow", function() U:RefreshUnit(unit, true) end)
    button:HookScript("OnHide", function() U:ClearVisuals(entry) end)
    button:SetScript("OnEnter", function() U:ShowUnitTooltip(entry) end)
    button:SetScript("OnLeave", function() U:HideUnitTooltip(entry) end)
    if type(ClickCastFrames) == "table" then ClickCastFrames[button] = true end

    -- Movers are separate ordinary frames. They can disappear at combat start
    -- without changing protected wrappers or obstructing their native clicks.
    local mover = CreateFrame("Frame", nil, UIParent)
    mover:SetFrameStrata("FULLSCREEN_DIALOG")
    mover:SetFrameLevel(100)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    Fill(mover, 0.12, 0.53, 0.50, 0.48)
    mover.label = Text(mover, 12)
    mover.label:SetPoint("CENTER")
    mover.label:SetText(spec.label .. " — drag")
    mover:SetScript("OnDragStart", function()
        if RP:IsInCombat() or not U.unlocked or not entry.enabled then return end
        anchor:StartMoving()
        entry.moving = true
    end)
    mover:SetScript("OnDragStop", function() U:FinishMove(entry) end)
    mover:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" then U:SetUnlocked(false) end
    end)
    mover:Hide()
    entry.mover = mover
    self:LayoutMover(entry)
    return entry
end

function U:LayoutMover(entry)
    if not entry.mover or not entry.anchor then return end
    entry.mover:ClearAllPoints()
    entry.mover:SetPoint("TOPLEFT", entry.anchor, "TOPLEFT", 0, 0)
    entry.mover:SetPoint("BOTTOMRIGHT", entry.anchor, "BOTTOMRIGHT", 0,
        -(entry.extraBottom or 0) * RP.db.unitFrameScale)
end

function U:FinishMove(entry)
    if not entry.moving then return end
    if RP:IsInCombat() then self.pendingMoves = true; return end
    entry.anchor:StopMovingOrSizing()
    entry.moving = false
    local x, y = entry.anchor:GetCenter()
    local scale = entry.anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if type(x) == "number" and type(y) == "number" and RP.Readable(x) and RP.Readable(y) then
        local position = RP.db.unitFramePositions[entry.unit]
        local nextX, nextY = x * scale - UIParent:GetWidth() / 2, y * scale
        if RP.Layout then nextX, nextY = RP.Layout:SnapPosition(entry, nextX, nextY) end
        if nextX and nextY then position.x, position.y = nextX, nextY end
    end
    self:Place(entry)
end

function U:Place(entry)
    if RP:IsInCombat() then self.pending = true; return end
    local position = RP.db.unitFramePositions[entry.unit]
    local x, y = position.x, position.y
    if RP.Layout then x, y = RP.Layout:ClampPosition(entry, x, y) end
    entry.anchor:ClearAllPoints()
    entry.anchor:SetPoint("CENTER", UIParent, "BOTTOM", x / RP.db.unitFrameScale,
        y / RP.db.unitFrameScale)
end

function U:ClearTargetTarget()
    local entry = self.targetTarget
    if not entry then return end
    self:HideUnitTooltip(entry)
    entry.visual:Hide()
    entry.name:SetText("")
    entry.health:SetMinMaxValues(0, 1)
    entry.health:SetValue(0)
    entry.visible = false
end

function U:RefreshTargetTarget()
    local entry, target = self.targetTarget, self.frames.target
    if not entry then return end
    if not entry.enabled or not target or not target.enabled or not target.plate.visible
        or not Exists("target") or not Exists("targettarget") then self:ClearTargetTarget(); return end
    local current, maximum = UnitHealth("targettarget"), UnitHealthMax("targettarget")
    if (RP.Readable(current) and type(current) ~= "number")
        or (RP.Readable(maximum) and (type(maximum) ~= "number" or maximum <= 0)) then
        self:ClearTargetTarget(); return
    end
    local name = RP:DisplayName("targettarget")
    if RP.IsSecret(name) then entry.name:SetText(name) else entry.name:SetText(name or "Unknown") end
    local kind = RP.Plates:Classify("targettarget")
    local color = RP.colors[kind] or RP.colors.neutral
    if RP.PublicTrue(UnitIsPlayer("targettarget")) then
        local _, class = UnitClass("targettarget")
        local classColor = RP.Readable(class) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if classColor then color = {classColor.r, classColor.g, classColor.b} end
    end
    entry.health:SetStatusBarColor(color[1], color[2], color[3], 1)
    entry.health:SetMinMaxValues(0, maximum)
    entry.health:SetValue(current)
    entry.visible = true
    entry.visual:Show()
end

function U:ConfigureTargetTarget()
    if RP:IsInCombat() then self.pending = true; return end
    local target = self.frames.target
    local enabled = target and target.enabled and RP.db.showTargetOfTarget
    local entry = self.targetTarget
    if enabled and not entry then
        local button = CreateFrame("Button", "RicoPlatesTargetTargetFrame", target.button, "SecureUnitButtonTemplate")
        button:Hide()
        button:RegisterForClicks("AnyUp")
        button:SetAttribute("unit", "targettarget")
        button:SetAttribute("*type1", "target")
        button:SetAttribute("*type2", "togglemenu")
        button.unit = "targettarget"
        local visual = CreateFrame("Frame", nil, button)
        visual:SetAllPoints(button); visual:EnableMouse(false)
        RP.Theme:Panel(visual):SetVertexColor(0.018, 0.030, 0.023, 0.98)
        local label = Text(visual, 8)
        label:SetPoint("TOPLEFT", 5, -4)
        label:SetTextColor(0.48, 0.67, 0.57)
        label:SetText("TARGET OF TARGET")
        local name = Text(visual, 10)
        name:SetPoint("TOPLEFT", 5, -16); name:SetPoint("TOPRIGHT", -5, -16)
        name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        local health = CreateFrame("StatusBar", nil, visual)
        health:SetStatusBarTexture(WHITE)
        health:SetPoint("BOTTOMLEFT", 5, 4); health:SetPoint("BOTTOMRIGHT", -5, 4)
        health:SetHeight(5)
        Fill(health, 0.04, 0.06, 0.05, 1)
        health:EnableMouse(false)
        entry = {unit = "targettarget", button = button, visual = visual, label = label, name = name, health = health}
        self.targetTarget = entry
        visual:Hide()
        button:HookScript("OnShow", function() U:RefreshTargetTarget() end)
        button:HookScript("OnHide", function() U:ClearTargetTarget() end)
        button:SetScript("OnEnter", function() U:ShowUnitTooltip(entry) end)
        button:SetScript("OnLeave", function() U:HideUnitTooltip(entry) end)
        if type(ClickCastFrames) == "table" then ClickCastFrames[button] = true end
    end
    if not entry then return end
    entry.enabled = enabled and true or false
    if entry.enabled then
        entry.button:SetSize(math.min(210, RP.db.unitFrameWidth), 38)
        entry.button:ClearAllPoints()
        entry.button:SetPoint("TOPLEFT", target.button, "BOTTOMLEFT", 10, -6)
        RegisterUnitWatch(entry.button)
        self:RefreshTargetTarget()
    else
        UnregisterUnitWatch(entry.button)
        entry.button:Hide()
        self:ClearTargetTarget()
    end
end

function U:ApplySettings()
    if RP:IsInCombat() then self.pending = true; return end
    self.pending = nil
    if self.pendingMoves then
        self.pendingMoves = nil
        for _, entry in pairs(self.frames) do self:FinishMove(entry) end
    end
    local replaced = {}
    local active = RP.db.enabled and RP.db.unitFramesEnabled
    for _, unit in ipairs(ORDER) do
        local enabled = active and RP.db[SPECS[unit].option]
        local entry = self.frames[unit]
        if enabled and not entry then
            local ok, result = pcall(self.Create, self, unit)
            if ok then entry = result else self:Error(result) end
        end
        if entry then
            if entry.moving then self:FinishMove(entry) end
            entry.enabled = enabled and true or false
            if entry.enabled then
                self:LayoutVisual(entry)
                entry.button:SetSize(entry.width, entry.height)
                entry.anchor:SetSize(entry.width, entry.height)
                entry.anchor:SetScale(RP.db.unitFrameScale)
                self:Place(entry)
                self:LayoutMover(entry)
                RegisterUnitWatch(entry.button)
                replaced[unit] = true
                self:RefreshUnit(unit, false)
            else
                UnregisterUnitWatch(entry.button)
                entry.button:Hide()
                self:ClearVisuals(entry)
            end
        end
    end
    if RP.NativeFrames then
        local _, status = RP.NativeFrames:Apply(replaced)
        for unit, result in pairs(status or {}) do
            local entry = self.frames[unit]
            if entry and entry.enabled and result.ok == false then
                -- Preserve the working native frame if its necessary companion
                -- controls cannot safely remain visible. Never show both roots.
                entry.enabled = false
                UnregisterUnitWatch(entry.button)
                entry.button:Hide()
                self:ClearVisuals(entry)
                self:Error(result.error or "Could not replace the default frame")
            end
        end
    end
    if RP.ClassResources then RP.ClassResources:Update() end
    self:ConfigureTargetTarget()
    RP:SyncNativeClassResources()
    self:UpdateMovers()
end

function U:IsUnlocked()
    return self.unlocked
end

function U:CreateMoveToolbar()
    if self.moveToolbar then return self.moveToolbar end
    local T = RP.Theme
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(460, 102)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(110)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -45)
    panel:EnableMouse(true)
    T:Window(panel, true)
    local title = Text(panel, 12)
    title:SetFont(T.font, 12, "")
    title:SetTextColor(unpack(T.colors.text))
    title:SetPoint("TOP", 0, -10)
    title:SetText("Drag a green outline to move the entire frame")
    local function Action(label, width, x, callback)
        local b = CreateFrame("Button", nil, panel)
        b:SetSize(width, 27)
        b:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, 9)
        b:EnableMouse(true)
        b.background = T:Panel(b)
        b.label = Text(b, 11)
        b.label:SetFont(T.font, 11, "")
        b.label:SetTextColor(unpack(T.colors.text))
        b.label:SetPoint("CENTER")
        b.label:SetText(label)
        b:SetScript("OnClick", callback)
        T:Button(b, b.background)
        return b
    end
    panel.lock = Action("Lock frames", 132, 35, function() U:SetUnlocked(false) end)
    panel.reset = Action("Reset positions", 155, 180, function() U:ResetPositions() end)
    local function SnapCheck(label, key, x)
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(22, 22); check:SetPoint("TOPLEFT", x, -31)
        RP.Theme:Check(check)
        check.label = Text(panel, 11); check.label:SetPoint("LEFT", check, "RIGHT", 4, 0); check.label:SetText(label)
        check:SetScript("OnClick", function(self)
            RP:SetOption(key, self:GetChecked() and true or false)
            U:UpdateMovers()
        end)
        check.key = key
        return check
    end
    panel.gridCheck = SnapCheck("Grid snap", "layoutGridSnap", 24)
    panel.frameCheck = SnapCheck("Snap to frames", "layoutFrameSnap", 198)
    panel.gridSize = Action("Grid: 8px", 88, 345, function()
        local values = {4, 8, 16, 32}
        local current = 1
        for i, value in ipairs(values) do if RP.db.layoutGridSize == value then current = i end end
        RP:SetOption("layoutGridSize", values[current % #values + 1])
        U:UpdateMovers()
    end)
    panel:Hide()
    self.moveToolbar = panel
    return panel
end

function U:UpdateMovers()
    local combat = RP:IsInCombat()
    local show = self.unlocked and not combat
    for _, entry in pairs(self.frames) do
        -- Hiding a drag handle need not emit OnDragStop. Remember the move
        -- without touching the protected anchor until combat has ended.
        if combat and entry.moving then self.pendingMoves = true end
        entry.mover:SetShown(show and entry.enabled)
    end
    if self.moveToolbar then self.moveToolbar:SetShown(show) end
    if RP.Layout then RP.Layout:UpdateGrid(show) end
    if self.moveToolbar then
        self.moveToolbar.gridCheck:SetChecked(RP.db.layoutGridSnap)
        self.moveToolbar.frameCheck:SetChecked(RP.db.layoutFrameSnap)
        self.moveToolbar.gridSize.label:SetText("Grid: " .. RP.db.layoutGridSize .. "px")
    end
    if RP.Options and RP.Options.RefreshState then RP.Options:RefreshState() end
end

function U:SetUnlocked(unlocked)
    if RP:IsInCombat() then
        RP:Print("Unit frames can be moved out of combat.")
        return false
    end
    self.unlocked = unlocked and true or false
    if self.unlocked then
        self:CreateMoveToolbar()
        if RP.Options and RP.Options.frame then RP.Options.frame:Hide() end
    end
    if not self.unlocked then
        for _, entry in pairs(self.frames) do self:FinishMove(entry) end
    end
    self:UpdateMovers()
    RP:Print(self.unlocked and "Drag a green outline to move the portrait and bars together. Click Lock frames or use /rp lock."
        or "Unit frames locked; positions saved.")
    return true
end

function U:ResetPositions()
    if RP:IsInCombat() then RP:Print("Positions can be reset out of combat."); return false end
    for _, unit in ipairs(ORDER) do
        local defaults = RP.defaults.unitFramePositions[unit]
        RP.db.unitFramePositions[unit] = { x = defaults.x, y = defaults.y }
    end
    self:ApplySettings()
    return true
end

function U:GetStatus()
    local active = 0
    for _, entry in pairs(self.frames) do if entry.enabled then active = active + 1 end end
    return "Unit frames: " .. active .. "/3 enabled | 3D portraits: "
        .. (RP.db.unitPortrait3D and "on (2D fallback for restricted models)" or "off")
        .. " | messages: " .. self.errors
end

local PREVIEWS = {
    player = { name = "Your character", kind = "friendly", level = 20, hp = 840, max = 1000,
        power = 65, powerMax = 100, powerColor = {0.20, 0.48, 1}, class = "MAGE",
        buffs = {{ icon = "Interface\\Icons\\Spell_Holy_WordFortitude", duration = 60, remaining = 42 }},
        debuffs = {{ icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", duration = 18, remaining = 10 }} },
    target = { name = "Elite target", kind = "enemy", classification = "elite", level = 22, hp = 760, max = 1200,
        power = 40, powerMax = 100, powerColor = {0.20, 0.48, 1},
        debuffs = {{ icon = "Interface\\Icons\\Ability_Rogue_Garrote", duration = 18, remaining = 11 }} },
    pet = { name = "Your pet", kind = "friendly", level = 19, hp = 360, max = 500,
        power = 55, powerMax = 100, powerColor = {1, 0.60, 0.15} },
}

function U:CreateOptionsPreview(parent)
    local preview = CreateFrame("Frame", nil, parent)
    preview:SetAllPoints(parent)
    preview:EnableMouse(false)
    preview.entries = {}
    for _, unit in ipairs(ORDER) do
        local panel = CreateFrame("Frame", nil, preview)
        panel:EnableMouse(false)
        local entry = self:CreateVisual(panel, unit, true)
        preview.entries[unit] = entry
        entry.hint = Text(panel, 10)
        entry.hint:SetTextColor(0.52, 0.62, 0.70)
        entry.hint:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 4, -20)
    end
    preview:Hide()
    return preview
end

function U:RefreshOptionsPreview(preview)
    if not preview or not preview:IsShown() then return end
    for i, unit in ipairs(ORDER) do
        local entry = preview.entries[unit]
        self:LayoutVisual(entry)
        entry.button:SetSize(entry.width, entry.height)
        local scale = math.min(0.72, 382 / entry.width, 104 / entry.height)
        entry.button:SetScale(scale)
        entry.button:ClearAllPoints()
        entry.button:SetPoint("TOPLEFT", preview, "TOPLEFT", 20 / scale, (-65 - (i - 1) * 144) / scale)
        local data = {}
        for key, value in pairs(PREVIEWS[unit]) do data[key] = value end
        if unit == "player" and UnitClass then
            local _, class = UnitClass("player")
            if RP.Readable(class) and class then data.class = class end
        end
        RP.Plates:UpdateDemo(entry.plate, data)
        self:LayoutIcons(entry)
        self:UpdateLevel(entry, data.level, PREVIEWS.player.level)
        self:UpdateClassification(entry, data.classification or "normal")
        if RP.ClassResources and entry.classResourceAnchor then RP.ClassResources:Preview(entry) end
        entry.portrait:Show()
        if Exists(unit) then RP.Portraits:SetUnit(entry.portrait, unit)
        else RP.Portraits:Clear(entry.portrait) end
        entry.hint:SetText(unit == "player" and "Example values • your actual portrait"
            or unit == "target" and "Selected target portrait; example values"
            or "Portrait available while you have a pet")
    end
end

function U:SetPreviewShown(preview, shown)
    if not preview then return end
    if shown then
        self.optionsPreview = preview
        preview:Show()
        self:RefreshOptionsPreview(preview)
    else
        for _, entry in pairs(preview.entries) do self:ClearVisuals(entry) end
        preview:Hide()
    end
end

function U:RefreshPreviewPortrait(unit)
    local preview = self.optionsPreview
    if not preview or not preview:IsShown() then return end
    local entry = preview.entries[unit]
    if not entry then return end
    entry.portrait:Show()
    if Exists(unit) then RP.Portraits:SetUnit(entry.portrait, unit, true)
    else RP.Portraits:Clear(entry.portrait) end
end

function U:Initialize()
    if self.initialized then return end
    self.initialized = true
    local eventFrame = CreateFrame("Frame")
    self.eventFrame = eventFrame
    local events = {
        "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "UNIT_PET", "UNIT_TARGET", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_CLASSIFICATION_CHANGED", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION",
        "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP",
        "UNIT_GUILD_UPDATE", "GUILD_ROSTER_UPDATE",
        "PLAYER_ALIVE", "PLAYER_DEAD", "PLAYER_UNGHOST", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    }
    for _, event in ipairs(events) do pcall(eventFrame.RegisterEvent, eventFrame, event) end
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_DISABLED" then U:UpdateMovers(); return end
        if event == "PLAYER_REGEN_ENABLED" then
            if U.pending or U.pendingMoves then U:ApplySettings() end
            U:UpdateMovers()
            U:RefreshAll(false)
            if RP.ClassResources then RP.ClassResources:Update() end
            RP:SyncNativeClassResources()
            -- A combat-restricted target may now allow 3D. Keep already loaded
            -- models running instead of restarting every portrait after a fight.
            for _, entry in pairs(U.frames) do
                if entry.enabled and not entry.portrait.modelReady and Exists(entry.unit) then
                    RP.Portraits:Refresh(entry.portrait)
                end
            end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            U:ApplySettings(); U:RefreshAll(true); return
        end
        if event == "PLAYER_TARGET_CHANGED" then
            if RP.Quest then RP.Quest:Forget("target") end
            U:RefreshUnit("target", true)
            U:RefreshPreviewPortrait("target")
            return
        end
        if event == "UNIT_PET" then
            U:RefreshUnit("pet", true)
            U:RefreshUnit("target", true)
            U:RefreshPreviewPortrait("pet")
            U:RefreshPreviewPortrait("target")
            return
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            U:RefreshUnit("player", true); U:RefreshPreviewPortrait("player"); return
        end
        if event == "PLAYER_LEVEL_UP" then
            if C_Timer and C_Timer.After then C_Timer.After(0, function() U:RefreshAll(false) end)
            else U:RefreshAll(false) end
            return
        end
        if event == "GROUP_ROSTER_UPDATE" then U:RefreshAll(false); return end
        if event == "GUILD_ROSTER_UPDATE" then U:RefreshAll(false); return end
        if event == "PLAYER_ALIVE" or event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" then
            U:RefreshUnit("player", true); return
        end
        if RP.IsSecret(unit) or type(unit) ~= "string" then return end
        if event == "UNIT_HEAL_PREDICTION" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
            for _, entry in pairs(U.frames) do
                if entry.enabled and entry.plate:IsShown() then
                    RP.Plates:UpdateHealPreview(entry.plate.healPreview, entry.unit)
                end
            end
            return
        end
        if unit == "targettarget" or (event == "UNIT_TARGET" and unit == "target") then
            U:RefreshTargetTarget(); return
        end
        if event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then U:RefreshPreviewPortrait(unit) end
        local entry = U.frames[unit]
        if not entry or not entry.enabled or not Exists(unit) then return end
        local p = entry.plate
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then RP.Plates:UpdateHealth(p)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER"
            or event == "UNIT_DISPLAYPOWER" then RP.Plates:UpdatePower(p)
        elseif event:find("UNIT_SPELLCAST", 1, true) then RP.Plates:UpdateCast(p)
        elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
            RP.Portraits:Refresh(entry.portrait)
        else
            U:RefreshUnit(unit, event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE")
        end
    end)
end
