local _, F = ...
local B = {}
F.BiteDetector = B

local UNIT = "softinteract"
local BOBBER_ID = 35591
local SAMPLE_EVERY, FIND_EVERY = 0.05, 0.50
local CAST_SETTLE, MATCH_WINDOW, ALERT_DURATION = 0.9, 0.35, 2.0
local STILL, DIP, SIDEWAYS = 1.5, 4, 5

local function Read(fn, ...)
    local ok, value = F.Call(fn, ...)
    if ok and not F.IsSecret(value) then return value end
end

local function OwnBobber()
    local guid = Read(UnitGUID, UNIT)
    if not F.PublicString(guid) or tonumber(guid:match("^GameObject%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-")) ~= BOBBER_ID then
        return nil, "Waiting for your fishing bobber."
    end
    if Read(UnitIsOwnerOrControllerOfUnit, "player", UNIT) == true then return guid end
    local owner, player = Read(UnitOwnerGUID, UNIT), Read(UnitGUID, "player")
    if F.PublicString(owner) and owner ~= "" and owner == player then return guid end
    return nil, "WoW did not expose ownership of the bobber."
end

local function Measure(frame)
    if not frame or F.IsSecret(frame) then return end
    local ok, x, y = pcall(function()
        if frame:IsShown() then return frame:GetLeft(), frame:GetTop() end
    end)
    if ok and F.Number(x) and F.Number(y) then return x, y end
end

local function MatchesBobber(frame, guid)
    if not frame or F.IsSecret(frame) then return false end
    local ok, unit = pcall(function()
        local unitFrame = frame.UnitFrame or frame
        return unitFrame.GetUnit and unitFrame:GetUnit() or unitFrame.unitToken or unitFrame.unit
    end)
    return ok and F.PublicString(unit) and Read(UnitGUID, unit) == guid
end

local function FindFrame(guid)
    local plate = Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit, UNIT)
    if Measure(plate) then return plate, true end
    if not WorldFrame then return end
    local ok, children = pcall(function() return {WorldFrame:GetChildren()} end)
    if not ok then return end
    -- A frame name or texture alone cannot identify the player's bobber.
    local found
    for _, frame in ipairs(children) do
        if MatchesBobber(frame, guid) and Measure(frame) then
            if found and found ~= frame then return end
            found = frame
        end
    end
    return found, false
end

local function FrameStillMatches(frame, native, guid)
    if native then return Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit, UNIT) == frame end
    return MatchesBobber(frame, guid)
end

local function CameraMoving(previousZoom)
    local zoom = Read(GetCameraZoom)
    local speed = Read(GetUnitSpeed, "player")
    local moved = (F.Number(zoom) and F.Number(previousZoom) and zoom ~= previousZoom)
        or (F.Number(speed) and speed > 0)
        or Read(IsMouseButtonDown, "LeftButton") == true or Read(IsMouseButtonDown, "RightButton") == true
    return moved, zoom
end

function B:ResetMotion()
    self.x, self.y, self.stillSamples, self.dipSamples = nil, nil, 0, 0
    self.motionAt, self.audioAt = nil, nil
end

function B:SetBite(confirmed)
    if self.confirmed == confirmed then return end
    self.confirmed = confirmed
    if F.warningsReady then F.Warnings:RefreshPrompt() end
    F:QueueRefresh()
end

function B:EndCast()
    if self.worker then self.worker:SetScript("OnUpdate", nil) end
    if self.castAt then self.lastCast = { audio = self.sawAudio, motion = self.sawMotion } end
    self.castAt, self.channelGUID, self.guid, self.frame, self.zoom = nil, nil, nil, nil, nil
    self.alertAt, self.sawAudio, self.sawMotion = nil, nil, nil
    self:ResetMotion()
    self:SetBite(false)
end

function B:IsBite()
    return self.confirmed == true and F.OneKey and F.OneKey.mode == "reel"
        and F.BiteAudio:IsActive() or false
end

