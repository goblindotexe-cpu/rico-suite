-- Party styling reuses Blizzard's secure member buttons and pooled lifecycle.
-- It never replaces party targeting/menu handlers or touches raid containers.
local _, RP = ...
local P = { entries = setmetatable({}, {__mode="k"}), compact = setmetatable({}, {__mode="k"}),
    standardHooks = setmetatable({}, {__mode="k"}), failedStandardBuilds = setmetatable({}, {__mode="k"}), errors=0 }
RP.PartyFrames = P
local WHITE = "Interface\\Buttons\\WHITE8X8"
local unpack = unpack or table.unpack

local function Public(value) return RP.Readable(value) end
local function Number(value) return Public(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function Call(fn, ...) if type(fn)~="function" then return false end; return pcall(fn, ...) end
local function Field(object,key)
    if not Public(object) or object==nil then return nil end
    local ok,value=pcall(function() return object[key] end)
    if ok and Public(value) then return value end
end
local function Object(object)
    if not Public(object) or (type(object)~="table" and type(object)~="userdata") then return false end
    local forbidden=Field(object,"IsForbidden")
    if type(forbidden)=="function" then local ok,value=Call(forbidden,object); return ok and Public(value) and value==false end
    return type(Field(object,"SetAlpha"))=="function"
end
local function Read(object,method,...)
    local ok,value=Call(Field(object,method),object,...)
    if ok and Public(value) then return value end
end
local function Combat() return RP:IsInCombat() end
local function Enabled() return RP.db and RP.db.enabled and RP.db.partyFrames~=false end
local function PartyUnit(unit)
    return Public(unit) and type(unit)=="string" and (unit=="player" or unit:match("^party[1-4]$"))
end
local function IsRaid() local ok,value=Call(IsInRaid); return ok and Public(value) and value==true end
local function CurrentUnit(frame)
    local unit=Read(frame,"GetUnit") or Field(frame,"displayedUnit") or Field(frame,"unit") or Field(frame,"unitToken")
    return PartyUnit(unit) and unit or nil
end
local function Exists(unit) local ok,value=Call(UnitExists,unit); return ok and RP.PublicTrue(value) end

local function ClearRange(state)
    if state.range then state.range:Hide() end
end

local function RangeAlpha(region,value,whenTrue,whenFalse)
    if not Public(value) then return Call(Field(region,"SetAlphaFromBoolean"),region,value,whenTrue,whenFalse) end
    region:SetAlpha(value and whenTrue or whenFalse)
    return true
end

local function UpdateRange(state,health,unit)
    if not Enabled() or RP.db.healerRange==false or not state.active or not unit or unit=="player"
        or Read(state.native,"IsVisible")~=true then ClearRange(state); return end
    local ok,inRange,checked=Call(UnitInRange,unit)
    if not ok or (Public(checked) and checked~=true) or (Public(inRange) and inRange~=false) then
        ClearRange(state); return
    end
    local fill=Read(health,"GetStatusBarTexture")
    if not Object(fill) then ClearRange(state); return end
    if not state.range then
        local frame=CreateFrame("Frame",nil,health)
        frame:EnableMouse(false); frame:SetFrameLevel(health:GetFrameLevel()+2)
        local shade=frame:CreateTexture(nil,"OVERLAY")
        shade:SetAllPoints(frame); shade:SetColorTexture(.01,.018,.025,.40)
        state.range,state.rangeShade=frame,shade
    end
    if state.rangeFill~=fill then
        state.range:ClearAllPoints(); state.range:SetAllPoints(fill)
        state.rangeFill=fill
    end
    -- The two alpha layers combine a valid range check with an out-of-range
    -- result inside the UI engine. Health text and names sit above the shade.
    if RangeAlpha(state.range,checked,1,0) and RangeAlpha(state.rangeShade,inRange,0,1) then
        state.range:Show()
    else ClearRange(state) end
end

function P:RefreshRange()
    for _,state in pairs(self.entries) do
        UpdateRange(state,state.entry.plate.health,CurrentUnit(state.native))
    end
    for _,state in pairs(self.compact) do
        UpdateRange(state,state.health,CurrentUnit(state.native))
    end
end

function P:Error(message)
    self.errors=self.errors+1
    self.lastError=Public(message) and type(message)=="string" and message:sub(1,180) or "Party appearance could not be applied."
end

local function InstallStandardHook(object,method,callback)
    local hooks=P.standardHooks[object]
    if not hooks then hooks={}; P.standardHooks[object]=hooks end
    if hooks[method] then return true end
    local ok=Call(hooksecurefunc,object,method,callback)
    if ok then hooks[method]=true end
    return ok
end

local function SnapshotAlpha(state,object)
    if not Object(object) or state.alphaMap[object] then return end
    local before=Read(object,"GetAlpha")
    if not Number(before) then error("Native party artwork alpha is unavailable.",0) end
    local property={object=object,before=before}
    state.alphaMap[object]=property; state.alphas[#state.alphas+1]=property
    local frame=state.native
    local ok=InstallStandardHook(object,"SetAlpha",function(region,alpha)
        local owner=P.entries[frame]
        if not owner or not owner.active or P.writingAlpha then return end
        local tracked=owner.alphaMap[region]
        if not tracked then return end
        if Number(alpha) then tracked.before=alpha end
        P.writingAlpha=true; pcall(region.SetAlpha,region,0); P.writingAlpha=false
    end)
    if not ok then error("Native party artwork could not be tracked.",0) end
end

local function HidePortrait(state)
    state.writingPortrait=true
    local ok=pcall(state.portrait.Hide,state.portrait)
    state.writingPortrait=false
    return ok
end

local function TrackPortrait(state)
    local frame=state.native
    local function OnVisibility(region,shown)
        local owner=P.entries[frame]
        if not owner or not owner.active or owner.portrait~=region or owner.writingPortrait or not Public(shown) then return end
        owner.portraitShown=shown and true or false
        if shown then HidePortrait(owner) end
    end
    local portrait=state.portrait
    if not InstallStandardHook(portrait,"Show",function(region) OnVisibility(region,true) end)
        or not InstallStandardHook(portrait,"Hide",function(region) OnVisibility(region,false) end)
        or not InstallStandardHook(portrait,"SetShown",OnVisibility) then
        error("Native party portrait visibility could not be tracked.",0)
    end
end

local function SnapshotMouse(state,object)
    if not Object(object) or state.mouseMap[object] then return end
    state.mouseMap[object]=true
    for _,kind in ipairs({"Click","Motion"}) do
        local getter,setter="IsMouse"..kind.."Enabled","SetMouse"..kind.."Enabled"
        local before=Read(object,getter)
        if type(before)=="boolean" and type(Field(object,setter))=="function" then
            state.mouse[#state.mouse+1]={object=object,getter=getter,setter=setter,before=before}
        end
    end
end

local function SnapshotPoints(state,object)
    if not Object(object) or state.pointMap[object] then return end
    local count=Read(object,"GetNumPoints")
    if not Number(count) or count>8 then return end
    local points={}
    for index=1,count do
        local values={pcall(object.GetPoint,object,index)}
        if not values[1] then return end
        table.remove(values,1)
        for _,value in ipairs(values) do if not Public(value) then return end end
        points[#points+1]=values
    end
    local property={object=object,points=points}
    state.pointMap[object]=property; state.points[#state.points+1]=property
end

local function Place(state,object,point,relative,relativePoint,x,y)
    if not Object(object) then return end
    SnapshotPoints(state,object)
    local property=state.pointMap[object]
    if not property then return end
    object:ClearAllPoints(); object:SetPoint(point,relative,relativePoint,x,y)
    property.applied={point,relative,relativePoint,x,y}
end

local function Raise(state,object,level)
    if not Object(object) or type(Field(object,"SetFrameLevel"))~="function" then return end
    local property=state.levelMap[object]
    if not property then
        local before=Read(object,"GetFrameLevel")
        if not Number(before) then return end
        property={object=object,before=before}; state.levelMap[object]=property; state.levels[#state.levels+1]=property
    else
        local current=Read(object,"GetFrameLevel")
        if property.applied and Number(current) and current~=property.applied then property.before=current end
    end
    object:SetFrameLevel(level); property.applied=level
end

local function OwnPoints(property)
    if Read(property.object,"GetNumPoints")~=1 then return false end
    local got={pcall(property.object.GetPoint,property.object,1)}
    if not got[1] then return false end
    for index=1,5 do if not Public(got[index+1]) or got[index+1]~=property.applied[index] then return false end end
    return true
end

local function StyleFont(state,object,size)
    if not Object(object) or type(Field(object,"SetFont"))~="function" then return end
    local property=state.fontMap[object]
    if not property then
        local values={pcall(object.GetFont,object)}
        if not values[1] or not Public(values[2]) or type(values[2])~="string" or not Number(values[3]) then return end
        property={object=object,font=values[2],size=values[3],flags=values[4] or ""}
        state.fontMap[object]=property; state.fonts[#state.fonts+1]=property
    end
    object:SetFont(RP.Theme.font,size or property.size,"OUTLINE")
    property.appliedFont,property.appliedSize=RP.Theme.font,size or property.size
end

function P:NativeIndicators(state)
    local frame,entry=state.native,state.entry
    local overlay=Field(frame,"PartyMemberOverlay")
    local indicatorLevel=entry.plate.front:GetFrameLevel()+6
    Raise(state,overlay,indicatorLevel)
    for _,key in ipairs({"ReadyCheck","NotPresentIcon","PowerBarAlt","PetFrame","AuraFrameContainer"}) do
        Raise(state,Field(frame,key),indicatorLevel+1)
    end
    Place(state,Field(overlay,"LeaderIcon"),"TOPRIGHT",entry.portrait,"TOPRIGHT",-2,3)
    Place(state,Field(overlay,"GuideIcon"),"TOPRIGHT",entry.portrait,"TOPRIGHT",-2,3)
    Place(state,Field(overlay,"RoleIcon"),"BOTTOMRIGHT",entry.portrait,"BOTTOMRIGHT",-2,2)
    Place(state,Field(overlay,"PVPIcon"),"TOPLEFT",entry.portrait,"TOPRIGHT",4,-2)
    Place(state,Field(frame,"ReadyCheck"),"CENTER",entry.portrait,"CENTER",0,0)
    Place(state,Field(frame,"NotPresentIcon"),"LEFT",entry.plate,"RIGHT",7,0)
    Place(state,Field(frame,"PowerBarAlt"),"TOPLEFT",entry.plate,"TOPRIGHT",7,0)
    Place(state,Field(frame,"PetFrame"),"TOPLEFT",state.visual,"BOTTOMLEFT",23,-3)
    -- Existing aura buttons keep their own secret-aware updates and hover.
    Place(state,Field(frame,"AuraFrameContainer"),"TOPLEFT",entry.plate.cast,"BOTTOMLEFT",0,-4)
    local container=Field(frame,"AuraFrameContainer")
    local ok,children=Call(function() return {container:GetChildren()} end)
    if ok and type(children)=="table" then
        for _,child in ipairs(children) do
            if Object(child) then
                if not child.ricoPartyBorder then child.ricoPartyBorder=RP.Theme:Panel(child) end
                StyleFont(state,Field(child,"Count"),10)
            end
        end
    end
end

function P:BuildStandard(frame)
    local existing=self.entries[frame]
    if existing then return existing end
    if self.failedStandardBuilds[frame] then return nil end
    local health=Field(frame,"HealthBarContainer")
    local portrait=Field(frame,"Portrait")
    if not Object(health) or not Object(portrait) or not Object(Field(frame,"Name")) then
        return nil,"This party frame layout is not supported; the native frame was preserved."
    end
    local unit=CurrentUnit(frame)
    if not unit then return nil end
    local state={native=frame,portrait=portrait,alphas={},alphaMap={},mouse={},mouseMap={},points={},pointMap={},fonts={},fontMap={},levels={},levelMap={}}
    local ok,reason=pcall(function()
        state.width,state.height=Read(frame,"GetWidth"),Read(frame,"GetHeight")
        if not Number(state.width) or not Number(state.height) then error("Native party frame dimensions are unavailable.",0) end
        -- Blizzard repaints the portrait's vertex alpha during health updates.
        -- Its visibility can be owned independently while it keeps updating.
        TrackPortrait(state)
        for _,key in ipairs({"Texture","VehicleTexture","Flash","Name","ResurrectableIndicator","HealthBarContainer","ManaBar"}) do
            SnapshotAlpha(state,Field(frame,key))
        end
        local nativeOverlay=Field(frame,"PartyMemberOverlay")
        SnapshotAlpha(state,Field(nativeOverlay,"Status")); SnapshotAlpha(state,Field(nativeOverlay,"Disconnect"))
        SnapshotMouse(state,health); SnapshotMouse(state,Field(health,"HealthBar")); SnapshotMouse(state,Field(frame,"ManaBar"))
        local visual=CreateFrame("Frame",nil,frame)
        state.visual=visual
        visual:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0); visual:EnableMouse(false)
        visual:SetFrameLevel(frame:GetFrameLevel()+6)
        state.entry=RP.UnitFrames:CreateVisual(visual,"party"..(Field(frame,"layoutIndex") or 1),false)
        state.entry.nativeAuras=true
        state.entry.unit=unit
        state.entry.partyFrame=true
        state.entry.enabled=true
        state.entry.nativeButton=frame
        visual:Hide()
    end)
    if not ok then
        if state.visual then
            -- Keep the native frame usable and leave the incomplete visual hidden.
            -- Retrying its constructor would allocate another set of child frames.
            self.failedStandardBuilds[frame]=true
            pcall(state.visual.Hide,state.visual)
        end
        return nil,reason
    end
    self.entries[frame]=state
    frame:HookScript("OnShow",function() P:QueueApply() end)
    frame:HookScript("OnHide",function() P:ClearStandard(state) end)
    frame:HookScript("OnEnter",function()
        if state.active and state.entry.enabled then
            if GameTooltip then GameTooltip:Hide() end
            RP.UnitFrames:ShowUnitTooltip(state.entry)
            local buffs=rawget(_G,"PartyMemberBuffTooltip")
            if Object(buffs) and Read(buffs,"IsShown")==true and RP.UnitFrames.unitTooltip then
                buffs:ClearAllPoints(); buffs:SetPoint("TOPLEFT",RP.UnitFrames.unitTooltip,"BOTTOMLEFT",0,-4)
                if not buffs.ricoPartyPanel then buffs.ricoPartyPanel=RP.Theme:Panel(buffs) end
                buffs.ricoPartyPanel:SetVertexColor(0.014,0.022,0.018,1)
            end
        end
    end)
    frame:HookScript("OnLeave",function() if state.entry then RP.UnitFrames:HideUnitTooltip(state.entry) end end)
    if type(Field(frame,"UpdateArt"))=="function" then pcall(hooksecurefunc,frame,"UpdateArt",function() P:QueueApply() end) end
    return state
end

function P:ClearStandard(state)
    ClearRange(state)
    if state.entry then state.entry.enabled=false; RP.UnitFrames:ClearVisuals(state.entry) end
    if state.visual then state.visual:Hide() end
end

function P:RefreshStandard(state,portrait)
    local unit=CurrentUnit(state.native)
    local pendingDisable=Combat() and state.active and not Enabled()
    if pendingDisable then self.pending=true end
    if state.active and ((not Enabled() and not pendingDisable) or not unit) then
        self:ReleaseStandard(state); return
    end
    if not state.active or IsRaid() or not unit or not Exists(unit) or not state.native:IsVisible() then
        self:ClearStandard(state); return
    end
    local changed=state.entry.unit~=unit
    state.entry.unit,state.entry.enabled=unit,true
    state.visual:Show()
    RP.UnitFrames:RefreshVisual(state.entry,portrait or changed)
    -- Forced Edit Mode previews can use player; this is still a party slot.
    RP.Plates:SetColor(state.entry.plate,"party")
    UpdateRange(state,state.entry.plate.health,unit)
end

function P:ApplyStandard(state)
    if Combat() then self.pending=true; return false end
    local entry,frame=state.entry,state.native
    if not state.active then
        state.portraitShown=Read(state.portrait,"IsShown")
        if type(state.portraitShown)~="boolean" then error("Native party portrait visibility is unavailable.",0) end
        state.points,state.pointMap,state.fonts,state.fontMap,state.levels,state.levelMap={},{},{},{},{},{}
        for _,property in ipairs(state.alphas) do
            local before=Read(property.object,"GetAlpha")
            if Number(before) then property.before=before end
        end
        for _,property in ipairs(state.mouse) do
            local before=Read(property.object,property.getter)
            if type(before)=="boolean" then property.before=before end
        end
        state.width,state.height=Read(frame,"GetWidth"),Read(frame,"GetHeight")
        state.appliedWidth,state.appliedHeight=nil,nil
    end
    RP.UnitFrames:LayoutVisual(entry)
    local scale=RP.db.partyFrameScale or 0.8
    state.visual:SetSize(entry.width,entry.height); state.visual:SetScale(scale)
    local width,height=entry.width*scale,entry.height*scale
    local currentWidth,currentHeight=Read(frame,"GetWidth"),Read(frame,"GetHeight")
    if state.appliedWidth and currentWidth~=state.appliedWidth and Number(currentWidth) then state.width=currentWidth end
    if state.appliedHeight and currentHeight~=state.appliedHeight and Number(currentHeight) then state.height=currentHeight end
    frame:SetSize(width,height); state.appliedWidth,state.appliedHeight=width,height
    for _,property in ipairs(state.mouse) do property.object[property.setter](property.object,false) end
    self:NativeIndicators(state)
    state.active=true
    if not HidePortrait(state) then error("Native party portrait could not be hidden.",0) end
    self.writingAlpha=true
    for _,property in ipairs(state.alphas) do property.object:SetAlpha(0) end
    self.writingAlpha=false
    self:RefreshStandard(state,true)
    return true
end

local function RestoreFonts(state)
    for _,property in ipairs(state.fonts) do
        local ok,font,size=pcall(property.object.GetFont,property.object)
        if ok and Public(font) and Public(size) and font==property.appliedFont and size==property.appliedSize then
            pcall(property.object.SetFont,property.object,property.font,property.size,property.flags)
        end
    end
end

function P:ReleaseStandard(state)
    if not state.active and not state.restorePending then return end
    local wasActive=state.active
    state.active=false
    self:ClearStandard(state)
    if wasActive then pcall(state.portrait.SetShown,state.portrait,state.portraitShown) end
    for _,property in ipairs(state.alphas) do
        if Read(property.object,"GetAlpha")==0 then pcall(property.object.SetAlpha,property.object,property.before) end
    end
    if Combat() then state.restorePending=true; self.pending=true; return end
    for _,property in ipairs(state.mouse) do
        if Read(property.object,property.getter)==false then pcall(property.object[property.setter],property.object,property.before) end
    end
    for _,property in ipairs(state.points) do
        if property.applied and OwnPoints(property) then
            property.object:ClearAllPoints()
            for _,point in ipairs(property.points) do property.object:SetPoint(unpack(point)) end
        end
    end
    for _,property in ipairs(state.levels) do
        if Read(property.object,"GetFrameLevel")==property.applied then property.object:SetFrameLevel(property.before) end
    end
    if Read(state.native,"GetWidth")==state.appliedWidth and Read(state.native,"GetHeight")==state.appliedHeight then
        state.native:SetSize(state.width,state.height)
    end
    RestoreFonts(state)
    state.restorePending=false
end

local function BarTexture(bar)
    local texture=Read(bar,"GetStatusBarTexture")
    return texture and Read(texture,"GetTexture"),texture
end

local function CaptureBarAppearance(bar)
    local file,region=BarTexture(bar)
    if not region then return nil end
    local atlas=Read(region,"GetAtlas")
    if type(atlas)~="string" or atlas=="" then atlas=nil end
    if type(file)~="string" and not Number(file) then file=nil end
    if file==nil and atlas==nil then return nil end
    local values={pcall(function() return region:GetTexCoord() end)}
    local coordinates
    if values[1] and (#values==5 or #values==9) then
        table.remove(values,1)
        local valid=true
        for _,value in ipairs(values) do if not Number(value) then valid=false; break end end
        if valid then coordinates=values end
    end
    return {file=file,atlas=atlas,coordinates=coordinates}
end

local function RestoreBarAppearance(bar,appearance)
    if not Object(bar) or not appearance then return end
    if appearance.file~=nil then pcall(bar.SetStatusBarTexture,bar,appearance.file) end
    local region=Read(bar,"GetStatusBarTexture")
    if not Object(region) then return end
    if appearance.atlas and type(Field(region,"SetAtlas"))=="function" then pcall(region.SetAtlas,region,appearance.atlas) end
    if appearance.coordinates then pcall(region.SetTexCoord,region,unpack(appearance.coordinates)) end
end

function P:BuildCompact(frame)
    if self.compact[frame] then return self.compact[frame] end
    local health,power=Field(frame,"healthBar"),Field(frame,"powerBar")
    if not Object(health) or type(Field(health,"GetStatusBarTexture"))~="function" then return nil end
    local texture,region=BarTexture(health)
    if not region then return nil end
    local healthAppearance=CaptureBarAppearance(health)
    if not healthAppearance then return nil end
    local colors={pcall(health.GetStatusBarColor,health)}
    if not colors[1] or not Number(colors[2]) or not Number(colors[3]) or not Number(colors[4]) then return nil end
    local powerTexture=Object(power) and BarTexture(power) or nil
    local state={native=frame,health=health,power=power,texture=texture,powerTexture=powerTexture,
        healthAppearance=healthAppearance,powerAppearance=Object(power) and CaptureBarAppearance(power) or nil,
        color={colors[2],colors[3],colors[4],colors[5] or 1},fonts={},fontMap={},parents={}}
    local clip=CreateFrame("Frame",nil,health); clip:EnableMouse(false); clip:SetClipsChildren(true)
    clip:SetPoint("TOPLEFT",region,"TOPLEFT"); clip:SetPoint("BOTTOMRIGHT",region,"BOTTOMRIGHT")
    clip:SetFrameLevel(health:GetFrameLevel()+1)
    state.clip=clip
    state.liquid=RP.Theme:Liquid(clip,{health=true,manual=true,width=health:GetWidth(),height=health:GetHeight(),bubbleCount=2,bubbleScale=0.75})
    local front=CreateFrame("Frame",nil,health); front:EnableMouse(false); front:SetAllPoints(health)
    front:SetFrameLevel(health:GetFrameLevel()+3); state.front=front
    state.trim=RP.Plates:CreateIronTrim(front)
    if RP.Plates.BuildHealPreview then state.healPreview=RP.Plates:BuildHealPreview(health,true) end
    clip:Hide(); front:Hide()
    if type(hooksecurefunc)=="function" then
        pcall(hooksecurefunc,health,"SetStatusBarColor",function(bar,r,g,b,a)
            if not state.active or P.paintingCompact then return end
            if Number(r) and Number(g) and Number(b) then state.color={r,g,b,Number(a) and a or 1} end
            P:PaintCompact(state)
        end)
        pcall(hooksecurefunc,health,"SetStatusBarTexture",function(bar,value)
            if not state.active or P.paintingCompact then return end
            if Public(value) and (type(value)=="number" or type(value)=="string") then state.texture=value end
            state.healthAppearance=CaptureBarAppearance(bar) or state.healthAppearance
            P:PaintCompact(state)
        end)
        if Object(power) and state.powerAppearance then
            pcall(hooksecurefunc,power,"SetStatusBarTexture",function(bar)
                if not state.active or P.paintingCompact then return end
                state.powerAppearance=CaptureBarAppearance(bar) or state.powerAppearance
                P:PaintCompact(state)
            end)
        end
    end
    self.compact[frame]=state
    frame:HookScript("OnShow",function() P:QueueApply() end)
    frame:HookScript("OnHide",function() P:HideCompact(state) end)
    return state
end

function P:PaintCompact(state)
    if not state.active then return end
    self.paintingCompact=true
    local color=RP.colors.party
    state.health:SetStatusBarTexture(WHITE); state.health:SetStatusBarColor(color[1],color[2],color[3],1)
    if Object(state.power) and state.powerAppearance then pcall(state.power.SetStatusBarTexture,state.power,WHITE) end
    state.liquid.tint=color
    self.paintingCompact=false
end

function P:HideCompact(state)
    state.appliedUnit=nil
    state.liquid:Stop(); state.clip:Hide(); state.front:Hide()
    ClearRange(state)
    if state.healPreview then RP.Plates:UpdateHealPreview(state.healPreview) end
    if RP.HealerHots then RP.HealerHots:Hide(state) end
end

local function UpdateCompactHeal(state,unit)
    if state.healPreview then RP.Plates:UpdateHealPreview(state.healPreview,Field(state.native,"displayedUnit") or unit) end
end

function P:UpdateCompactHealthText(state)
    if not state or not state.active then return end
    local frame=state.native
    local text=Field(frame,"statusText")
    local options=Field(frame,"optionTable")
    if not Object(text) or Read(text,"IsShown")~=true or Field(options,"displayStatusText")~=true then return end
    local ok,mode=Call(CompactUnitFrame_GetOptionHealthText,frame,options)
    if not ok or not Public(mode) or (mode~="health" and mode~="losthealth") then return end
    local member=CurrentUnit(frame)
    local unit=Field(frame,"displayedUnit") or member
    if not member then return end
    local connected,isConnected=Call(UnitIsConnected,member)
    local alive,isDead=Call(UnitIsDeadOrGhost,unit)
    if not connected or not Public(isConnected) or isConnected~=true or not alive or not Public(isDead) or isDead~=false then return end
    local readHealth=mode=="health" and UnitHealth or UnitHealthMissing
    local read,value=Call(readHealth,unit)
    if read and (RP.IsSecret(value) or Number(value)) then
        text:SetFormattedText(mode=="health" and "%s" or "-%s",RP.Plates:FormatHealthNumber(value))
    end
end

function P:ApplyCompact(state)
    local unit=CurrentUnit(state.native)
    if not unit or IsRaid() then self:ReleaseCompact(state); return end
    if state.parentRestorePending and not Combat() then self:ReleaseCompact(state) end
    local newlyStyled=not state.active
    if newlyStyled then
        state.texture=BarTexture(state.health)
        state.powerTexture=Object(state.power) and BarTexture(state.power) or nil
        state.healthAppearance=CaptureBarAppearance(state.health) or state.healthAppearance
        state.powerAppearance=Object(state.power) and CaptureBarAppearance(state.power) or nil
        local colors={pcall(state.health.GetStatusBarColor,state.health)}
        if colors[1] and Number(colors[2]) and Number(colors[3]) and Number(colors[4]) then
            state.color={colors[2],colors[3],colors[4],Number(colors[5]) and colors[5] or 1}
        end
        state.fonts,state.fontMap={},{}
        state.parents={}
        if not Combat() then
            for _,key in ipairs({"name","statusText"}) do
                local object=Field(state.native,key)
                local parent=Read(object,"GetParent")
                if Object(object) and Object(parent) and type(Field(object,"SetParent"))=="function" then
                    state.parents[#state.parents+1]={object=object,parent=parent}
                    object:SetParent(state.front)
                end
            end
        end
    end
    state.active=true
    self:PaintCompact(state)
    StyleFont(state,Field(state.native,"name"),11)
    StyleFont(state,Field(state.native,"statusText"),10)
    local width,height=Read(state.health,"GetWidth"),Read(state.health,"GetHeight")
    if Number(width) and Number(height) then state.liquid.width,state.liquid.height=width,height end
    if state.native:IsVisible() then
        state.appliedUnit=unit
        state.clip:Show(); state.front:Show()
        if newlyStyled then self:UpdateCompactHealthText(state) end
        if RP.db.bubbles then
            if not state.liquid:GetScript("OnUpdate") then state.liquid:Start() end
        else state.liquid:Stop() end
        UpdateRange(state,state.health,unit)
        UpdateCompactHeal(state,unit)
        if RP.HealerHots then RP.HealerHots:Attach(state,unit,state.front,state.health,"compact") end
    else self:HideCompact(state) end
end

function P:ReleaseCompact(state)
    if not state.active and not state.parentRestorePending then return end
    if state.active then
        state.active=false; self:HideCompact(state)
        Call(CompactUnitFrame_UpdateStatusText,state.native)
        RestoreBarAppearance(state.health,state.healthAppearance)
        RestoreBarAppearance(state.power,state.powerAppearance)
        pcall(state.health.SetStatusBarColor,state.health,unpack(state.color))
        RestoreFonts(state)
    end
    if not Combat() then
        for _,property in ipairs(state.parents or {}) do
            if Read(property.object,"GetParent")==state.front then property.object:SetParent(property.parent) end
        end
        state.parentRestorePending=false
    else state.parentRestorePending=true; self.pending=true end
end

function P:RefreshFonts()
    local suite=rawget(_G,"RicoSuite")
    for _,state in pairs(self.entries) do
        if state.entry then
            if suite and type(suite.RefreshPlateFonts)=="function" then suite:RefreshPlateFonts(state.entry.plate,RP.Theme) end
            state.entry.status:SetFont(RP.Theme.font,9,"OUTLINE")
            if state.active and not Combat() then self:NativeIndicators(state) end
        end
    end
    for _,state in pairs(self.compact) do if state.active then self:ApplyCompact(state) end end
end

function P:UpdateSettings()
    self:Initialize()
    if self.applying then return end
    if Combat() then self.pending=true; self:RefreshRange(); return end
    self.pending=false; self.applying=true
    if not Enabled() then
        for _,state in pairs(self.entries) do self:ReleaseStandard(state) end
        for _,state in pairs(self.compact) do self:ReleaseCompact(state) end
    else
        local native=rawget(_G,"PartyFrame")
        if Object(native) then
            for index=1,4 do
                local frame=Read(native,"GetPartyMemberFrame",index) or Field(native,"MemberFrame"..index)
                if Object(frame) then
                    local state,reason=self:BuildStandard(frame)
                    if state then
                        local ok,message=pcall(self.ApplyStandard,self,state)
                        if not ok then self:ReleaseStandard(state); self:Error(message) end
                    elseif reason then self:Error(reason) end
                end
            end
            local layout=Field(native,"Layout")
            if type(layout)=="function" then pcall(layout,native) end
        end
        local compact=rawget(_G,"CompactPartyFrame")
        local members=Field(compact,"memberUnitFrames")
        if type(members)=="table" and Public(members) then
            for index=1,math.min(#members,5) do
                local frame=members[index]
                if Object(frame) then
                    local state=self:BuildCompact(frame)
                    if state then self:ApplyCompact(state) end
                end
            end
        end
    end
    self.applying=false
    self:RefreshFonts()
end

function P:QueueApply()
    if self.applying or self.queued then return end
    if Combat() then self.pending=true; return end
    self.queued=true
    local function Apply() P.queued=false; P:UpdateSettings() end
    if C_Timer and C_Timer.After then C_Timer.After(0,Apply) else Apply() end
end

function P:RefreshAll(portrait)
    for _,state in pairs(self.entries) do self:RefreshStandard(state,portrait) end
    for _,state in pairs(self.compact) do
        local pendingDisable=Combat() and state.active and not Enabled()
        if pendingDisable then self.pending=true end
        if (not Enabled() and not pendingDisable) or IsRaid() or not CurrentUnit(state.native) then self:ReleaseCompact(state)
        elseif state.active then self:ApplyCompact(state) end
    end
end

function P:GetStatus()
    local standard,compact=0,0
    for _,state in pairs(self.entries) do if state.active and Read(state.native,"IsVisible")==true then standard=standard+1 end end
    for _,state in pairs(self.compact) do if state.active and Read(state.native,"IsVisible")==true then compact=compact+1 end end
    local message
    local pending=self.pending or (Combat() and not Enabled() and (standard+compact)>0)
    if pending then message="Party appearance changes will apply after combat."
    elseif not Enabled() then message="Party styling is disabled; Blizzard party frames are restored."
    elseif compact>0 then message="Compact party frames use Rico liquid bars; their native layout is preserved."
    elseif standard>0 then message="Party frames use the Rico style. Move their group with Blizzard Edit Mode."
    elseif self.lastError then message=self.lastError
    else message="The Rico party style is ready and appears when your party frames are shown." end
    return {message=message,mode=compact>0 and "compact" or standard>0 and "standard" or "inactive",
        standard=standard,compact=compact,errors=self.errors,pending=pending==true}
end

function P:CreateOptionsPreview(parent)
    local preview={frame=CreateFrame("Frame",nil,parent),entries={}}
    preview.frame:SetAllPoints(parent); preview.frame:EnableMouse(false)
    for index=1,2 do
        local host=CreateFrame("Frame",nil,preview.frame)
        host:SetPoint("TOPLEFT",preview.frame,"TOPLEFT",12,-85-(index-1)*160)
        local entry=RP.UnitFrames:CreateVisual(host,"party"..index,true)
        entry.enabled=true; entry.partyFrame=true; entry.nativeAuras=true
        entry.previewHost=host; preview.entries[index]=entry
    end
    self:RefreshOptionsPreview(preview)
    return preview
end

function P:RefreshOptionsPreview(preview)
    if not preview then return end
    for index,entry in ipairs(preview.entries or {}) do
        local healing=index==1 and RP.Options and RP.Options.selectedPage==8
        RP.UnitFrames:LayoutVisual(entry)
        entry.previewHost:SetSize(entry.width,entry.height)
        entry.previewHost:SetScale(math.min(RP.db.partyFrameScale or 0.8,0.95))
        entry.previewHost:ClearAllPoints()
        entry.previewHost:SetPoint("TOPLEFT",preview.frame,"TOPLEFT",12,-85-(index-1)*160)
        RP.Plates:UpdateDemo(entry.plate,{name=index==1 and "Party healer [Guild]" or "Party warrior [Guild]",kind="party",
            hp=healing and 1400 or index==1 and 1680 or 2340,max=index==1 and 2200 or 3000,
            heal=healing and 1000 or nil,healAbsorb=healing and 120 or nil,
            level=index==1 and 26 or 27,class=index==1 and "PRIEST" or "WARRIOR",power=70,powerMax=100,powerColor={0.15,0.35,1}})
        RP.UnitFrames:LayoutIcons(entry)
        entry.portrait:Show(); RP.Portraits:SetUnit(entry.portrait,"player",false)
    end
end

function P:SetPreviewShown(preview,shown)
    if not preview then return end
    preview.frame:SetShown(shown)
    for _,entry in ipairs(preview.entries or {}) do
        entry.plate:SetShown(shown)
        if shown then RP.Plates:StartBubbles(entry.plate)
        else RP.Plates:StopBubbles(entry.plate); RP.Portraits:Clear(entry.portrait) end
    end
    if shown then self:RefreshOptionsPreview(preview) end
end

local function MatchingUnit(state,unit)
    if not state.active then return end
    local token=CurrentUnit(state.native)
    if not token or token==unit then return token end
    local ok,same=Call(UnitIsUnit,token,unit)
    if ok and RP.PublicTrue(same) then return token end
end

local function UpdateVitals(state,unit,kind)
    if kind=="standard" then
        RP.Plates:UpdateHealth(state.entry.plate)
        RP.UnitFrames:UpdateStatus(state.entry)
        if RP.Dispels then RP.Dispels:RefreshStandard(state) end
    else
        UpdateCompactHeal(state,unit)
        if RP.Dispels then RP.Dispels:RefreshCompact(state) end
    end
    if RP.PartyWarnings then RP.PartyWarnings:Refresh(state,kind) end
end

local healthEvents={UNIT_HEALTH=true,UNIT_MAXHEALTH=true}
local powerEvents={UNIT_POWER_UPDATE=true,UNIT_POWER_FREQUENT=true,UNIT_MAXPOWER=true,UNIT_DISPLAYPOWER=true}

function P:Initialize()
    if self.initialized then return end
    self.initialized=true
    local events=CreateFrame("Frame"); self.events=events
    if type(hooksecurefunc)=="function" and type(CompactUnitFrame_UpdateStatusText)=="function" then
        pcall(hooksecurefunc,_G,"CompactUnitFrame_UpdateStatusText",function(frame)
            P:UpdateCompactHealthText(P.compact[frame])
        end)
    end
    for _,event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","GROUP_ROSTER_UPDATE","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED",
        "UNIT_HEALTH","UNIT_MAXHEALTH","UNIT_HEAL_PREDICTION","UNIT_HEAL_ABSORB_AMOUNT_CHANGED","UNIT_IN_RANGE_UPDATE",
        "UNIT_POWER_UPDATE","UNIT_POWER_FREQUENT","UNIT_MAXPOWER","UNIT_DISPLAYPOWER","UNIT_NAME_UPDATE",
        "UNIT_PORTRAIT_UPDATE","UNIT_MODEL_CHANGED","UNIT_LEVEL","UNIT_CLASSIFICATION_CHANGED","UNIT_CONNECTION","UNIT_FLAGS","UNIT_FACTION",
        "UNIT_ENTERED_VEHICLE","UNIT_EXITED_VEHICLE","UNIT_GUILD_UPDATE","GUILD_ROSTER_UPDATE","PARTY_LEADER_CHANGED","ROLE_CHANGED_INFORM",
        "UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_CHANNEL_UPDATE"}) do pcall(events.RegisterEvent,events,event) end
    events:SetScript("OnEvent",function(_,event,unit)
        if event=="UNIT_IN_RANGE_UPDATE" then P:RefreshRange(); return end
        if event=="PLAYER_REGEN_ENABLED" or event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_ENTERING_WORLD" or event=="ADDON_LOADED" then
            P:QueueApply()
        end
        if event:sub(1,5)=="UNIT_" then
            if not Public(unit) or type(unit)~="string" then return end
            if event=="UNIT_HEAL_PREDICTION" or event=="UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                for _,state in pairs(P.entries) do
                    if state.active and state.entry.plate:IsShown() then
                        RP.Plates:UpdateHealPreview(state.entry.plate.healPreview,state.entry.unit)
                    end
                end
                -- Compact frames keep Blizzard's native incoming-heal layers.
                -- This preview contains only the separate own-overheal marker.
                for _,state in pairs(P.compact) do
                    if state.active and state.healPreview and Read(state.native,"IsVisible")==true then
                        UpdateCompactHeal(state,CurrentUnit(state.native))
                    end
                end
                return
            end
            local portrait=event=="UNIT_PORTRAIT_UPDATE" or event=="UNIT_MODEL_CHANGED" or event=="UNIT_NAME_UPDATE"
            local health,power=healthEvents[event],powerEvents[event]
            local cast=event:find("UNIT_SPELLCAST_",1,true)~=nil
            local frequent=health or power or cast
            local enabled=Enabled()
            local pendingDisable=not enabled and Combat()
            local raid=IsRaid()
            for _,state in pairs(P.entries) do
                local token=MatchingUnit(state,unit)
                if token then
                    local entry=state.entry
                    if frequent and (enabled or pendingDisable) and not raid and entry.enabled and entry.unit==token
                        and Exists(token) and Read(state.native,"IsVisible")==true and Read(entry.plate,"IsVisible")==true then
                        if pendingDisable then P.pending=true end
                        if health then UpdateVitals(state,token,"standard")
                        elseif power then RP.Plates:UpdatePower(entry.plate)
                        else RP.Plates:UpdateCast(entry.plate) end
                    else P:RefreshStandard(state,portrait) end
                end
            end
            for _,state in pairs(P.compact) do
                local token=MatchingUnit(state,unit)
                if token then
                    if pendingDisable then P.pending=true end
                    if (not enabled and not pendingDisable) or raid then P:ReleaseCompact(state)
                    elseif frequent and state.appliedUnit==token and Read(state.front,"IsVisible")==true then
                        -- Native compact frames already update their HP, power and cast widgets.
                        if health then UpdateVitals(state,token,"compact") end
                    else P:ApplyCompact(state) end
                end
            end
            return
        end
        P:RefreshAll(event=="UNIT_PORTRAIT_UPDATE" or event=="UNIT_MODEL_CHANGED" or event=="UNIT_NAME_UPDATE" or event=="GROUP_ROSTER_UPDATE")
    end)
    local native=rawget(_G,"PartyFrame")
    if Object(native) and type(hooksecurefunc)=="function" then
        for _,method in ipairs({"InitializePartyMemberFrames","UpdatePartyFrames","UpdateMemberFrames","UpdateSpacingAndLayout"}) do
            if type(Field(native,method))=="function" then pcall(hooksecurefunc,native,method,function() P:QueueApply() end) end
        end
    end
end
