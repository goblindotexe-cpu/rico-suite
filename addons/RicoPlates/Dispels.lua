-- Friendly dispel capability is separate from public spell-readiness checks.
-- Spell families are the learned Vanilla/Forever abilities, not retail-spec
-- assumptions. Sources: Quest-independent spell map in Decursive/DCR_init.lua
-- and EllesmereUIRaidFrames/EUI_RaidFrames_ClickCast.lua (IS_FOREVER branch).
-- https://github.com/2072/Decursive/blob/master/DCR_init.lua
-- https://github.com/EllesmereGaming/EllesmereUI/blob/main/EllesmereUIRaidFrames/EUI_RaidFrames_ClickCast.lua
local _, RP = ...
local D = { records=setmetatable({}, {__mode="k"}), active=setmetatable({}, {__mode="k"}),
    fonts=setmetatable({}, {__mode="k"}) }
RP.Dispels = D
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FALLBACK = "Interface\\Icons\\Spell_Holy_DispelMagic"
local MAX_AURAS = 80
local GROUP = "ricoPartyDispel"
-- Forever's AuraUtil defines RAID as harmful auras the PLAYER can dispel.
-- RAID_PLAYER_DISPELLABLE may also include other raid members' capabilities.
local FILTER = "HARMFUL|RAID"
local SPELLS = {
    PRIEST = {{988,"Dispel Magic",2,"Magic"},{527,"Dispel Magic",2,"Magic"},
        {552,"Abolish Disease",2,"Disease"},{528,"Cure Disease",2,"Disease"}},
    PALADIN = {{4987,"Cleanse",2,"Magic","Poison","Disease"},{1152,"Purify",2,"Poison","Disease"}},
    DRUID = {{2782,"Remove Curse",8,"Curse"},{2893,"Abolish Poison",8,"Poison"},{8946,"Cure Poison",8,"Poison"}},
    MAGE = {{475,"Remove Lesser Curse",64,"Curse"}},
    SHAMAN = {{526,"Cure Poison",8,"Poison"},{2870,"Cure Disease",8,"Disease"}},
    WARLOCK = {{19736,"Devour Magic",32,"Magic",pet=true},{19734,"Devour Magic",32,"Magic",pet=true},
        {19731,"Devour Magic",32,"Magic",pet=true},{19505,"Devour Magic",32,"Magic",pet=true}},
}
local TYPES = {
    Magic={0.22,0.68,1.00,"M"}, Curse={0.77,0.34,1.00,"C"},
    Poison={0.30,0.96,0.39,"P"}, Disease={0.96,0.68,0.24,"D"},
}
local HARD_CONTROL = { STUN=true, STUN_MECHANIC=true, SILENCE=true, PACIFYSILENCE=true,
    FEAR=true, HORROR=true, CONFUSE=true, SLEEP=true, CYCLONE=true, BANISH=true, POSSESS=true }
local NONCAST_CONTROL = { ROOT=true, DISARM=true, PACIFY=true }

