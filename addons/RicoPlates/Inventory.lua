local _, RP = ...

local Inventory = {
    headers = setmetatable({}, { __mode = "k" }),
    bodies = setmetatable({}, { __mode = "k" }),
    slots = setmetatable({}, { __mode = "k" }),
    bagnonHooks = setmetatable({}, { __mode = "k" }),
}
RP.Inventory = Inventory

local function ReadableFrame(frame)
    if not RP.Readable(frame) then return false end
    local kind = type(frame)
    return (kind == "table" or kind == "userdata") and type(frame.IsShown) == "function"
        and RP.CanUseFrame(frame)
end

local function InCombat()
    return InCombatLockdown and RP.PublicTrue(InCombatLockdown())
end

local function BagnonInventory()
    local bagnon = _G.Bagnon
    if type(bagnon) ~= "table" then return nil, false end
    local frames = bagnon.Frames
    if type(frames) ~= "table" or type(frames.IsEnabled) ~= "function"
        or type(frames.Get) ~= "function" or type(frames.Show) ~= "function"
        or type(frames.Hide) ~= "function" then
        return nil, true
    end
    local ok, enabled = pcall(frames.IsEnabled, frames, "inventory")
    if not ok or not RP.Readable(enabled) then return nil, true end
    if enabled then return frames, false end
    return nil, false
end

local function GetBagnonFrame(frames)
    local ok, frame = pcall(frames.Get, frames, "inventory")
    if ok and ReadableFrame(frame) then return frame end
end

local function Outline(frame, layer, sublevel, inset, light, shade)
    local top = frame:CreateTexture(nil, layer, nil, sublevel)
    top:SetColorTexture(light[1], light[2], light[3], 1)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    top:SetHeight(1)

    local bottom = frame:CreateTexture(nil, layer, nil, sublevel)
    bottom:SetColorTexture(shade[1], shade[2], shade[3], 1)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    bottom:SetHeight(1)

    local left = frame:CreateTexture(nil, layer, nil, sublevel)
    left:SetColorTexture(shade[1], shade[2], shade[3], 1)
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
    left:SetWidth(1)

    local right = frame:CreateTexture(nil, layer, nil, sublevel)
    right:SetColorTexture(shade[1], shade[2], shade[3], 1)
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
    right:SetWidth(1)
end

function Inventory:PaintBody(frame)
    if self.bodies[frame] then return end

    local background = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    background:SetColorTexture(0.018, 0.035, 0.029, 1)
    background:SetAllPoints()
    self.bodies[frame] = background
    Outline(frame, "BORDER", 2, 0, {0.27, 0.43, 0.36}, {0.18, 0.29, 0.24})
    Outline(frame, "BORDER", 2, 1, {0.07, 0.13, 0.10}, {0.05, 0.09, 0.075})
end

function Inventory:PaintSlot(button, icon, stockNormal, empty)
    if stockNormal and stockNormal ~= icon then stockNormal:SetAlpha(0) end

    local skin = self.slots[button]
    if not skin then
        local well = button:CreateTexture(nil, "ARTWORK", nil, 4)
        well:SetColorTexture(0.048, 0.087, 0.069, 1)
        well:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        well:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        Outline(button, "ARTWORK", 5, 0, {0.06, 0.11, 0.09}, {0.035, 0.06, 0.05})
        Outline(button, "ARTWORK", 5, 1, {0.25, 0.41, 0.33}, {0.12, 0.22, 0.18})
        skin = { empty = well }
        self.slots[button] = skin
    end
    skin.empty:SetShown(empty == true)
end

function Inventory:PaintBagnonSlot(button)
    local icon = button.icon or button.Icon
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    local empty = not RP.PublicTrue(button.hasItem)
    self:PaintSlot(button, icon, normal, empty)
    -- Keep Bagnon's optional bag-family colors in the new empty slot fill.
    if empty and normal and normal.GetVertexColor then
        local r, g, b = normal:GetVertexColor()
        local gray = math.min(r, g, b)
        self.slots[button].empty:SetColorTexture(
            0.048 + (r - gray) * 0.20, 0.087 + (g - gray) * 0.20, 0.069 + (b - gray) * 0.20, 1)
    end
end

function Inventory:SkinBagnonBody(frame)
    -- Bagnon's skin frame also receives mouse events for the bag window.
    if frame.skin and frame.skin.SetAlpha then frame.skin:SetAlpha(0) end
    self:PaintBody(frame)

    if hooksecurefunc and not self.bagnonHooks[frame] and type(frame.UpdateVisuals) == "function" then
        hooksecurefunc(frame, "UpdateVisuals", function(shown) self:Skin(shown, true) end)
        self.bagnonHooks[frame] = true
    end

    local group = frame.ItemGroup
    if not group or type(group.buttons) ~= "table" then return end
    if hooksecurefunc and not self.bagnonHooks[group] and type(group.Layout) == "function" then
        hooksecurefunc(group, "Layout", function() self:Skin(frame, true) end)
        self.bagnonHooks[group] = true
    end
    for _, button in ipairs(group.buttons) do
        if hooksecurefunc and not self.bagnonHooks[button] and type(button.Update) == "function" then
            hooksecurefunc(button, "Update", function(slot) self:PaintBagnonSlot(slot) end)
            self.bagnonHooks[button] = true
        end
        self:PaintBagnonSlot(button)
    end
