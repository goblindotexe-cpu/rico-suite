local _, RP = ...
local T = RP.Theme
local H = {}
RP.PickPocketHUD = H

local unpack = unpack or table.unpack

local function CoinText(total)
    local format = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString
    if total > 0 and format then
        local ok, text = pcall(format, total, 11)
        if ok and RP.Readable(text) and type(text) == "string" and text ~= "" then return text end
    end

    local coins = {}
    local function Add(count, metal)
        coins[#coins + 1] = ("%d|TInterface\\MoneyFrame\\UI-%sIcon:11:11:1:0|t"):format(count, metal)
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
    frame.amount:SetText(CoinText(total))
    frame:SetWidth(math.max(86, math.ceil(frame.amount:GetStringWidth() + 22)))
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

function H:Build()
    local frame = CreateFrame("Frame", nil, UIParent)
    self.frame = frame
    frame:SetSize(86, 24)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    T:Panel(frame)

    local amount = frame:CreateFontString(nil, "OVERLAY")
    frame.amount = amount
    amount:SetPoint("CENTER", 0, 0)
    amount:SetFont(T.font, 12, "")
    amount:SetTextColor(unpack(T.colors.text))
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
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Pick Pocket")
        GameTooltip:AddLine("Total coin collected with Pick Pocket on this character.", 0.72, 0.83, 0.78, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", HideTooltip)
    frame:SetScript("OnHide", function(self)
        HideTooltip(self)
        StopDrag(self)
    end)
    UIParent:HookScript("OnSizeChanged", function() H:Place() end)
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
