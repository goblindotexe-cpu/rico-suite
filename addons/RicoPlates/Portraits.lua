local _, RP = ...
local Portraits = {}
RP.Portraits = Portraits

local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local RETRY_DELAYS = {0.15, 0.4, 1.0}

-- PlayerModel:SetUnit requires declassified unit identity on Forever. Only use
-- the caller's fixed HUD tokens; never substitute a GUID or creature displayID.
local function ValidUnit(unit)
    if RP.IsSecret(unit) or type(unit) ~= "string" then return false end
    return unit == "player" or unit == "target" or unit == "pet" or unit:match("^party[1-4]$") ~= nil
end

local function Call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false end
    return pcall(object[method], object, ...)
end

local function Exists(unit)
    if not ValidUnit(unit) or type(UnitExists) ~= "function" then return false end
    local ok, exists = pcall(UnitExists, unit)
    return ok and not RP.IsSecret(exists) and exists == true
end

local function Visible(widget)
    local method = widget.IsVisible and "IsVisible" or "IsShown"
    local ok, visible = Call(widget, method)
    return ok and not RP.IsSecret(visible) and visible == true
end

local function Settings()
    local d = RP.db or RP.defaults or {}
    local use3D = not RP.IsSecret(d.unitPortrait3D) and d.unitPortrait3D ~= false
    local zoom = d.unitPortraitZoom
    if RP.IsSecret(zoom) or type(zoom) ~= "number" then zoom = 0.85 end
    return use3D, math.max(0.5, math.min(1, zoom))
end

local function CancelRetry(widget)
    if widget.retryTimer then Call(widget.retryTimer, "Cancel") end
    widget.retryTimer, widget.retryPending = nil, false
end

local function ResetModel(widget)
    widget.accepted, widget.modelReady, widget.loadSeen = false, false, false
    if widget.model then
        Call(widget.model, "SetAlpha", 0)
        Call(widget.model, "Hide")
        Call(widget.model, "ClearModel")
    end
end

local function Fallback(widget, unit)
    widget.portrait:SetTexture(UNKNOWN)
    widget.portrait:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    widget.mode = "unknown"
    if Exists(unit) and type(SetPortraitTexture) == "function" then
        -- The third argument disables the default circular mask; our HUD owns
        -- the rectangular iron frame. No texture identity is read back in Lua.
        local ok = pcall(SetPortraitTexture, widget.portrait, unit, true)
        if ok then widget.mode = "portrait" end
    end
    widget.portrait:Show()
end

local function ApplyCamera(widget)
    local model = widget.model
    -- The portrait camera chooses the model's head/shoulders. RefreshCamera or
    -- SetCamera(0) here can reset that choice to the full-body scene camera.
    -- Map the zoom control to the portrait range; do not inspect unit bounds.
    local zoomOK = Call(model, "SetPortraitZoom", 0.90 + (widget.zoom - 0.50) * 0.20)
    Call(model, "SetPosition", 0, 0, 0)
    if not Call(model, "SetFacing", 0) then Call(model, "SetRotation", 0, false) end
    return zoomOK
end

function Portraits:FinishLoading(widget, fromEvent)
    if not widget.unit or not widget.accepted or not widget.use3D or not Visible(widget) then
        return false
    end
    if fromEvent then widget.loadSeen = true end
    local loaded = widget.loadSeen
    if not loaded then
        local ok, fileID = Call(widget.model, "GetModelFileID")
        loaded = ok and not RP.IsSecret(fileID) and type(fileID) == "number" and fileID > 0
    end
    if not loaded or not ApplyCamera(widget) then return false end

    -- Native animation 0 is the normal idle animation used by Blizzard's model
    -- helpers. We do not rotate, seek, or update the model every rendered frame.
    local firstReady = not widget.modelReady
    if firstReady or fromEvent then Call(widget.model, "SetAnimation", 0, 0) end
    Call(widget.model, "Show")
    Call(widget.model, "SetAlpha", 1)
    widget.portrait:Hide()
    widget.modelReady, widget.mode = true, "model"
    if firstReady and C_Timer and C_Timer.After then
        -- Some models publish their portrait camera on the next rendered frame.
        local generation = widget.generation
        C_Timer.After(0, function()
            if widget.generation == generation and widget.modelReady and Visible(widget) then ApplyCamera(widget) end
        end)
    end
    CancelRetry(widget)
    return true
end

function Portraits:TryModel(widget)
    if not widget.model or not widget.use3D or not Exists(widget.unit) or not Visible(widget) then
        return false
    end
    if widget.accepted then return self:FinishLoading(widget) end

    ResetModel(widget)
    -- A shown transparent model can finish loading without flashing a prior
    -- target or exposing an unframed full-body model behind the 2D fallback.
    Call(widget.model, "Show")
    widget.binding = true
    local ok, success = Call(widget.model, "SetUnit", widget.unit, false)
    widget.binding = false
    if not ok or RP.IsSecret(success) or success ~= true then
        -- Identity restrictions may return nothing or error. Do not hammer a
        -- denied API; a later portrait/world/model event can explicitly retry.
        widget.denied = not ok or RP.IsSecret(success) or success ~= false
        ResetModel(widget)
        return false
    end
    widget.accepted, widget.denied = true, false
    return self:FinishLoading(widget)
