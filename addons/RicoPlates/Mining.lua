-- Only an actual successful Mining cast followed by received gathering loot creates a location.
-- Map marks are historical, approximate gathering positions, never live ore detection.
local _, RP = ...
local M = RP.Mining
M.name, M.version = "RicoMining", "1.0.2"
M.defaults = {pins=true, skillFilter=false}
M.session = {items={}, quantity=0, nodes=0}
local MAX_NODES, MAX_LISTENERS = 5000, 12
local MINING_SPELLS = {[2575]=true,[2576]=true,[3564]=true,[10248]=true}
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Table(value) return Public(value) and type(value)=="table" and (not canaccesstable or canaccesstable(value)) end
local function Number(value) return Public(value) and type(value)=="number" and value==value and math.abs(value)<math.huge end
local function String(value) return Public(value) and type(value)=="string" end
local function Field(value,key)
    if not Table(value) and not (Public(value) and type(value)=="userdata") then return end
    local ok, result = pcall(function() return value[key] end)
    if ok and Public(result) then return result end
end
local function Read(fn,...)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,...)
    if ok and Public(value) then return value end
end
local function ID(value) return Number(value) and value>=1 and value%1==0 and value<2147483648 end
local function Point(map,x,y) return ID(map) and Number(x) and Number(y) and x>=0 and x<=1 and y>=0 and y<=1 end
local function Text(value,limit)
    if not String(value) then return end
    value=value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("[%c]"," ")
    return value:sub(1,limit or 100)
end
local function Clock() return Read(GetTime) or 0 end
local function Stamp() local value=Read(GetServerTime) or Read(time); return Number(value) and math.floor(value) or 0 end
local function CleanNumber(value,min,max,default)
    return Number(value) and value>=min and value<=max and value or default
end
M.IsSecret = function(value) return not Public(value) end
M.Number, M.String, M.Table = Number, String, Table

function M:Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff59e4bfRico Mining|r: "..message) end
end
function M:Subscribe(callback)
    if type(callback)~="function" then return false end
    self.listeners=self.listeners or {}
    for _, old in ipairs(self.listeners) do if old==callback then return true end end
    if #self.listeners>=MAX_LISTENERS then return false end
    self.listeners[#self.listeners+1]=callback
    return true
end
function M:Refresh(viewOnly)
    if self.Map and self.Map.Refresh then self.Map:Refresh(viewOnly) end
    if self.UI and self.UI.Refresh then self.UI:Refresh() end
    for _, callback in ipairs(self.listeners or {}) do pcall(callback,self) end
end
function M:QueueRefresh(viewOnly)
    if not viewOnly then self.catalogRefreshPending=true end
    if self.refreshPending then return end
    self.refreshPending=true
    local function refresh()
        local refreshViewOnly=not self.catalogRefreshPending
        self.refreshPending,self.catalogRefreshPending=nil,nil
        self:Refresh(refreshViewOnly)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1,refresh) else refresh() end
end
function M:SetOption(key,value)
    if not self.db or type(self.defaults[key])~="boolean" or type(value)~="boolean" then return false end
    if self.db[key]~=value then
        self.db[key]=value
        self:QueueRefresh(true)
    end
    return true
end

function M:GetSkill()
    local skill = Read(C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID,186)
    if not Table(skill) then
        local count=Read(C_SkillInfo and C_SkillInfo.GetNumSkillLines or GetNumSkillLines)
        if Number(count) and count>=0 then
            for index=1,math.min(250,math.floor(count)) do
                local info=Read(C_SkillInfo and C_SkillInfo.GetSkillLineInfo,index)
                if Table(info) and Field(info,"skillID")==186 then skill=info; break end
                if not info and type(GetSkillLineInfo)=="function" then
                    local ok,name,header,_,rank,temp,modifier,maxRank=pcall(GetSkillLineInfo,index)
                    local miningName=Read(C_Spell and C_Spell.GetSpellName,2575) or "Mining"
                    if ok and String(name) and Public(header) and not header and name==miningName then
                        skill={name=name,rank=rank,tempPoints=temp,modifier=modifier,maxRank=maxRank}; break
                    end
                end
            end
        end
    end
    local rank,maximum=Field(skill,"rank"),Field(skill,"maxRank")
    local known=Number(rank) and Number(maximum) and rank>=0 and maximum>0
    local modifier=CleanNumber(Field(skill,"modifier"),-1000,1000,0)+CleanNumber(Field(skill,"tempPoints"),-1000,1000,0)
    return {known=known,learned=known,name="Mining",current=known and rank or nil,max=known and maximum or nil,
        effective=known and math.max(0,rank+modifier) or nil,modifier=modifier}
