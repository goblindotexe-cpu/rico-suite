local _, RP = ...
local A = {}
RP.QuestTrackerNative = A

local unpack = unpack or table.unpack

local function Locked()
    if not InCombatLockdown then return false end
    local ok, locked = pcall(InCombatLockdown)
    return not ok or RP.IsSecret(locked) or locked == true or locked == 1
end

local function Move(manager, module, container)
    local ok = pcall(manager.SetModuleContainer, manager, module, container)
    return ok and manager:GetContainerForModule(module) == container and container:HasModule(module)
end

local function Ignore() end

local function CreateParking(manager, container)
    -- The Blizzard container template calls ManagedFrameMixin:OnShow during creation.
    -- A hidden holder needs the module registry methods, but no managed layout.
    local parking = CreateFrame("Frame", nil, UIParent)
    parking:Hide()
    parking.modules = {}
    parking.AddModule = container.AddModule
    parking.RemoveModule = container.RemoveModule
    parking.HasModule = container.HasModule
    parking.RemoveAllModules = container.RemoveAllModules
    -- Parked native modules retain their watch/collapse state without laying out invisible blocks.
    parking.OnAdded, parking.SetBackgroundAlpha = Ignore, Ignore
    parking.MarkDirty, parking.Update, parking.ForceExpand, parking.ForEachModule = Ignore, Ignore, Ignore, Ignore
    parking.HasAnyModules = function() return false end
    parking.IsCollapsed = function() return true end
    manager:AddContainer(parking)
    return parking
end

local function CreateHost(container)
    local ok, host = pcall(CreateFrame, "Frame", nil, container, "ObjectiveTrackerModuleTemplate")
    if not ok or not host.Header or not host.MarkDirty then return end
    host:Hide()
    host.Header:Hide()
    host.GetContentsHeight = function(self) return self.ricoUsedHeight or 0 end
    host.IsTruncated = function() return false end
    host.Update = function(self, availableHeight)
        local height = self.ricoViewHeight or 0
        local collapsed = self.parentContainer:IsCollapsed()
        local show = height > 0 and availableHeight >= height and not collapsed
        -- Keep the native All Objectives header available for re-expansion.
        local usedHeight = collapsed and height > 0 and self.headerHeight or (show and height or 0)
        local resize = usedHeight > 0 and self:GetHeight() ~= usedHeight
        local visibilityChanged = self:IsShown() ~= show
        if (resize or visibilityChanged) and Locked() and self:IsProtected() then
            return self:GetContentsHeight(), false
        end
        if resize then self:SetHeight(usedHeight) end
        if visibilityChanged then self:SetShown(show) end
        self.ricoUsedHeight = usedHeight
        return usedHeight, false
    end
    return host
end

function A:LayoutChanged(frame)
    local attachment = self.attachment
    if not attachment or attachment.frame ~= frame then return false end
    local host = attachment.host
    local height = frame:IsShown() and frame:GetHeight() or 0
    if host.ricoViewHeight == height then return true end
    if Locked() then return false end
    host.ricoViewHeight = height
    host:MarkDirty()
    return true
end

function A:Detach(frame)
    local attachment = self.attachment
    if not attachment or attachment.frame ~= frame then return true end
    if Locked() then return false, "combat" end

    local manager, container, parking, host = attachment.manager, attachment.container, attachment.parking, attachment.host
    attachment.attached = nil
    host:Hide()
    host.ricoViewHeight, host.ricoUsedHeight = nil, nil
    if manager:GetContainerForModule(host) == container and not Move(manager, host, parking) then return false end
    for _, module in ipairs(attachment.stock) do
        if manager:GetContainerForModule(module) == parking then
            if not Move(manager, module, container) then return false end
            module:MarkDirty()
        end
    end

    if frame:GetParent() == host then
        frame:SetParent(attachment.parent)
        frame:ClearAllPoints()
        for _, point in ipairs(attachment.points) do frame:SetPoint(unpack(point, 1, 5)) end
    end
    self.attachment = nil
    container:MarkDirty()
    return true
end

function A:Attach(frame)
    local questie = rawget(_G, "Questie")
    local profile = questie and questie.IsForever and questie.db and questie.db.profile
    if profile and profile.trackerEnabled == true then
        local restored, reason = self:Detach(frame)
        return false, restored and "questie" or reason or "pending"
    end
    if self.attachment then
        if self.attachment.frame ~= frame then return false, "managed" end
        if self.attachment.attached then
            self:LayoutChanged(frame)
            return true
        end
        local restored, reason = self:Detach(frame)
        if not restored then return false, reason or "pending" end
    end

    local manager, container = ObjectiveTrackerManager, ObjectiveTrackerFrame
    if not (QuestObjectiveTracker or CampaignQuestObjectiveTracker) then return false, "unavailable" end
    if not (manager and manager.GetContainerForModule and manager.SetModuleContainer and manager.AddContainer
        and container and container.AddModule and container.RemoveModule and container.HasModule
        and container.RemoveAllModules and container.MarkDirty) then return false, "pending" end
    if Locked() then return false, "combat" end

    local stock, order = {}, math.huge
    for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }) do
        local module = _G[name]
        if module then
            local owner = manager:GetContainerForModule(module)
            if not owner or not owner:HasModule(module) or type(module.uiOrder) ~= "number" then return false, "pending" end
            if owner ~= container then return false, "managed" end
            stock[#stock + 1] = module
            order = math.min(order, module.uiOrder)
        end
    end

    self.parking = self.parking or CreateParking(manager, container)
    self.host = self.host or CreateHost(container)
    local parking, host = self.parking, self.host
    if not parking or not host then return false, "pending" end
    host.uiOrder = order

    local points = {}
    for index = 1, frame:GetNumPoints() do points[index] = { frame:GetPoint(index) } end
    self.attachment = { frame = frame, parent = frame:GetParent(), points = points, manager = manager,
        container = container, parking = parking, host = host, stock = stock }
    for _, module in ipairs(stock) do
        if not Move(manager, module, parking) then self:Detach(frame); return false, "pending" end
    end
    if not Move(manager, host, container) then self:Detach(frame); return false, "pending" end

    frame:SetParent(host)
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    self.attachment.attached = true
    self:LayoutChanged(frame)
    return true
end