end

function Inventory:Skin(frame, bagnon)
    if not ReadableFrame(frame) or not frame:IsShown() then return end
    if InCombat() then
        self.pendingSkin = true
        return
    end

    if bagnon then
        self:SkinBagnonBody(frame)
    elseif self.SkinNativeBody then
        self:SkinNativeBody(frame)
    end
    if self.headers[frame] then return end

    -- The existing title area leaves the close button, controls and item
    -- grid untouched. Bagnon's title is a button that also owns its drag
    -- and search interactions, so only its font string is made transparent.
    local titleArea = bagnon and frame.Title or frame.TitleContainer
    if not ReadableFrame(titleArea) then return end
    local titleText
    if bagnon then
        titleText = titleArea.GetFontString and titleArea:GetFontString()
    else
        titleText = titleArea.TitleText
    end
    if not titleText or not titleText.SetAlpha or not RP.Theme or not RP.Theme.Header then return end

    local header = RP.Theme:Header(titleArea, "INVENTORY", { height = 20, fontSize = 12 })
    header:SetPoint("TOPLEFT", titleArea, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", titleArea, "TOPRIGHT", 0, 0)
    header:SetFrameLevel(titleArea:GetFrameLevel() + 1)
    titleText:SetAlpha(0)
    self.headers[frame] = header
end

function Inventory:HookBagnon(frames)
    if self.bagnonFrames ~= frames and hooksecurefunc then
        hooksecurefunc(frames, "Show", function(provider, id)
            if id == "inventory" then self:Skin(GetBagnonFrame(provider), true) end
        end)
        self.bagnonFrames = frames
    end
    self:Skin(GetBagnonFrame(frames), true)
end

function Inventory:HookNative()
    local frame = _G.ContainerFrameCombinedBags
    if not ReadableFrame(frame) then return nil end
    if self.nativeFrame ~= frame then
        frame:HookScript("OnShow", function(shown) self:Skin(shown, false) end)
        self.nativeFrame = frame
    end
    self:Skin(frame, false)
    return frame
end

local function UsingCombinedBags()
    local manager = _G.ContainerFrameSettingsManager
    if manager and type(manager.IsUsingCombinedBags) == "function" then
        return RP.PublicTrue(manager:IsUsingCombinedBags())
    end
    local getter = C_CVar and C_CVar.GetCVarBool or GetCVarBool
    return getter and RP.PublicTrue(getter("combinedBags")) or false
end

function Inventory:EnableCombinedBags()
    if UsingCombinedBags() then return true end
    if InCombat() then return false end
    -- Match the client's own Convert to Combined Bags command.
    local setter = SetCVar or C_CVar and C_CVar.SetCVar
    if not setter or not pcall(setter, "combinedBags", "1") then return false end
    return UsingCombinedBags()
end

function Inventory:Setup()
    local frames, pendingProvider = BagnonInventory()
    if frames then
        self:HookBagnon(frames)
        return
    end
    if pendingProvider or not self:HookNative() then return end
    if InCombat() then
        self.pendingSetup = true
    elseif not self.nativeConfigured then
        self.nativeConfigured = self:EnableCombinedBags()
    end
end

function Inventory:Fail(message)
    RP:Print(message)
    return false
end

function Inventory:Toggle(force)
    if InCombat() then return self:Fail("Open Rico Inventory after combat.") end
    if not self.events then self:Initialize() end

    local frames, pendingProvider = BagnonInventory()
    if frames then
        self:HookBagnon(frames)
        local frame = GetBagnonFrame(frames)
        if frame and frame:IsShown() then
            if force ~= true then frames:Hide("inventory") end
            return true
        end
        frame = frames:Show("inventory")
        if not ReadableFrame(frame) or not frame:IsShown() then return self:Fail("Bagnon inventory is unavailable.") end
        self:Skin(frame, true)
        return true
    end
    if pendingProvider then return self:Fail("Bagnon inventory is still loading.") end

    local frame = self:HookNative()
    if not frame or not OpenBackpack or not CloseBackpack then
        return self:Fail("Combined bags are unavailable on this client.")
    end
    local wasShown = frame:IsShown()
    if not self:EnableCombinedBags() then
        return self:Fail("Combined bags are unavailable on this client.")
    end
    if frame:IsShown() then
        if wasShown and force ~= true then CloseBackpack() end
    else
        OpenBackpack()
        if not frame:IsShown() then return self:Fail("The inventory cannot open here.") end
    end
    return true
end

function Inventory:Initialize()
    if self.events then return end
    local events = CreateFrame("Frame")
    self.events = events
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event, addon)
        if event == "PLAYER_REGEN_ENABLED" then
            if self.pendingSetup or self.pendingSkin then
                self.pendingSetup, self.pendingSkin = nil, nil
                self:Setup()
            end
        elseif event == "PLAYER_ENTERING_WORLD" or addon == "Bagnon" or addon == "Blizzard_UIPanels_Game" then
            self:Setup()
        end
    end)

    SLASH_RICOINVENTORY1, SLASH_RICOINVENTORY2 = "/ri", "/ricoinventory"
    SlashCmdList.RICOINVENTORY = function() self:Toggle() end
    self:Setup()
end