end

function M:GetRequirement(oreID,nodeName)
    local name=Text(nodeName)
    local observed=name and self.db and Table(self.db.requirements) and self.db.requirements[name:lower()]
    if Number(observed) and observed>=1 and observed<=1000 then return observed,"Observed tooltip" end
    local node=name and self.Data.nodes[name:lower()]
    if node then return node.requiredSkill,"Classic reference" end
    if name and name~="" and name~="Mining vein" then return end
    local ore=self.Data.byID[oreID]
    if ore then return ore.requiredSkill,"Classic reference" end
end

function M:GetSkillHelp()
    local skill=self:GetSkill()
    local help={skill=skill,entries={},nextTraining=skill.known and skill.current>=skill.max-5 and skill.max<300 or false}
    local best,nextOre
    for _, ore in ipairs(self.Data.ores) do
        local required,source=self:GetRequirement(ore.id,ore.nodeName)
        local eligible
        if skill.known then eligible=skill.effective>=required end
        local entry={oreID=ore.id,name=ore.name,requiredSkill=required,source=source,canMine=eligible,icon=ore.icon,quest=ore.quest}
        help.entries[#help.entries+1]=entry
        if skill.known and not ore.quest then
            if skill.effective>=required then best=entry elseif not nextOre then nextOre=entry end
        end
    end
    help.recommended,help.nextOre=best,nextOre
    if not skill.known then help.message="Learn Mining from a trainer to see your skill and eligible ores."
    elseif help.nextTraining then help.message="Your Mining skill is near its current cap. Check a Mining trainer for the next rank."
    elseif best then help.message="At your skill, try "..best.name..". Requirements marked Classic reference are not confirmed Forever observations."
    else help.message="Mine veins you can gather. Hover a vein to learn its displayed requirement." end
    return help
end

function M:GetNodes(mapFilter,oreFilter)
    local result={}
    if not self.db then return result end
    if mapFilter~=nil and not ID(mapFilter) or oreFilter~=nil and not ID(oreFilter) then return result end
    for _, node in ipairs(self.db.nodes) do
        if (not ID(mapFilter) or node.map==mapFilter) and (not ID(oreFilter) or node.oreID==oreFilter) then
            local copy={}
            for key,value in pairs(node) do copy[key]=value end
            copy.requiredSkill,copy.requirementSource=self:GetRequirement(copy.oreID,copy.name)
            result[#result+1]=copy
        end
    end
    if type(self.GetReferenceNodes)=="function" then
        local grid={}
        for _,node in ipairs(result) do
            grid[node.map]=grid[node.map] or {}
            local mapGrid=grid[node.map]
            local oreID=node.oreID or 0
            mapGrid[oreID]=mapGrid[oreID] or {}
            local oreGrid=mapGrid[oreID]
            local key=math.floor(node.x/0.0025)*1000+math.floor(node.y/0.0025)
            oreGrid[key]=oreGrid[key] or {}; oreGrid[key][#oreGrid[key]+1]=node
        end
        local references=self:GetReferenceNodes(mapFilter,oreFilter)
        local requirements={}
        for _, reference in ipairs(references or {}) do
            local covered=false
            local gx,gy=math.floor(reference.x/0.0025),math.floor(reference.y/0.0025)
            local oreGrid=grid[reference.map] and grid[reference.map][reference.oreID or 0]
            if oreGrid then
                for dx=-1,1 do
                    for dy=-1,1 do
                        for _,node in ipairs(oreGrid[(gx+dx)*1000+gy+dy] or {}) do
                            if (node.x-reference.x)^2+(node.y-reference.y)^2<=0.0025^2 then covered=true; break end
                        end
                        if covered then break end
                    end
                    if covered then break end
                end
            end
            if not covered then
                local copy={}
                for key,value in pairs(reference) do copy[key]=value end
                local learned=requirements[copy.name]
                if not learned then
                    local required,source=self:GetRequirement(copy.oreID,copy.name)
                    learned={required=required,source=source}; requirements[copy.name]=learned
                end
                if Number(learned.required) then copy.requiredSkill,copy.requirementSource=learned.required,learned.source end
                result[#result+1]=copy
            end
        end
    end
    table.sort(result,function(a,b)
        if (a.observed==true)~=(b.observed==true) then return a.observed==true end
        local aa,bb=a.lastSeen or 0,b.lastSeen or 0
        if aa~=bb then return aa>bb end
        return a.id<b.id
    end)
    return result
end
function M:GetStats()
    local visits=0
    for _, node in ipairs(self.db and self.db.nodes or {}) do visits=visits+node.count end
    local elapsed=self.session.started and math.max(0,Clock()-self.session.started) or 0
    local items={}; for id,count in pairs(self.session.items) do items[id]=count end
    return {nodes=self.db and #self.db.nodes or 0,observedNodes=self.db and #self.db.nodes or 0,
        referenceNodes=self.Reference and self.Reference.total or 0,visits=visits,sessionNodes=self.session.nodes,
        sessionQuantity=self.session.quantity,sessionItems=items,started=self.session.started,elapsed=elapsed,
        perHour=elapsed>=60 and self.session.quantity*3600/elapsed or nil}
end

function M:Position()
    local map=Read(C_Map and C_Map.GetBestMapForUnit,"player")
    local pos=ID(map) and Read(C_Map and C_Map.GetPlayerMapPosition,map,"player")
    local x,y=Field(pos,"x"),Field(pos,"y")
    if not Point(map,x,y) then return end
    local zone=Text(Read(GetZoneText)) or Text(Field(Read(C_Map and C_Map.GetMapInfo,map),"name")) or ("Map "..map)
    local result={map=map,x=x,y=y,zone=zone}
    if C_Map and type(C_Map.GetWorldPosFromMapPos)=="function" and CreateVector2D then
        local ok,worldMap,world=pcall(C_Map.GetWorldPosFromMapPos,map,CreateVector2D(x,y))
        local wx,wy=Field(world,"x"),Field(world,"y")
        if ok and Number(worldMap) and Number(wx) and Number(wy) then result.worldMap,result.wx,result.wy=worldMap,wx,wy end
    end
    return result
end

function M:IsMiningSpell(spellID)
    if not ID(spellID) then return false end
    if MINING_SPELLS[spellID] then return true end
    local name=Read(C_Spell and C_Spell.GetSpellName,spellID)
    local mining=Read(C_Spell and C_Spell.GetSpellName,2575)
    return String(name) and String(mining) and name==mining
end

function M:CaptureTooltip(tooltip,data)
    if not self.db or not Table(data) or not Table(Field(data,"lines")) then return end
    local lines=Field(data,"lines")
    local name=Text(Field(lines[1],"leftText"))
    if not name or name=="" then return end
    local kind=Field(data,"type")
    local objectKind=Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object
    if kind~=objectKind or objectKind==nil then return end
    local mining=Read(C_Spell and C_Spell.GetSpellName,2575) or "Mining"
    local requirement,miningLine
    for index=2,math.min(#lines,12) do
        local text=Text(Field(lines[index],"leftText"),220)
        if text and String(mining) and text:find(mining,1,true) then
            miningLine=true
            -- Read the explicit '(N)' requirement the game shows; no failure/skill-up number inference.
            local value=tonumber(text:match("%((%d+)%)"))
            if Number(value) and value>=1 and value<=1000 then requirement=value; break end
        end
    end
    if not miningLine and not self.Data.nodes[name:lower()] then return end
    local key=name:lower()
    local requirements=self.db.requirements
    if requirement and requirements[key]~=requirement then
        local count=0
        if not requirements[key] then for _ in pairs(requirements) do count=count+1 end end
        if count<500 then
            requirements[key]=requirement
            self:QueueRefresh()
        end
    end
    self.hover={name=name,requiredSkill=requirement,at=Clock(),position=self:Position()}
end

function M:BeginCast(unit,target,castGUID,spellID)
    if not String(unit) or unit~="player" then return end
    -- Any new player cast invalidates an unfinished gather, including a later unrelated loot window.
    self.pending,self.lootWindow=nil,nil
    if not self:IsMiningSpell(spellID) then return end
    local name=Text(target)
    local hover=self.hover
    if (not name or name=="") and hover and Clock()-hover.at<=3 then name=hover.name end
    local position=self:Position()
    if not position then return end
    self.pending={name=name,position=position,castGUID=String(castGUID) and castGUID or nil,
        spellID=spellID,at=Clock(),succeeded=false}
end
function M:FinishCast(unit,castGUID,spellID)
    if not String(unit) or unit~="player" or not self:IsMiningSpell(spellID) then return end
    local pending=self.pending
    if not pending or Clock()-pending.at>20 then return end
    if pending.castGUID and (not String(castGUID) or pending.castGUID~=castGUID) then return end
    pending.succeeded,pending.successAt=true,Clock()
    self:CommitWindow()
end
function M:FailedCast(unit,castGUID)
    if String(unit) and unit=="player" and self.pending
        and (not self.pending.castGUID or String(castGUID) and self.pending.castGUID==castGUID) then
        self.pending,self.lootWindow=nil,nil
    end
end

local function LootSource(slot)
    if type(GetLootSourceInfo)~="function" then return nil end
    local values={pcall(GetLootSourceInfo,slot)}
    if not values[1] then return false end
    local present=false
    for index=2,math.min(#values,18),2 do
        local guid=values[index]
        if not Public(guid) then return false end
        if String(guid) and guid~="" then
            present=true
            if guid:match("^GameObject%-") then return true end
        end
    end
    if present then return false end
    return nil
end
function M:SnapshotLoot()
    local pending=self.pending
    if not pending or Clock()-pending.at>20 or pending.successAt and Clock()-pending.successAt>8 then return end
    if Read(IsFishingLoot)==true then return end
    local count=Read(GetNumLootItems)
    if not Number(count) or count<1 or count>100 then return end
    local window=self.lootWindow or {slots={},pending=pending}
    if window.pending~=pending then return end
    self.lootWindow=window
    for slot=1,count do
        if not window.slots[slot] then
            local link=Read(GetLootSlotLink,slot)
            local id=String(link) and tonumber(link:match("item:(%d+)"))
            local ok,quantity=false,nil
            if type(GetLootSlotInfo)=="function" then
                local got,_,_,amount=pcall(GetLootSlotInfo,slot)
                ok,quantity=got,amount
            end
            local source=LootSource(slot)
            if ID(id) and ok and Number(quantity) and quantity>0 and quantity<=10000 and source~=false then
                window.slots[slot]={id=id,quantity=math.floor(quantity),objectSource=source==true}
            end
        end
    end
end
function M:ReceiveLoot(slot)
    if not ID(slot) then return end
    local entry=self.lootWindow and self.lootWindow.slots[slot]
    if not entry or entry.received then return end
    entry.received=true
    self:CommitWindow()
end

function M:RecordNode(pending,oreID)
    local pos=pending.position
    if not pos or not Point(pos.map,pos.x,pos.y) then return end
    local ore=self.Data.byID[oreID]
    local name=pending.name
    if not name or name=="" then name=ore and ore.nodeName or "Mining vein" end
    local known=self.Data.nodes[name:lower()]
    oreID=known and known.oreID or oreID
    local best
    for _, node in ipairs(self.db.nodes) do
        if node.map==pos.map and node.oreID==oreID and node.name==name then
            local near
            if Number(node.wx) and Number(pos.wx) and node.worldMap==pos.worldMap then
                near=(node.wx-pos.wx)^2+(node.wy-pos.wy)^2<=20^2
            else near=(node.x-pos.x)^2+(node.y-pos.y)^2<=0.0015^2 end
            if near then best=node; break end
        end
    end
    local stamp=Stamp()
    if not best then
        self.db.serial=self.db.serial+1
        best={id="mined:"..self.db.serial,map=pos.map,x=pos.x,y=pos.y,wx=pos.wx,wy=pos.wy,worldMap=pos.worldMap,
            oreID=oreID,name=name,nodeName=name,zone=pos.zone,firstSeen=stamp,lastSeen=stamp,count=0,
            positionSource="Gathering position (approximate)",source="Observed mining",observed=true}
        self.db.nodes[#self.db.nodes+1]=best
        if #self.db.nodes>MAX_NODES then
            local oldest=1
            for index=2,#self.db.nodes do if self.db.nodes[index].lastSeen<self.db.nodes[oldest].lastSeen then oldest=index end end
            table.remove(self.db.nodes,oldest)
        end
    end
    best.lastSeen,best.count=stamp,math.min(1000000,best.count+1)
    return best
end

function M:CommitWindow()
    local window=self.lootWindow
    local pending=window and window.pending
    if not pending or pending~=self.pending or not pending.succeeded or not self.db then return end
    if Clock()-pending.at>20 or Clock()-(pending.successAt or 0)>8 then return end
    local oreID,objectSource,received
    for _, entry in pairs(window.slots) do
        if entry.received then
            received=true
            if self.Data.byID[entry.id] then oreID=entry.id end
            objectSource=objectSource or entry.objectSource
        end
    end
    if not received then return end
    local known=pending.name and self.Data.nodes[pending.name:lower()]
    if not oreID and known then oreID=known.oreID end
    if not oreID and not objectSource then return end
    if not window.node then
        -- Unknown Forever ores remain historical locations too, without inventing a skill or ore category.
        window.node=self:RecordNode(pending,oreID)
        if window.node then
            self.session.nodes=self.session.nodes+1
            if self.Routes and self.Routes.OnMinedNode then self.Routes:OnMinedNode(window.node) end
        end
    end
    if not window.node then return end
    for _, entry in pairs(window.slots) do
        if entry.received and not entry.credited then
            entry.credited=true
            self.session.started=self.session.started or Clock()
            self.session.items[entry.id]=(self.session.items[entry.id] or 0)+entry.quantity
            self.session.quantity=self.session.quantity+entry.quantity
        end
    end
    self:QueueRefresh()
end

function M:Initialize()
    if self.initialized then return end
    self.initialized=true
    if not Table(RicoMiningDB) then RicoMiningDB={} end
    self.db=RicoMiningDB
    local db=self.db
    if not Table(db.nodes) then db.nodes={} end
    if not Table(db.requirements) then db.requirements={} end
    db.serial=math.floor(CleanNumber(db.serial,0,2147480000,0))
    local valid,seenIDs={},{}
    for index=1,math.min(#db.nodes,MAX_NODES+100) do
        local node=db.nodes[index]
        if Table(node) and Point(Field(node,"map"),Field(node,"x"),Field(node,"y")) and String(Field(node,"name")) then
            local copy={id=Text(Field(node,"id"),70) or ("restored:"..index),map=node.map,x=node.x,y=node.y,
                name=Text(node.name),nodeName=Text(node.name),oreID=ID(Field(node,"oreID")) and node.oreID or nil,
                zone=Text(Field(node,"zone")) or ("Map "..node.map),firstSeen=CleanNumber(Field(node,"firstSeen"),0,100000000000,0),
                lastSeen=CleanNumber(Field(node,"lastSeen"),0,100000000000,0),count=math.floor(CleanNumber(Field(node,"count"),1,1000000,1)),
                source="Observed mining",positionSource="Gathering position (approximate)",observed=true}
            if Number(Field(node,"wx")) and Number(Field(node,"wy")) and Number(Field(node,"worldMap")) then
                copy.wx,copy.wy,copy.worldMap=node.wx,node.wy,node.worldMap
            end
            local serial=tonumber(copy.id:match("^mined:(%d+)$"))
            if Number(serial) and serial<2147480000 then db.serial=math.max(db.serial,serial) end
            if seenIDs[copy.id] then copy.id="restored:"..index end
            seenIDs[copy.id]=true
            valid[#valid+1]=copy
            if #valid>=MAX_NODES then break end
        end
    end
    db.nodes=valid
    local requirements={}
    local count=0
    for name,required in pairs(db.requirements) do
        if String(name) and #name<=100 and Number(required) and required>=1 and required<=1000 then
            requirements[name:lower()]=math.floor(required); count=count+1; if count>=500 then break end
        end
    end
    db.requirements=requirements
    for key,value in pairs(self.defaults) do if type(db[key])~="boolean" then db[key]=value end end
    self.events=CreateFrame("Frame")
    for _, event in ipairs({"UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED",
        "LOOT_READY","LOOT_OPENED","LOOT_SLOT_CLEARED","LOOT_CLOSED","SKILL_LINES_CHANGED","ZONE_CHANGED_NEW_AREA","PLAYER_ENTERING_WORLD"}) do
        pcall(self.events.RegisterEvent,self.events,event)
    end
    self.events:SetScript("OnEvent",function(_,event,...)
        if event=="UNIT_SPELLCAST_SENT" then self:BeginCast(...)
        elseif event=="UNIT_SPELLCAST_SUCCEEDED" then self:FinishCast(...)
        elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then self:FailedCast(...)
        elseif event=="LOOT_READY" or event=="LOOT_OPENED" then self:SnapshotLoot()
        elseif event=="LOOT_SLOT_CLEARED" then self:ReceiveLoot(...)
        elseif event=="LOOT_CLOSED" then self.pending,self.lootWindow=nil,nil
        else self:QueueRefresh(true) end
    end)
    local objectKind=Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object
    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall)=="function" and objectKind then
        pcall(TooltipDataProcessor.AddTooltipPostCall,objectKind,function(tooltip,data) self:CaptureTooltip(tooltip,data) end)
    end
    if self.Map and self.Map.Initialize then self.Map:Initialize() end
    if self.Routes and self.Routes.Initialize then self.Routes:Initialize() end
    if self.UI and self.UI.Initialize then self.UI:Initialize() end
    self:QueueRefresh(true)
end
SLASH_RICOMINING1,SLASH_RICOMINING2="/rm","/ricomining"
SlashCmdList.RICOMINING=function()
    if not M.initialized then M:Initialize() end
    if M.UI and M.UI.Show then M.UI:Show() end
end