function B:RecordMotion(x, y, now)
    if not self.x or math.abs(x - self.x) > SIDEWAYS then
        self:ResetMotion()
        self.x, self.y, self.stillSamples = x, y, 1
        return
    end
    local drop = self.y - y
    if self.stillSamples >= 3 and drop >= DIP then
        -- Keep the resting height through the dip and require a second low sample.
        self.dipSamples = self.dipSamples + 1
        if self.dipSamples == 2 then self.motionAt, self.sawMotion = now, true end
        return
    end
    self.dipSamples = 0
    self.stillSamples = math.abs(drop) <= STILL and math.min(3, self.stillSamples + 1) or 1
    self.x, self.y = x, y
end

function B:Sample(now)
    if not F.BiteAudio:IsActive() then
        self:ResetMotion()
        self:SetBite(false)
        return
    end
    local guid, reason = OwnBobber()
    if guid ~= self.guid then
        self.guid, self.frame, self.nextFind = guid, nil, 0
        self:ResetMotion()
        self:SetBite(false)
    end
    if not guid then self.visualStatus = reason; return end

    if self.frame and not FrameStillMatches(self.frame, self.nativeFrame, guid) then
        self.frame, self.nextFind = nil, now + FIND_EVERY
        self:ResetMotion()
        self:SetBite(false)
    end
    local x, y = Measure(self.frame)
    if not x and now >= self.nextFind then
        self.frame, self.nativeFrame = FindFrame(guid)
        self.nextFind = now + FIND_EVERY
        x, y = Measure(self.frame)
    end
    if not x then
        self.visualStatus = "WoW did not expose a measurable frame for your bobber."
        self:ResetMotion()
        self:SetBite(false)
        return
    end
    self.visualStatus = "Measuring your bobber."
    if self.alertAt then
        if now - self.alertAt >= ALERT_DURATION then self:SetBite(false) end
        return
    end
    local moving, zoom = CameraMoving(self.zoom)
    self.zoom = zoom
    if moving then self:ResetMotion(); return end
    self:RecordMotion(x, y, now)
    local motion, sound = self.motionAt, self.audioAt
    if motion and sound and now - motion <= MATCH_WINDOW and now - sound <= MATCH_WINDOW
        and math.abs(motion - sound) <= MATCH_WINDOW then
        self.alertAt = now
        self:SetBite(true)
    end
end

local function Tick(_, elapsed)
    B.elapsed = B.elapsed + elapsed
    if B.elapsed < SAMPLE_EVERY then return end
    B.elapsed = 0
    local now = GetTime()
    if B.castAt and now - B.castAt >= CAST_SETTLE then B:Sample(now) end
end

function B:Sync()
    local binding = F.OneKey
    if not (self.armed and F.db.fishingPrompt and binding and binding.mode == "reel") then
        if self.castAt then self:EndCast() end
        return
    end
    if self.castAt and self.channelGUID == binding.channelGUID then return end
    self:EndCast()
    self.castAt, self.channelGUID, self.nextFind, self.elapsed = GetTime(), binding.channelGUID, 0, 0
    self.visualStatus = "Waiting for your fishing bobber."
    self.worker = self.worker or CreateFrame("Frame")
    self.worker:SetScript("OnUpdate", Tick)
end

function B:Command(argument)
    argument = argument:lower()
    if argument == "off" then
        self.armed = false
        self:EndCast()
        F.BiteAudio:Stop()
        F:Print("Bite alert off.")
        return
    end
    if argument == "on" then
        local ok, message = F.BiteAudio:Start(function(now)
            if B.castAt and now - B.castAt >= CAST_SETTLE then B.audioAt, B.sawAudio = now, true end
        end)
        if ok then self.armed = true; self:Sync() end
        F:Print(message)
        return
    end
    F:Print("Bite alert: " .. (F.BiteAudio:IsActive() and "Stereo Mix active. " or "Stereo Mix inactive. ")
        .. (self.visualStatus or "Cast Fishing to check the bobber frame."))
    local cast = self.castAt and { audio = self.sawAudio, motion = self.sawMotion } or self.lastCast
    if cast then
        F:Print("Cast measurements: bobber dip " .. (cast.motion and "yes" or "no")
            .. ", sound pulse " .. (cast.audio and "yes" or "no") .. ".")
    end
    F:Print("Use /rf bite on to start the local Stereo Mix test, or /rf bite off to stop it.")
end
