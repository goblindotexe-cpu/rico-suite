local _, F = ...

local Audio = {}
F.BiteAudio = Audio

local events = CreateFrame("Frame")
local sessionEvents = {
    "VOICE_CHAT_AUDIO_CAPTURE_ENERGY",
    "VOICE_CHAT_ACTIVE_INPUT_DEVICE_UPDATED",
    "VOICE_CHAT_ACTIVE_OUTPUT_DEVICE_UPDATED",
    "VOICE_CHAT_ACTIVE_VOICE_PROVIDER_CHANGED",
    "VOICE_CHAT_CHANNEL_ACTIVATED",
    "VOICE_CHAT_CHANNEL_JOINED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_LEAVING_WORLD",
    "PLAYER_LOGOUT",
}

local function ReadableTable(value)
    return not F.IsSecret(value) and type(value) == "table"
        and (not canaccesstable or canaccesstable(value))
end

local function ActiveLoopback(voice)
    local ok, devices = F.Call(voice.GetAvailableInputDevices)
    if not ok or not ReadableTable(devices) then return end
    for _, device in ipairs(devices) do
        if ReadableTable(device) and not F.IsSecret(device.isActive) and device.isActive == true then
            local name = device.displayName
            if not F.PublicString(name) then return end
            name = name:lower():match("^%s*(.-)%s*$")
            if (name:match("^stereo[%s%-]*mix$") or name:match("^stereo[%s%-]*mix%s*%("))
                and F.PublicString(device.deviceID) and device.deviceID ~= "" then
                return device.deviceID
            end
            return
        end
    end
end

local function IsOutsideVoiceChannel(voice)
    local ok, channelID = F.Call(voice.GetActiveChannelID)
    return ok and not F.IsSecret(channelID) and channelID == nil
end

local function ClearSession()
    local session = Audio.session
    if not session then return end
    Audio.session = nil
    for _, event in ipairs(sessionEvents) do events:UnregisterEvent(event) end
    return session
end

function Audio:Stop()
    local session = ClearSession()
    if session then F.Call(session.voice.EndLocalCapture) end
end

function Audio:IsActive()
    return self.session ~= nil and self.session.samples > 0
end

local function StopWithMessage(message)
    Audio:Stop()
    F:Print(message)
end

local function MeasureEnergy(session, energy)
    if not F.Number(energy) or energy < 0 or energy > 1 then return end
    local now = GetTime()
    session.firstSampleAt = session.firstSampleAt or now
    session.samples = session.samples + 1
    local baseline = session.baseline or energy
    local rise = energy - baseline
    local warm = session.samples >= 5 and now - session.firstSampleAt >= 0.4
    local threshold = math.max(0.007, baseline * 0.6, session.deviation * 4)
    local peak = warm and rise >= threshold

    -- Learn the local noise level more slowly during peaks so the splash cannot erase its own signal.
    local weight = peak and 0.025 or 0.18
    session.baseline = baseline + weight * rise
    session.deviation = session.deviation + weight * (math.abs(rise) - session.deviation)
    local pulse = peak and not session.inPeak and now - session.lastPulseAt >= 0.45
    session.inPeak = peak
    if pulse then
        session.lastPulseAt = now
        session.callback(now)
    end
end

events:RegisterEvent("VOICE_CHAT_AUDIO_CAPTURE_STARTED")
events:RegisterEvent("VOICE_CHAT_AUDIO_CAPTURE_STOPPED")
events:SetScript("OnEvent", function(_, event, _, energy)
    local session = Audio.session
    if event == "VOICE_CHAT_AUDIO_CAPTURE_STOPPED" then
        Audio.externalCapture = false
        if session then
            ClearSession()
            F:Print("Bite audio ended because WoW stopped the local audio test.")
        end
    elseif event == "VOICE_CHAT_AUDIO_CAPTURE_STARTED" then
        if not session then
            Audio.externalCapture = true
        elseif ActiveLoopback(session.voice) ~= session.device or not IsOutsideVoiceChannel(session.voice) then
            StopWithMessage("Bite audio stopped because the voice input or channel changed.")
        end
    elseif session then
        if event == "VOICE_CHAT_AUDIO_CAPTURE_ENERGY" then
            MeasureEnergy(session, energy)
        elseif event == "VOICE_CHAT_ACTIVE_INPUT_DEVICE_UPDATED" then
            if ActiveLoopback(session.voice) ~= session.device then
                StopWithMessage("Bite audio stopped because the voice input changed.")
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            StopWithMessage("Bite audio stopped in combat. Use /rf bite on to enable it again.")
        elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
            Audio:Stop()
        else
            StopWithMessage("Bite audio stopped because the voice device, provider or channel changed.")
        end
    end
end)

function Audio:Start(callback)
    if type(callback) ~= "function" then return false, "Bite audio could not start." end
    if InCombatLockdown and InCombatLockdown() then return false, "Leave combat before enabling bite audio." end
    if self.session then
        self.session.callback = callback
        return true, "Bite audio is already enabled."
    end
    local voice = C_VoiceChat
    if not voice or type(voice.BeginLocalCapture) ~= "function" or type(voice.EndLocalCapture) ~= "function" then
        return false, "This client does not support the local audio test."
    end
    if self.externalCapture then return false, "Stop the existing WoW microphone test before enabling bite audio." end
    if not IsOutsideVoiceChannel(voice) then return false, "Leave your WoW voice channel before enabling bite audio." end
    local device = ActiveLoopback(voice)
    if not device then return false, "Select Stereo Mix as the active WoW voice input to enable bite audio." end
    local session = { voice = voice, device = device, callback = callback, samples = 0, deviation = 0,
        lastPulseAt = -math.huge }
    self.session = session
    for _, event in ipairs(sessionEvents) do events:RegisterEvent(event) end
    local ok, result = F.Call(voice.BeginLocalCapture, false)
    if not ok or F.IsSecret(result) or result == false then
        if self.session == session then ClearSession() end
        return false, "WoW could not start the local Stereo Mix test."
    end
    if self.session ~= session then return false, "WoW ended the local audio test during startup." end
    C_Timer.After(4, function()
        if Audio.session == session and session.samples == 0 then
            StopWithMessage("No audio levels reached WoW from Stereo Mix. Bite audio stopped.")
        end
    end)
    return true, "Bite audio enabled using local Stereo Mix."
end
