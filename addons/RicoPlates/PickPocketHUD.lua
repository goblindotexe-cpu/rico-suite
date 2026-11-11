local _, RP = ...
local T = RP.Theme
local H = {}
RP.PickPocketHUD = H

local MIN_WIDTH, HEIGHT, COIN_SIZE = 108, 30, 12

local function CoinText(total)
    local format = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString
    if total > 0 and format then
        local ok, text = pcall(format, total, COIN_SIZE)
        if ok and RP.Readable(text) and type(text) == "string" and text ~= "" then return text end
    end

    local coins = {}
    local function Add(count, metal)
        coins[#coins + 1] = ("%d|TInterface\\MoneyFrame\\UI-%sIcon:%d:%d:1:0|t"):format(count, metal, COIN_SIZE, COIN_SIZE)
    end
    local gold, silver, copper = math.floor(total / 10000), math.floor(total / 100) % 100, total % 100
    if gold > 0 then Add(gold, "Gold") end
    if silver > 0 then Add(silver, "Silver") end
    if copper > 0 or total == 0 then Add(copper, "Copper") end
    return table.concat(coins, "   ")
end

local function ValidFraction(value)
    return type(value) == "number" and value >= 0 and value <= 1
end

function H:Place()
    if self.dragging then return end
    local frame, db = self.frame, self.db
    frame:ClearAllPoints()
    if ValidFraction(db.x) and ValidFraction(db.y) then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x * UIParent:GetWidth(), db.y * UIParent:GetHeight())
    else
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 145)
    end
end

function H:Refresh(total)
    local frame = self.frame
    local increased = self.lastTotal and total > self.lastTotal
    self.lastTotal = total
    frame.amount:SetText(CoinText(total))
    frame:SetWidth(math.max(MIN_WIDTH, math.ceil(frame.amount:GetStringWidth() + 34)))
    if increased and frame:IsVisible() then
        frame.coinFlash:Stop()
        frame.coinFlash:Play()
    end
end

local function HideTooltip(frame)
    if GameTooltip and GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

local function StopDrag(frame)
    if not H.dragging then return end
    frame:StopMovingOrSizing()
    H.dragging = nil
    local x, y = frame:GetCenter()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if x and y and width > 0 and height > 0 then
        H.db.x = math.max(0, math.min(1, x / width))
        H.db.y = math.max(0, math.min(1, y / height))
        H:Place()
    end
end

local function BuildFinish(frame)
    T:Panel(frame)
    frame.ricoBorder[1]:SetVertexColor(0.42, 0.53, 0.39, 1)
    frame.ricoBorder[2]:SetVertexColor(0.23, 0.18, 0.10, 1)

    local inset = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    inset:SetPoint("TOPLEFT", 2, -2)
    inset:SetPoint("BOTTOMRIGHT", -2, 2)
    inset:SetColorTexture(0.038, 0.075, 0.059, 1)
    if CreateColor and inset.SetGradient then
        inset:SetGradient("VERTICAL", CreateColor(0.014, 0.027, 0.021, 1), CreateColor(0.055, 0.100, 0.074, 1))
    end

    local trim = frame:CreateTexture(nil, "BORDER", nil, 1)
    trim:SetPoint("TOPLEFT", 7, -3)
    trim:SetPoint("TOPRIGHT", -7, -3)
    trim:SetHeight(1)
    trim:SetColorTexture(0.47, 0.75, 0.53, 0.58)
    if CreateColor and trim.SetGradient then
        trim:SetGradient("HORIZONTAL", CreateColor(0.34, 0.91, 0.64, 0.82), CreateColor(0.79, 0.57, 0.26, 0.40))
    end
    frame.trim = trim

    local flash = frame:CreateTexture(nil, "ARTWORK")
    flash:SetPoint("TOPLEFT", 3, -4)
    flash:SetPoint("BOTTOMRIGHT", -3, 3)
    flash:SetColorTexture(0.78, 0.57, 0.24, 0.24)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0)
    local pulse = frame:CreateAnimationGroup()
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetTarget(flash)
    fade:SetFromAlpha(0.82)
    fade:SetToAlpha(0)
    fade:SetDuration(0.65)
    fade:SetSmoothing("OUT")
    frame.coinFlash = pulse
end

function H:Build()
    local frame = CreateFrame("Frame", nil, UIParent)
    self.frame = frame
    frame:SetSize(MIN_WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    BuildFinish(frame)

    local amount = frame:CreateFontString(nil, "OVERLAY")
    frame.amount = amount
    amount:SetPoint("CENTER", 0, 0)
    amount:SetFont(T.font, 14, "")
    amount:SetTextColor(1.00, 0.94, 0.77)
    amount:SetShadowColor(0, 0, 0, 0.9)
    amount:SetShadowOffset(1, -1)

    frame:SetScript("OnDragStart", function(self)
        HideTooltip(self)
        H.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", StopDrag)
    frame:SetScript("OnEnter", function(self)
        if H.dragging or not GameTooltip then return end
        self.trim:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Pick Pocket")
        GameTooltip:AddLine("Total coin collected with Pick Pocket on this character.", 0.72, 0.83, 0.78, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        self.trim:SetAlpha(0.78)
        HideTooltip(self)
    end)
    frame:SetScript("OnHide", function(self)
        self.trim:SetAlpha(0.78)
        self.coinFlash:Stop()
        HideTooltip(self)
        StopDrag(self)
    end)
    UIParent:HookScript("OnSizeChanged", function() H:Place() end)
    frame.trim:SetAlpha(0.78)
    self:Place()
end

function H:UpdateSettings()
    if self.frame then self.frame:SetShown(RP.db.enabled) end
end

function H:Initialize()
    if self.frame or not RP.PickPocketMoney or not UnitClass then return end
    local _, class = UnitClass("player")
    if not RP.Readable(class) or class ~= "ROGUE" then return end
    if type(RicoPlatesPickPocketDB) ~= "table" then RicoPlatesPickPocketDB = {} end
    self.db = RicoPlatesPickPocketDB
    self:Build()
    RP.PickPocketMoney:Initialize(self.db, function(total) H:Refresh(total) end)
    self:Refresh(self.db.total or 0)
    self:UpdateSettings()
end