local function Public(value) return RP.Readable(value) end
local function Number(value)
    return Public(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function String(value) return Public(value) and type(value)=="string" end
local function Table(value)
    return Public(value) and type(value)=="table" and (not canaccesstable or canaccesstable(value))
end
local function Field(object,key)
    if not Public(object) or object==nil then return nil end
    local ok,value=pcall(function() return object[key] end)
    if ok and Public(value) then return value end
end
local function Call(fn,...)
    if type(fn)~="function" then return false end
    return pcall(fn,...)
end
local function Read(fn,...)
    local ok,value=Call(fn,...)
    if ok and Public(value) then return value end
end
local function True(value) return Public(value) and (value==true or value==1) end
local function False(value) return Public(value) and (value==false or value==0) end
local function Unit(unit)
    return String(unit) and (unit=="player" or unit:match("^party[1-4]$"))
end
local function Visible(frame)
    return frame and Read(Field(frame,"IsVisible"),frame)==true
end
local function Enabled()
    return RP.db and RP.db.enabled~=false and RP.db.partyFrames~=false and RP.db.partyDispels~=false
end
local function CurrentUnit(state,kind)
    local unit = kind=="standard" and state.entry and state.entry.unit
        or Read(Field(state.native,"GetUnit"),state.native)
        or Field(state.native,"displayedUnit") or Field(state.native,"unit") or Field(state.native,"unitToken")
    return Unit(unit) and unit or nil
end
local function FriendlyAlive(unit)
    if not Unit(unit) or not True(Read(UnitExists,unit)) then return false end
    if not True(Read(UnitCanAssist,"player",unit)) then return false end
    if not False(Read(UnitIsDeadOrGhost,unit)) then return false end
    return True(Read(UnitIsConnected,unit))
end
local function PetAlive()
    return True(Read(UnitExists,"pet")) and False(Read(UnitIsDeadOrGhost,"pet"))
end

local function Known(id,pet)
    local api=C_SpellBook
    if api and type(api.IsSpellKnown)=="function" then
        local banks=Enum and Enum.SpellBookSpellBank
        return True(Read(api.IsSpellKnown,id,pet and (banks and banks.Pet or 1) or (banks and banks.Player or 0)))
    end
    if type(IsSpellKnown)=="function" then return True(Read(IsSpellKnown,id,pet and true or false)) end
    return not pet and True(Read(IsPlayerSpell,id)) or false
end

function D:GetSpells()
    if self.spells then return self.spells end
    local ok,_,class=Call(UnitClass,"player")
    local found={}
    if ok and String(class) then
        local petAlive=PetAlive()
        for _,spell in ipairs(SPELLS[class] or {}) do
            if (not spell.pet or petAlive) and Known(spell[1],spell.pet) then
                local info=Read(C_Spell and C_Spell.GetSpellInfo,spell[1])
                local name=Table(info) and Field(info,"name")
                local choice={id=spell[1],name=String(name) and name or spell[2],school=spell[3],pet=spell.pet}
                for index=4,#spell do
                    local dispelType=spell[index]
                    found[dispelType]=found[dispelType] or {}
                    found[dispelType][#found[dispelType]+1]=choice
                end
            end
        end
    end
    self.spells=found
    return found
end
function D:HasCapability()
    for _,choices in pairs(self:GetSpells()) do
        for _,spell in ipairs(choices) do if not spell.pet or PetAlive() then return true end end
    end
    return false
end

local function ControlStatus(spell)
    -- Player loss-of-control does not describe a pet's own lockout or stun.
    if spell.pet then return nil,"Pet availability is not checked." end
    local api=C_LossOfControl
    if not api or type(api.GetActiveLossOfControlDataCount)~="function" or type(api.GetActiveLossOfControlData)~="function" then
        return nil,"Control restrictions are not readable."
    end
    local count=Read(api.GetActiveLossOfControlDataCount)
    if not Number(count) or count<0 or count>32 or count~=math.floor(count) then return nil,"Control restrictions are not readable." end
    for index=1,count do
        local data=Read(api.GetActiveLossOfControlData,index)
        if not Table(data) then return nil,"Control restrictions are not readable." end
        local kind=Field(data,"locType")
        if not String(kind) then return nil,"Control restrictions are not readable." end
        local remaining=Field(data,"timeRemaining")
        if not Number(remaining) or remaining>0 then
            if HARD_CONTROL[kind] then return false,"Casting is blocked by loss of control." end
            if kind=="SCHOOL_INTERRUPT" then
                local mask=Field(data,"lockoutSchool")
                if not Number(mask) or mask<0 or mask~=math.floor(mask) then return nil,"School lockout is not readable." end
                if math.floor(mask/spell.school)%2==1 then return false,"This spell school is locked." end
            elseif not HARD_CONTROL[kind] and not NONCAST_CONTROL[kind] then
                return nil,"This control restriction is not classified."
            end
        end
    end
    return true
end

local function CooldownStatus(id)
    if C_Spell and C_Spell.GetSpellCharges then
        local info=Read(C_Spell.GetSpellCharges,id)
        if info~=nil then
            if not Table(info) then return nil end
            local current=Field(info,"currentCharges")
            if not Number(current) then return nil end
            return current>0
        end
    end
    if C_Spell and C_Spell.GetSpellCooldown then
        local info=Read(C_Spell.GetSpellCooldown,id)
        if not Table(info) then return nil end
        local enabled,active=Field(info,"isEnabled"),Field(info,"isActive")
        if False(enabled) then return false end
        if not True(enabled) then return nil end
        if type(active)=="boolean" then return not active end
        local start,duration=Field(info,"startTime"),Field(info,"duration")
        local now=Read(GetTime)
        if Number(start) and Number(duration) and Number(now) then return start==0 or duration==0 or start+duration<=now end
        return nil
    end
    local ok,start,duration,enabled=Call(GetSpellCooldown,id)
    local now=Read(GetTime)
    if ok and Number(start) and Number(duration) and Number(now) and Public(enabled) then
        if False(enabled) then return false end
        if True(enabled) then return start==0 or duration==0 or start+duration<=now end
    end
end

function D:SpellStatus(spell,unit)
    if not False(Read(UnitIsDeadOrGhost,"player")) then return "unknown","Player availability is not readable." end
    local controlled,controlMessage=ControlStatus(spell)
    if controlled==false then return "unavailable",controlMessage end
    local cooldown=CooldownStatus(spell.id)
    if cooldown==false then return "cooldown","The dispel is cooling down or has no charges." end
    local usableAPI=C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
    local ok,usable,power=Call(usableAPI,spell.id)
    if ok and False(usable) then
        return "unavailable",True(power) and "Not enough power for this dispel." or "The spell is unavailable in the current form or state."
    end
    local rangeAPI=C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
    local ranged,inRange=Call(rangeAPI,spell.id,unit)
    if ranged and False(inRange) then return "range","This member is outside the dispel's range." end
    if controlled==true and cooldown==true and ok and True(usable) and ranged and True(inRange) then
        return "ready","Public cooldown, range and casting checks passed."
    end
    return "unknown",controlMessage or "Spell availability is not fully readable."
end

function D:Scan(unit)
    if not FriendlyAlive(unit) then return {} end
    local spells=self:GetSpells()
    if not next(spells) then return {} end
    local getter=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local debuffGetter=C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex
    local result={}
    if type(getter)~="function" and type(debuffGetter)~="function" then return result end
    for index=1,MAX_AURAS do
        local ok,aura
        if type(getter)=="function" then ok,aura=Call(getter,unit,index,"HARMFUL")
        else ok,aura=Call(debuffGetter,unit,index) end
        if not ok or not Public(aura) then break end
        if aura==nil then break end
        if not Table(aura) then break end
        local dispelType=Field(aura,"dispelName")
        local choices=String(dispelType) and spells[dispelType]
        if choices and Field(aura,"isHarmful")~=false then
            local name,icon,instance=Field(aura,"name"),Field(aura,"icon"),Field(aura,"auraInstanceID")
            result[#result+1]={dispelType=dispelType,name=String(name) and name or (dispelType.." debuff"),
                icon=(String(icon) or Number(icon)) and icon or FALLBACK,
                instance=Number(instance) and instance>0 and instance or nil,index=index,choices=choices}
        end
    end
    return result
end

local function Anchor(record)
    local state=record.state
    return record.kind=="standard" and state.entry.plate.health or state.health,
        record.kind=="standard" and state.entry.portraitFront or state.front or state.native
end
local function BadgeSize(record)
    local anchor=Anchor(record)
    local height=Read(Field(anchor,"GetHeight"),anchor)
    local maximum=record.kind=="compact" and 14 or 20
    return Number(height) and math.max(10,math.min(maximum,math.floor(height)-4)) or maximum
end
local function Font(font,size)
    D.fonts[font]=size
    font:SetFont(RP.Theme.font,size,"OUTLINE")
end
function D:RefreshFonts()
    for font,size in pairs(self.fonts) do font:SetFont(RP.Theme.font,size,"OUTLINE") end
end

local function InitializeNativeButton(button,size)
    button:SetSize(size,size)
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(true) end
    local background=button:CreateTexture(nil,"BACKGROUND")
    background:SetAllPoints(); background:SetTexture(WHITE); background:SetVertexColor(.005,.009,.007,1)
    local icon=button:CreateTexture(nil,"ARTWORK")
    icon:SetPoint("TOPLEFT",1,-1); icon:SetPoint("BOTTOMRIGHT",-1,1); icon:SetTexCoord(.08,.92,.08,.92)
    button:SetIcon(icon)
    -- These are supported inbound render sinks. The native button applies
    -- restricted type/color/text itself; addon Lua never reads them back.
    local border=button:CreateTexture(nil,"OVERLAY")
    border:SetPoint("TOPLEFT",-2,2); border:SetPoint("BOTTOMRIGHT",2,-2)
    local styles=Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    button:AddDispelTypeTexture(border,{style=styles and styles.BorderWithIcon or 1,
        showWhenHarmful=true,showWhenHelpful=false})
    local front=CreateFrame("Frame",nil,button); front:SetAllPoints(button)
    front:SetFrameLevel(button:GetFrameLevel()+3); front:EnableMouse(false)
    local letter=front:CreateFontString(nil,"OVERLAY"); Font(letter,8)
    letter:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",0,-1)
    button:SetDispelTypeText(letter,{customDispelTextMap={Magic="M",Curse="C",Poison="P",Disease="D"}})
    local count=front:CreateFontString(nil,"OVERLAY"); Font(count,9)
    count:SetPoint("TOPRIGHT",button,"TOPRIGHT",1,1); button:SetApplicationCount(count)
    -- Preserve Blizzard's native tooltip: it can show restricted aura identity
    -- without returning that identity to addon code. These icons mean
    -- "removable by me", not "ready now"; cooldown/mana/LoS aren't promised.
    if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_TOPRIGHT",0,4) end
    if button.SetHideTooltipInCombat then button:SetHideTooltipInCombat(false) end
end

function D:CreateNative(record)
    if record.container then return true end
    if self.nativeAvailable==false then return false end
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local ok,info=Call(C_XMLUtil.GetTemplateInfo,"CustomAuraContainerTemplate")
        if ok and Public(info) and info==nil then self.nativeAvailable=false; return false end
    end
    local created
    local ok,result=pcall(function()
        local anchor,parent=Anchor(record)
        local size=BadgeSize(record)
        local container=CreateFrame("AuraContainer",nil,parent,"CustomAuraContainerTemplate")
        created=container
        if type(container.AddAuraGroup)~="function" or type(container.SetEnabled)~="function"
            or type(container.SetUnit)~="function" then return nil end
        container:Hide(); container:SetEnabled(false); container:EnableMouse(false)
        container:SetSize(size,size)
        -- Keep this one small indicator and its two-pixel border inside the
        -- health bar, so horizontal compact layouts keep native member gaps.
        container:SetPoint("TOPRIGHT",anchor,"TOPRIGHT",-2,-2)
        container:SetFrameLevel(parent:GetFrameLevel()+12)
        if container.SetEditModePreviewEnabled then container:SetEditModePreviewEnabled(false) end
        container:SetFlowLayoutAnchorPoint("TOPRIGHT")
        if container.SetFlowLayoutGrowthDirection and AnchorUtil and AnchorUtil.FlowDirection then
            container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left,AnchorUtil.FlowDirection.Down)
        end
        container:SetFlowLayoutMaximumLineSize(math.huge)
        -- This is an indicator, not a second aura row. Native party auras still
        -- list every effect; one foremost removable effect is enough here.
        record.nativeButtons={}
        container:AddAuraGroup(GROUP,FILTER,{maxFrameCount=1,
            initializeFrame=function(button)
                InitializeNativeButton(button,size)
                -- Own construction references, never aura assignments/counts.
                record.nativeButtons[#record.nativeButtons+1]=button
            end,
            layout={elementSpacing=4,lineSpacing=0}})
        return container
    end)
    if not ok or not result then
        if created then Call(Field(created,"SetEnabled"),created,false); Call(Field(created,"Hide"),created) end
        self.nativeAvailable=false
        return false
    end
    self.nativeAvailable=true
    record.container=result
    return true
end

function D:RefreshNative(record,force)
    -- Do not inspect native aura assignments, children, visibility, or counts.
    -- The engine's HARMFUL|RAID filter alone owns presence and dispel type.
    if record.badge then record.badge:Hide() end
    self.active[record]=nil
    if self.worker and not next(self.active) then self.worker:Hide() end
    local container=record.container
    local size=BadgeSize(record); container:SetSize(size,size)
    for _,button in ipairs(record.nativeButtons or {}) do button:SetSize(size,size) end
    if force or record.nativeUnit~=record.unit then
        container:SetEnabled(false); container:SetUnit("")
        container:SetUnit(record.unit); record.nativeUnit=record.unit
    end
    container:SetEnabled(true); container:Show()
    record.mode="native"
end

function D:Build(record)
    if record.badge then return end
    local anchor,parent=Anchor(record)
    local badge=CreateFrame("Frame",nil,parent)
    record.badge=badge
    local size=BadgeSize(record)
    badge:SetSize(size,size); badge:SetPoint("TOPRIGHT",anchor,"TOPRIGHT",-2,-2)
    badge:SetFrameLevel(parent:GetFrameLevel()+12)
    badge:EnableMouse(true)
    if badge.SetMouseClickEnabled then badge:SetMouseClickEnabled(false) end
    if badge.SetMouseMotionEnabled then badge:SetMouseMotionEnabled(true) end
    local background=badge:CreateTexture(nil,"BACKGROUND"); background:SetAllPoints(); background:SetTexture(WHITE)
    background:SetVertexColor(0.005,0.009,0.007,1)
    local icon=badge:CreateTexture(nil,"ARTWORK"); icon:SetPoint("TOPLEFT",1,-1); icon:SetPoint("BOTTOMRIGHT",-1,1)
    icon:SetTexCoord(.08,.92,.08,.92); record.icon=icon
    record.edges={}
    for _,edge in ipairs({{"TOPLEFT","TOPRIGHT",true},{"BOTTOMLEFT","BOTTOMRIGHT",true},{"TOPLEFT","BOTTOMLEFT",false},{"TOPRIGHT","BOTTOMRIGHT",false}}) do
        local tex=badge:CreateTexture(nil,"OVERLAY"); tex:SetTexture(WHITE)
        tex:SetPoint(edge[1],badge,edge[1],-1,1); tex:SetPoint(edge[2],badge,edge[2],1,-1)
        if edge[3] then tex:SetHeight(2) else tex:SetWidth(2) end
        record.edges[#record.edges+1]=tex
    end
    record.letter=badge:CreateFontString(nil,"OVERLAY"); Font(record.letter,8)
    record.letter:SetPoint("BOTTOMLEFT",0,-1)
    record.count=badge:CreateFontString(nil,"OVERLAY"); Font(record.count,9)
    record.count:SetPoint("TOPRIGHT",2,2); record.count:SetTextColor(1,1,1,1)
    badge:SetScript("OnEnter",function() D:ShowTooltip(record) end)
    badge:SetScript("OnLeave",function() if D.tooltip then D.tooltip:Hide() end end)
    badge:SetScript("OnHide",function() if D.tooltip and D.tooltip:IsOwned(badge) then D.tooltip:Hide() end end)
    badge:Hide()
end

function D:ShowTooltip(record)
    local aura,spell=record.selected,record.spell
    if not aura or not spell or not record.badge:IsVisible() then return end
    if RP.UnitFrames then RP.UnitFrames:HideUnitTooltip() end
    if RP.Features then RP.Features:HideBadgeTooltip() end
    if GameTooltip then GameTooltip:Hide() end
    if not self.tooltip then
        self.tooltip=CreateFrame("GameTooltip","RicoPlatesDispelTooltip",UIParent,"GameTooltipTemplate")
        self.tooltip:SetFrameStrata("TOOLTIP"); self.tooltip:SetClampedToScreen(true); self.tooltip:EnableMouse(false)
        RP.Theme:Panel(self.tooltip):SetVertexColor(.014,.022,.018,1)
    end
    local tip=self.tooltip
    tip:SetOwner(record.badge,"ANCHOR_RIGHT"); tip:ClearLines()
    local color=TYPES[aura.dispelType]
    tip:SetText(aura.name,color[1],color[2],color[3])
    tip:AddLine("Removable type: "..aura.dispelType,.9,.93,.9)
    tip:AddLine("Your learned spell: "..spell.name,.8,.9,.83,true)
    tip:AddLine(record.readinessMessage or "Spell availability is not fully readable.",.9,.83,.63,true)
    tip:AddLine("Removable by me. Line of sight is not checked; this indicator does not cast a spell.",.7,.77,.72,true)
    if #record.auras>1 then
        tip:AddLine(#record.auras.." removable debuffs observed:",.83,.87,.84)
        for index=1,math.min(6,#record.auras) do tip:AddLine(record.auras[index].name.." ("..record.auras[index].dispelType..")",.76,.83,.78,true) end
    end
    tip:Show()
end

function D:Forget(state)
    local record=self.records[state]
    if not record then return end
    self.active[record]=nil
    record.auras,record.selected,record.spell={},nil,nil
    record.scanned,record.nativeUnit=nil,nil
    if record.badge then record.badge:Hide() end
    if record.container then
        record.container:SetEnabled(false); record.container:SetUnit(""); record.container:Hide()
    end
    if self.worker and not next(self.active) then self.worker:Hide() end
end

function D:Paint(record)
    if not Enabled() or not record.state.active or not Visible(record.state.native) or not FriendlyAlive(record.unit) then
        self:Forget(record.state); return
    end
    local best,bestSpell,bestState,bestMessage
    for _,aura in ipairs(record.auras) do
        for _,spell in ipairs(aura.choices) do
            if not spell.pet or PetAlive() then
                local status,message=self:SpellStatus(spell,record.unit)
                if not best or (status=="ready" and bestState~="ready") then
                    best,bestSpell,bestState,bestMessage=aura,spell,status,message
                end
            end
        end
    end
    if not best then self:Forget(record.state); return end
    self:Build(record)
    local size=BadgeSize(record); record.badge:SetSize(size,size)
    record.selected,record.spell,record.readiness,record.readinessMessage=best,bestSpell,bestState,bestMessage
    record.icon:SetTexture(best.icon)
    local color=TYPES[best.dispelType]
    for _,edge in ipairs(record.edges) do edge:SetVertexColor(color[1],color[2],color[3],1) end
    record.letter:SetText(color[4]); record.letter:SetTextColor(color[1],color[2],color[3],1)
    record.count:SetText(#record.auras>1 and tostring(#record.auras) or "")
    record.icon:SetDesaturated(bestState~="ready")
    record.badge:SetAlpha(bestState=="ready" and 1 or bestState=="unknown" and .82 or .6)
    record.badge:Show()
    self.active[record]=true; self.worker:Show()
end

function D:Refresh(state,kind,force)
    if not state then return end
    local record=self.records[state]
    if not record then record={state=state,kind=kind,auras={}}; self.records[state]=record end
    local unit=CurrentUnit(state,kind)
    if not Enabled() or not state.active or not unit or not Visible(state.native)
        or (kind=="standard" and (not state.entry or not state.entry.enabled or state.entry.preview))
        or True(Read(IsInRaid)) or not FriendlyAlive(unit) then self:Forget(state); return end
    local guid=Read(UnitGUID,unit)
    if not String(guid) then guid=nil end
    if force or record.unit~=unit or record.guid~=guid or not record.scanned then
        record.unit,record.guid,record.scanned=unit,guid,true
        force=true
    end
    if not self:HasCapability() then self:Forget(state); return end
    if self:CreateNative(record) then self:RefreshNative(record,force); return end
    record.mode="api"
    if force then record.auras=self:Scan(unit) end
    self:Paint(record)
end
function D:RefreshStandard(state) self:Refresh(state,"standard") end
function D:RefreshCompact(state) self:Refresh(state,"compact") end
function D:RefreshAll(force)
    local party=RP.PartyFrames
    if not party then return end
    for _,state in pairs(party.entries or {}) do self:Refresh(state,"standard",force) end
    for _,state in pairs(party.compact or {}) do self:Refresh(state,"compact",force) end
end
function D:UpdateSettings()
    self:Initialize(); self:RefreshAll(true)
end

function D:Initialize()
    if self.initialized then return end
    self.initialized=true
    local worker=CreateFrame("Frame"); self.worker=worker; worker:Hide()
    worker:SetScript("OnUpdate",function(_,elapsed)
        D.elapsed=(D.elapsed or 0)+elapsed
        if D.elapsed<.25 then return end
        D.elapsed=0
        for record in pairs(D.active) do
            if Enabled() and record.state.active and Visible(record.state.native) and FriendlyAlive(record.unit) then D:Paint(record)
            else D:Forget(record.state) end
        end
    end)
    local party=RP.PartyFrames
    if party and type(hooksecurefunc)=="function" then
        hooksecurefunc(party,"RefreshStandard",function(_,state) D:RefreshStandard(state) end)
        hooksecurefunc(party,"ApplyCompact",function(_,state) D:RefreshCompact(state) end)
        for _,method in ipairs({"ClearStandard","HideCompact","ReleaseStandard","ReleaseCompact"}) do
            hooksecurefunc(party,method,function(_,state) D:Forget(state) end)
        end
    end
    local events=CreateFrame("Frame"); self.events=events
    for _,event in ipairs({"UNIT_AURA","GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","SPELLS_CHANGED","LEARNED_SPELL_IN_SKILL_LINE",
        "LEARNED_SPELL_IN_TAB","UNIT_PET","UNIT_FLAGS","UNIT_CONNECTION","UNIT_FACTION","PLAYER_SPECIALIZATION_CHANGED",
        "UPDATE_SHAPESHIFT_FORM","SPELL_UPDATE_COOLDOWN","SPELL_UPDATE_CHARGES",
        "SPELL_UPDATE_USABLE","LOSS_OF_CONTROL_ADDED","LOSS_OF_CONTROL_UPDATE"}) do pcall(events.RegisterEvent,events,event) end
    events:SetScript("OnEvent",function(_,event,unit)
        if event=="UNIT_AURA" then
            if not Unit(unit) then return end
            for state,record in pairs(D.records) do
                -- Native containers subscribe to UNIT_AURA themselves. Resetting
                -- their binding on every aura update would cause icon flicker.
                if record.unit==unit and record.mode~="native" then D:Refresh(state,record.kind,true) end
            end
        elseif event=="SPELL_UPDATE_COOLDOWN" or event=="SPELL_UPDATE_CHARGES" or event=="SPELL_UPDATE_USABLE"
            or event=="LOSS_OF_CONTROL_ADDED" or event=="LOSS_OF_CONTROL_UPDATE" then
            for record in pairs(D.active) do D:Paint(record) end
        elseif event=="UNIT_FLAGS" or event=="UNIT_CONNECTION" or event=="UNIT_FACTION" then
            if unit=="pet" then D.spells=nil; D:RefreshAll(true)
            elseif Unit(unit) then
                for state,record in pairs(D.records) do if record.unit==unit then D:Refresh(state,record.kind,true) end end
            end
        else
            if event=="UNIT_PET" and unit~="player" then return end
            D.spells=nil; D:RefreshAll(true)
        end
    end)
end
