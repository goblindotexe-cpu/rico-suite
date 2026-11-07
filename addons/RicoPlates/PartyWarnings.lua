-- A separate crimson warning rim. Restricted health is evaluated by the
-- client's percentage/curve API and sent directly to a native alpha sink.
local _, RP = ...
local W = { states=setmetatable({}, {__mode="k"}), fallback=setmetatable({}, {__mode="k"}) }
RP.PartyWarnings = W
local WHITE = "Interface\\Buttons\\WHITE8X8"
local unpack = unpack or table.unpack

local function Public(value) return RP.Readable(value) end
local function Number(value)
    return Public(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function Call(fn, ...)
    if type(fn)~="function" then return false end
    return pcall(fn, ...)
end
local function Read(fn, ...)
    local ok, value=Call(fn,...)
    if ok and Public(value) then return value end
end
local function Field(object,key)
    if not Public(object) or object==nil then return nil end
    local ok,value=pcall(function() return object[key] end)
    if ok and Public(value) then return value end
end
local function Threshold()
    local value=RP.db and RP.db.partyLowHealthThreshold
    return Number(value) and math.max(10,math.min(50,value)) or 25
end
local function Enabled()
    return RP.db and RP.db.enabled~=false and RP.db.partyFrames~=false and RP.db.partyLowHealth~=false
end
local function Token(state)
    local unit=state.entry and state.entry.unit
    if not Public(unit) then return nil end
    if not unit then
        unit=Read(Field(state.native,"GetUnit"),state.native) or Field(state.native,"displayedUnit")
            or Field(state.native,"unit") or Field(state.native,"unitToken")
    end
    return Public(unit) and type(unit)=="string" and (unit=="player" or unit:match("^party[1-4]$")) and unit or nil
end
local function Alive(unit)
    if Read(UnitExists,unit)~=true or Read(UnitIsConnected,unit)~=true then return false end
    if type(UnitIsDeadOrGhost)=="function" then return Read(UnitIsDeadOrGhost,unit)==false end
    return Read(UnitIsDead,unit)==false and Read(UnitIsGhost,unit)==false
end
local function Grouped(unit)
    if Read(IsInRaid)==true then return false end
    if type(IsInGroup)=="function" then return Read(IsInGroup)==true end
    if type(GetNumSubgroupMembers)=="function" then
        local count=Read(GetNumSubgroupMembers)
        return Number(count) and count>0
    end
    return Read(UnitInParty,unit)==true
end

local function Edge(parent, first, second, horizontal, offset, thickness, color)
    local texture=parent:CreateTexture(nil,"OVERLAY")
    texture:SetTexture(WHITE)
    texture:SetPoint(first,parent,first,first:find("LEFT",1,true) and -offset or offset,
        first:find("TOP",1,true) and offset or -offset)
    texture:SetPoint(second,parent,second,second:find("LEFT",1,true) and -offset or offset,
        second:find("TOP",1,true) and offset or -offset)
    if horizontal then texture:SetHeight(thickness) else texture:SetWidth(thickness) end
    texture:SetVertexColor(unpack(color))
    return texture
end

local function Pulse(frame)
    if type(frame.CreateAnimationGroup)~="function" then return nil end
    local ok,group=pcall(function()
        local animation=frame:CreateAnimationGroup()
        animation:SetLooping("REPEAT")
        for index,values in ipairs({{0.45,1},{1,0.45}}) do
            local alpha=animation:CreateAnimation("Alpha")
            alpha:SetOrder(index); alpha:SetDuration(0.6)
            alpha:SetFromAlpha(values[1]); alpha:SetToAlpha(values[2]); alpha:SetSmoothing("IN_OUT")
        end
        return animation
    end)
    return ok and group or nil
end

function W:Build(state,kind)
    local warning=self.states[state]
    if warning then return warning end
    -- Allocate only outside combat. PartyFrames creates/applies its visuals
    -- outside combat too, so normal health changes need no frame construction.
    if RP:IsInCombat() then return nil end
    local parent=kind=="standard" and state.visual or state.native
    if not parent or type(parent.CreateTexture)~="function" then return nil end
    local root=CreateFrame("Frame",nil,parent)
    root:SetAllPoints(parent); root:EnableMouse(false)
    local level=parent:GetFrameLevel()
    if state.entry then
        level=math.max(level,state.entry.plate.front:GetFrameLevel(),state.entry.portraitFront:GetFrameLevel())
    elseif state.front then level=math.max(level,state.front:GetFrameLevel()) end
    root:SetFrameLevel(level+3)
    local pulse=CreateFrame("Frame",nil,root); pulse:SetAllPoints(root); pulse:EnableMouse(false)
    local mask=CreateFrame("Frame",nil,pulse); mask:SetAllPoints(pulse); mask:EnableMouse(false)
    local colors={{0.57,0.005,0.045,0.25},{0.96,0.025,0.13,0.8},{1,0.30,0.39,1}}
    for _,segment in ipairs({{"TOPLEFT","TOPRIGHT",true},{"BOTTOMLEFT","BOTTOMRIGHT",true},
        {"TOPLEFT","BOTTOMLEFT",false},{"TOPRIGHT","BOTTOMRIGHT",false}}) do
        for index,color in ipairs(colors) do
            Edge(mask,segment[1],segment[2],segment[3],5-index,4-index,color)
        end
    end
    for _,corner in ipairs({"TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT"}) do
        for _,horizontal in ipairs({true,false}) do
            local texture=mask:CreateTexture(nil,"OVERLAY"); texture:SetTexture(WHITE)
            texture:SetPoint(corner,mask,corner,0,0); texture:SetSize(horizontal and 11 or 2,horizontal and 2 or 11)
            texture:SetVertexColor(1,0.52,0.59,1)
        end
    end
    warning={root=root,pulse=pulse,mask=mask,kind=kind,group=Pulse(pulse)}
    self.states[state]=warning
    root:SetScript("OnHide",function()
        if warning.group then warning.group:Stop() end
        W.fallback[state]=nil
        if W.worker and not next(W.fallback) then W.worker:Hide() end
    end)
    root:Hide()
    return warning
end

function W:Forget(state)
    local warning=self.states[state]
    self.fallback[state]=nil
    if warning then
        warning.unit,warning.mode=nil,nil
        if warning.group then warning.group:Stop() end
        warning.root:Hide()
    end
    if self.worker and not next(self.fallback) then self.worker:Hide() end
end

function W:Curve()
    local threshold=Threshold()
    if self.curve and self.curveThreshold==threshold then return self.curve end
    local create=C_CurveUtil and C_CurveUtil.CreateCurve
    if type(create)~="function" then return nil end
    local ok,curve=pcall(function()
        local value=create()
        if value.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then value:SetType(Enum.LuaCurveType.Step) end
        value:AddPoint(0,1); value:AddPoint(threshold/100,1)
        value:AddPoint(threshold/100+0.000001,0); value:AddPoint(1,0)
        return value
    end)
    if ok and curve then self.curve,self.curveThreshold=curve,threshold; return curve end
end

function W:NativeAlpha(unit)
    local curve=self:Curve()
    if not curve or type(UnitHealthPercent)~="function" then return false end
    local ok,value=pcall(UnitHealthPercent,unit,false,curve)
    if not ok then return false end
    if RP.IsSecret(value) then return true,value,true end
    if Number(value) and value>=0 and value<=1 then return true,value,false end
    return false
end

function W:Refresh(state,kind)
    if type(state)~="table" then return end
    local warning=self.states[state]
    if state.active and not warning then warning=self:Build(state,kind) end
    local unit=Token(state)
    if not warning or not Enabled() or not state.active or not unit or not Grouped(unit) or not Alive(unit)
        or not state.native:IsVisible() or (kind=="standard" and (not state.visual:IsVisible() or state.entry.plate.preview)) then
        self:Forget(state); return
    end
    local native,alpha,secret=self:NativeAlpha(unit)
    if not native then
        local health,maximum=Read(UnitHealth,unit),Read(UnitHealthMax,unit)
        if not Number(health) or not Number(maximum) or maximum<=0 or health<=0 or health>maximum
            or health/maximum*100>Threshold() then self:Forget(state); return end
        alpha=1
    elseif not secret and alpha==0 then self:Forget(state); return end
    -- Never inspect alpha after it reaches this sink: a secret percentage is
    -- not compared, stored as a count, or used to decide what Lua should run.
    local applied=pcall(warning.mask.SetAlpha,warning.mask,alpha)
    if not applied then self:Forget(state); return end
    warning.unit,warning.mode=unit,native and "native" or "public"
    warning.root:Show()
    if warning.group then
        if not warning.group:IsPlaying() then warning.group:Play() end
    else
        self.fallback[state]=kind
        self.worker:Show()
    end
end

function W:UpdateSettings()
    self:Initialize()
    local party=RP.PartyFrames
    if not party then return end
    for _,state in pairs(party.entries or {}) do self:Refresh(state,"standard") end
    for _,state in pairs(party.compact or {}) do self:Refresh(state,"compact") end
end

function W:Initialize()
    if self.initialized then return end
    self.initialized=true
    local worker=CreateFrame("Frame"); self.worker=worker; worker:Hide()
    worker:SetScript("OnUpdate",function(_,elapsed)
        W.elapsed=(W.elapsed or 0)+elapsed
        W.refreshElapsed=(W.refreshElapsed or 0)+elapsed
        if W.elapsed<0.05 then return end
        W.elapsed=0
        local refresh=W.refreshElapsed>=0.1
        if refresh then W.refreshElapsed=0 end
        local now=Read(GetTime)
        local alpha=Number(now) and (0.70+0.26*math.sin(now*5.2)) or 0.9
        for state,kind in pairs(W.fallback) do
            if refresh then W:Refresh(state,kind) end
            local warning=W.states[state]
            if W.fallback[state] and warning then warning.pulse:SetAlpha(alpha) end
        end
        if not next(W.fallback) then worker:Hide() end
    end)
    local party=RP.PartyFrames
    if party and type(hooksecurefunc)=="function" then
        hooksecurefunc(party,"RefreshStandard",function(_,state) W:Refresh(state,"standard") end)
        hooksecurefunc(party,"ApplyCompact",function(_,state) W:Refresh(state,"compact") end)
        for _,method in ipairs({"ClearStandard","HideCompact","ReleaseStandard","ReleaseCompact"}) do
            hooksecurefunc(party,method,function(_,state) W:Forget(state) end)
        end
    end
    local events=CreateFrame("Frame"); self.events=events
    for _,event in ipairs({"GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED"}) do events:RegisterEvent(event) end
    events:SetScript("OnEvent",function() W:UpdateSettings() end)
end