end

function Portraits:ScheduleRetry(widget)
    if widget.retryPending or widget.denied or widget.modelReady or not widget.model
        or not widget.use3D or not Visible(widget) or not Exists(widget.unit) then return end
    local nextRetry = (widget.retryCount or 0) + 1
    local delay = RETRY_DELAYS[nextRetry]
    if not delay or not C_Timer then return end
    local generation = widget.generation
    local function Retry()
        if widget.generation ~= generation then return end
        widget.retryTimer, widget.retryPending = nil, false
        if not Visible(widget) or not Exists(widget.unit) then return end
        if not self:TryModel(widget) then self:ScheduleRetry(widget) end
    end
    widget.retryCount, widget.retryPending = nextRetry, true
    if type(C_Timer.NewTimer) == "function" then
        widget.retryTimer = C_Timer.NewTimer(delay, Retry)
    elseif type(C_Timer.After) == "function" then
        C_Timer.After(delay, Retry)
    else
        widget.retryPending = false
    end
end

function Portraits:Create(parent)
    local widget = CreateFrame("Frame", nil, parent)
    widget:EnableMouse(false)
    widget.generation, widget.retryCount = 0, 0
    widget.mode, widget.modelReady = "unknown", false

    widget.background = widget:CreateTexture(nil, "BACKGROUND")
    widget.background:SetAllPoints(widget)
    widget.background:SetColorTexture(1, 1, 1, 1)
    if widget.background.SetGradient and CreateColor then
        widget.background:SetGradient("VERTICAL", CreateColor(0.012, 0.024, 0.019, 1), CreateColor(0.065, 0.12, 0.083, 1))
    else widget.background:SetColorTexture(0.024, 0.045, 0.032, 1) end
    widget.portrait = widget:CreateTexture(nil, "ARTWORK")
    widget.portrait:SetAllPoints(widget)
    Fallback(widget)

    local viewport = CreateFrame("Frame", nil, widget)
    viewport:SetPoint("TOPLEFT", widget, "TOPLEFT", 3, -3)
    viewport:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -3, 3)
    viewport:SetClipsChildren(true)
    viewport:EnableMouse(false)
    widget.viewport = viewport
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, viewport)
    if ok and model and type(model.SetUnit) == "function" and type(model.SetPortraitZoom) == "function" then
        widget.model = model
        model:EnableMouse(false)
        model:SetAllPoints(viewport)
        Call(model, "SetKeepModelOnHide", false)
        Call(model, "SetDoBlend", false)
        model:SetScript("OnModelLoaded", function()
            if not widget.unit or not widget.use3D or not Visible(widget) then return end
            -- SetUnit may deliver OnModelLoaded synchronously. Wait until its
            -- public success result has been checked before displaying anything.
            if widget.binding then widget.loadSeen = true; return end
            Portraits:FinishLoading(widget, true)
        end)
        ResetModel(widget)
    elseif ok and model then
        Call(model, "Hide")
    end

    widget:SetScript("OnHide", function()
        widget.generation = widget.generation + 1
        CancelRetry(widget)
        ResetModel(widget)
        Fallback(widget)
        widget.suspended = true
    end)
    widget:SetScript("OnShow", function()
        if widget.unit then Portraits:SetUnit(widget, widget.unit, true) end
    end)
    return widget
end

function Portraits:SetUnit(widget, unit, forceRefresh)
    if not widget then return end
    if not ValidUnit(unit) then self:Clear(widget); return end
    local use3D, zoom = Settings()
    local sameBinding = widget.unit == unit and widget.use3D == use3D and not widget.suspended
    if sameBinding and not forceRefresh then
        if widget.zoom ~= zoom then
            widget.zoom = zoom
            if widget.modelReady then ApplyCamera(widget) end
        end
        return
    end

    widget.generation = widget.generation + 1
    CancelRetry(widget)
    ResetModel(widget)
    widget.unit, widget.use3D, widget.zoom = unit, use3D, zoom
    widget.retryCount, widget.denied, widget.suspended = 0, false, false
    Fallback(widget, unit)
    if not use3D or not Exists(unit) or not Visible(widget) then return end
    if not self:TryModel(widget) then self:ScheduleRetry(widget) end
end

function Portraits:Refresh(widget)
    if widget and widget.unit then self:SetUnit(widget, widget.unit, true) end
end

function Portraits:ApplySettings(widget)
    if widget and widget.unit then self:SetUnit(widget, widget.unit) end
end

function Portraits:Clear(widget)
    if not widget then return end
    widget.generation = widget.generation + 1
    CancelRetry(widget)
    widget.unit, widget.denied, widget.suspended = nil, false, false
    widget.retryCount = 0
    ResetModel(widget)
    Fallback(widget)
end
