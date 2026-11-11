local _, RP = ...
local I = { views = {} }
RP.QuestTrackerItems = I

local function Locked()
    if not InCombatLockdown then return false end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not RP.Readable(value) or RP.PublicTrue(value)
end

local function ItemForQuest(quest)
    local indexForID = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
    if not quest or not indexForID or not GetQuestLogSpecialItemInfo then return end
    local ok, index = pcall(indexForID, quest.id)
    if not ok or not RP.Readable(index) or type(index) ~= "number" or index < 1 then return end
    local found, link, texture, charges, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, index)
    if not found or not RP.Readable(link) or type(link) ~= "string"
        or (quest.complete and not RP.PublicTrue(showWhenComplete)) then return end
    local id = tonumber(link:match("|Hitem:(%d+)") or link:match("^item:(%d+)"))
    if not id or id < 1 then return end
    if not RP.Readable(texture) or not texture then texture = "Interface\\Icons\\INV_Misc_QuestionMark" end
    if not RP.Readable(charges) or type(charges) ~= "number" or charges <= 1 then charges = nil end
    return id, texture, charges, index, link
end

local function HideTooltip(view)
    if GameTooltip and GameTooltip:IsOwned(view) then GameTooltip:Hide() end
end

local function ShowTooltip(view)
    if not GameTooltip or not view.link then return end
    GameTooltip:SetOwner(view, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink(view.link)
    if Locked() then
        GameTooltip:AddLine("Click to use after combat", 0.66, 0.79, 0.74)
    end
    GameTooltip:Show()
end

local function Highlight(view, active)
    view.highlight:SetShown(active)
    if active then ShowTooltip(view) else HideTooltip(view) end
end

local function RefreshCooldown(view)
    local start, duration, enabled
    if view.index and GetQuestLogSpecialItemCooldown then
        local ok
        ok, start, duration, enabled = pcall(GetQuestLogSpecialItemCooldown, view.index)
        if not ok then start = nil end
    end
    local active = RP.Readable(start) and type(start) == "number"
        and RP.Readable(duration) and type(duration) == "number" and duration > 0 and RP.PublicTrue(enabled)
    if active then view.cooldown:SetCooldown(start, duration) end
    view.cooldown:SetShown(active)
end

local function CreateAction(view)
    if not RegisterStateDriver then return end
    if not I.actionRoot then
        local root = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        root:Hide()
        root:SetAttribute("_onstate-ricocombat", [[
            if newstate == "combat" then self:Hide() end
        ]])
        RegisterStateDriver(root, "ricocombat", "[combat] combat; peace")
        I.actionRoot = root
        root:Show()
    end
    -- Keep the protected action outside the native tracker's frame and anchor chains.
    local action = CreateFrame("Button", nil, I.actionRoot, "SecureActionButtonTemplate")
    action:Hide()
    action:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    action:EnableMouseWheel(view.onWheel ~= nil)
    action:SetScript("OnMouseWheel", view.onWheel)
    action:SetScript("OnEnter", function() Highlight(view, true) end)
    action:SetScript("OnLeave", function() Highlight(view, false) end)
    action:SetScript("OnHide", function() Highlight(view, false) end)
    action:SetScript("PreClick", function(self)
        if not Locked() then
            local expected = view:IsVisible() and view:IsMouseOver() and view.itemID == self.itemID
            self:SetAttribute("type1", expected and "item" or nil)
        end
    end)
    view.action = action
    return action
end

local function SyncAction(view)
    if Locked() then return end
    local action = view.action
    local x, y
    if view.itemID and view:IsVisible() then x, y = view:GetCenter() end
    if not x or not y then
        if action and action:IsShown() then action:Hide() end
        return
    end
    action = action or CreateAction(view)
    if not action then return end
    local scale = view:GetEffectiveScale() / UIParent:GetEffectiveScale()
    x, y = x * scale, y * scale
    if action.x ~= x or action.y ~= y or action.scale ~= scale then
        action.x, action.y, action.scale = x, y, scale
        action:SetSize(view:GetWidth() * scale, view:GetHeight() * scale)
        action:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end
    local strata, level = view:GetFrameStrata(), view:GetFrameLevel() + 1
    if action.strata ~= strata then action.strata = strata; action:SetFrameStrata(strata) end
    if action.level ~= level then action.level = level; action:SetFrameLevel(level) end
    if action.itemID ~= view.itemID then
        action.itemID = view.itemID
        action:SetAttribute("type1", "item")
        action:SetAttribute("item1", "item:" .. view.itemID)
    end
    if not action:IsShown() then action:Show() end
end

local function Tick(view, elapsed)
    view.elapsed = view.elapsed + elapsed
    if view.elapsed >= 0.10 then
        view.elapsed = 0
        SyncAction(view)
    end
end

local function OnEvent(_, event)
    for _, view in ipairs(I.views) do
        if event == "BAG_UPDATE_COOLDOWN" then
            if view:IsVisible() then RefreshCooldown(view) end
        elseif view:IsVisible() then
            view.icon:SetDesaturated(Locked())
            if GameTooltip and GameTooltip:IsShown() and GameTooltip:IsOwned(view) then ShowTooltip(view) end
            SyncAction(view)
        elseif event == "PLAYER_REGEN_ENABLED" then
            SyncAction(view)
        end
    end
    if event == "PLAYER_REGEN_ENABLED" and I.actionRoot and not Locked() then I.actionRoot:Show() end
end

function I:Create(row, onWheel)
    local view = CreateFrame("Button", nil, row)
    view:Hide()
    view:SetSize(21, 21)
    view.onWheel, view.elapsed = onWheel, 0
    view:EnableMouseWheel(onWheel ~= nil)
    view:SetScript("OnMouseWheel", onWheel)
    view:SetScript("OnEnter", function(self) Highlight(self, true) end)
    view:SetScript("OnLeave", function(self) Highlight(self, false) end)
    view:SetScript("OnHide", function(self) Highlight(self, false); SyncAction(self) end)
    view:SetScript("OnShow", function(self) RefreshCooldown(self); SyncAction(self) end)
    view:SetScript("OnUpdate", Tick)

    view.icon = view:CreateTexture(nil, "ARTWORK")
    view.icon:SetAllPoints()
    view.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local cooldown = CreateFrame("Cooldown", nil, view, "CooldownFrameTemplate")
    cooldown:SetAllPoints(view)
    cooldown:EnableMouse(false)
    cooldown:Hide()
    view.cooldown = cooldown
    local theme = RP.Theme
    theme:Border(view)
    view.count = view:CreateFontString(nil, "OVERLAY")
    view.count:SetFont(theme.font, 9, "OUTLINE")
    view.count:SetPoint("BOTTOMRIGHT", -2, 1)
    view.highlight = view:CreateTexture(nil, "HIGHLIGHT")
    view.highlight:SetColorTexture(0.39, 0.93, 0.68, 0.23)
    view.highlight:SetAllPoints()
    view.highlight:Hide()
    self.views[#self.views + 1] = view
    if not self.events then
        local events = CreateFrame("Frame")
        self.events = events
        events:RegisterEvent("BAG_UPDATE_COOLDOWN")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:SetScript("OnEvent", OnEvent)
    end
    return view
end

function I:Update(view, quest)
    local id, texture, charges, index, link = ItemForQuest(quest)
    local changed = view.itemID ~= id or view.index ~= index or view.link ~= link
    view.itemID, view.index, view.link = id, index, link
    if not id then
        if view:IsShown() then view:Hide() end
        SyncAction(view)
        return
    end
    if view.texture ~= texture then view.texture = texture; view.icon:SetTexture(texture) end
    if view.charges ~= charges then view.charges = charges; view.count:SetText(charges or "") end
    view.icon:SetDesaturated(Locked())
    if not view:IsShown() then view:Show() end
    if changed then
        RefreshCooldown(view)
        if GameTooltip and GameTooltip:IsShown() and GameTooltip:IsOwned(view) then ShowTooltip(view) end
    end
    SyncAction(view)
end
