-- Historical mining locations, followed as a bounded, owner-scoped farm circuit.
-- The navigator verifies actual walking terrain; no road identity is inferred.
local _, RP = ...
local M = _G.RicoMining or RP.Mining
local R = {owner="RicoMining",state="idle",message="Choose a saved location or start a farm route.",index=0,total=0}
M.Routes = R

local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Number(value)
    return Public(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function Table(value)
    return Public(value) and type(value)=="table" and (not canaccesstable or canaccesstable(value))
end
local function String(value) return Public(value) and type(value)=="string" end
local function ID(value) return Number(value) and value>0 and value<2147483648 and value%1==0 end
local function Point(value)
    return Table(value) and ID(value.map) and Number(value.x) and Number(value.y)
        and value.x>=0 and value.x<=1 and value.y>=0 and value.y<=1
end
local function Read(fn,...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...)
    if ok and Public(value) then return value end
end
local function Field(object,key)
    if not Table(object) and not (Public(object) and type(object)=="userdata") then return nil end
    local ok,value=pcall(function()return object[key]end)
    if ok and Public(value) then return value end
end
local function Combat() return Read(InCombatLockdown)==true end
local function Player()
    local map=Read(C_Map and C_Map.GetBestMapForUnit,"player")
    if not ID(map) then return nil end
    local position=Read(C_Map and C_Map.GetPlayerMapPosition,map,"player")
    local x,y=Field(position,"x"),Field(position,"y")
    if not Number(x) or not Number(y) then
        local method=Field(position,"GetXY")
        if type(method)=="function" then
            local ok,px,py=pcall(method,position)
            if ok and Number(px) and Number(py) then x,y=px,py end
        end
    end
    local result={map=map,x=x,y=y}
    return Point(result) and result or nil
end
local function Name(node)
    local value=String(node.name) and node.name or node.nodeName
    return String(value) and value~="" and value:sub(1,100) or "Saved mining location"
end
local function World(point)
    if Number(point.worldMap) and Number(point.wx) and Number(point.wy) then return point.worldMap,point.wx,point.wy end
    local api=C_Map and C_Map.GetWorldPosFromMapPos
    if type(api)~="function" or type(CreateVector2D)~="function" then return nil end
    local vector=Read(CreateVector2D,point.x,point.y)
    if not vector then return nil end
    local ok,map,position=pcall(api,point.map,vector)
    local x,y=Field(position,"x"),Field(position,"y")
    if ok and Number(map) and Number(x) and Number(y) then return map,x,y end
end
local function ScopeMap(map)
    local micro=Enum and Enum.UIMapType and Enum.UIMapType.Micro
    local seen={}
    for index=1,8 do
        if seen[map] then return nil end
        seen[map]=true
        local info=Read(C_Map and C_Map.GetMapInfo,map)
        if not Table(info) or micro==nil or Field(info,"mapType")~=micro then return map end
        local parent=Field(info,"parentMapID")
        if not ID(parent) then return nil end
        map=parent
    end
    return nil
end
local function Reproject(point,map)
    if point.map==map then return {map=map,x=point.x,y=point.y} end
    local world,x,y=World(point)
    local api=C_Map and C_Map.GetMapPosFromWorldPos
    if world==nil or type(api)~="function" or type(CreateVector2D)~="function" then return nil end
    local vector=Read(CreateVector2D,x,y)
    if not vector then return nil end
    local ok,result,position=pcall(api,world,vector,map)
    local px,py=Field(position,"x"),Field(position,"y")
    local value={map=result,x=px,y=py}
    if ok and Public(result) and result==map and Point(value) then return value end
end
local function WorldDistance(a,b)
    local map,x,y=World(a)
    local other,px,py=World(b)
    if map~=nil and map==other then return (x-px)^2+(y-py)^2 end
end
local function Projection(map)
    local fallback={xx=8000,xy=0,yx=0,yy=8000,hx=.001,hy=.001}
    local api=C_Map and C_Map.GetWorldPosFromMapPos
    if type(api)~="function" or type(CreateVector2D)~="function" then return fallback end
    local function World(x,y)
        local vector=Read(CreateVector2D,x,y)
        if not vector then return nil end
        local ok,world,position=pcall(api,map,vector)
        local px,py=Field(position,"x"),Field(position,"y")
        if ok and Number(world) and Number(px) and Number(py) then return world,px,py end
    end
    local world,x,y=World(0,0)
    local wx,ax,ay=World(1,0)
    local wy,bx,by=World(0,1)
    if world==nil or wx~=world or wy~=world then return fallback end
    local xx,xy,yx,yy=ax-x,ay-y,bx-x,by-y
    local lx,ly=math.sqrt(xx*xx+xy*xy),math.sqrt(yx*yx+yy*yy)
    if lx<=0 or ly<=0 then return fallback end
    return {xx=xx,xy=xy,yx=yx,yy=yy,hx=8/lx,hy=8/ly}
end
local function Distance(a,b,projection)
    local dx,dy=(a.metricX or a.x)-(b.metricX or b.x),(a.metricY or a.y)-(b.metricY or b.y)
    return (dx*projection.xx+dy*projection.yx)^2+(dx*projection.xy+dy*projection.yy)^2
end

function R:Provider()
    local provider=rawget(_G,"ShortestPathForever")
    local api=Table(provider) and provider.API
    local bridge=Table(provider) and provider.RicoRoutes
    if not Table(api) or not Public(api.version) or api.version~=1 or type(api.NavigateRoute)~="function"
        or type(api.CurrentStop)~="function" or type(api.Cancel)~="function" or type(api.Ended)~="function" then
        return nil,nil,"Navigation is not ready. Use /reload to load Rico navigation."
    end
    if not Table(bridge) or not Public(bridge.version) or bridge.version~=1 or not Number(bridge.minor) or bridge.minor<2
        or not Public(bridge.providerVersion) or bridge.providerVersion~="v1.22.38" or type(bridge.CanStart)~="function" or type(bridge.GetStatus)~="function" then
        return nil,nil,"The mining navigation bridge is unavailable. Use /reload after updating Rico."
    end
    return api,bridge
end

function R:SetWorking()
    if not self.driver then return end
    if self.active then
        if not self.driver:GetScript("OnUpdate") then
            self.elapsed=0
            self.driver:SetScript("OnUpdate",function(_,elapsed)
                R.elapsed=R.elapsed+elapsed
                if R.elapsed>=0.5 then R.elapsed=0; R:Refresh() end
            end)
        end
    else self.driver:SetScript("OnUpdate",nil) end
end

function R:BeginLeg()
    local api,bridge,reason=self:Provider()
    if not api then return false,reason end
    if Combat() then return false,"Finish combat before planning a mining route." end
    if Read(bridge.CanStart,self.owner)~=true then
        return false,"Another journey is active. Stop it before starting the mining route."
    end
    local node=self.nodes and self.nodes[self.index]
    if not Point(node) then return false,"This saved location has no usable coordinates." end
    local ok=Read(api.NavigateRoute,self.owner,{{map=node.map,x=node.x,y=node.y,title=Name(node),kind="point",hold=true,radius=4}})
    if ok~=true then return false,"The navigator could not start this mining destination. Try another location." end
    self.waitingAdvance=false
    self.state,self.message="searching","Checking walking terrain to "..Name(node).."."
    return true,self.message
end

function R:Start(nodes,options)
    options=Table(options) and options or {}
    if Combat() then return false,"Finish combat before planning a mining route." end
    local api,bridge,reason=self:Provider()
    if not api then return false,reason end
    if Read(bridge.CanStart,self.owner)~=true then
        return false,"Another journey is active. Stop it before starting the mining route."
    end
    local here=Player()
    if not here then return false,"Your map position is unavailable. Try again outdoors." end
    local scope=options.single==true and here.map or ScopeMap(here.map)
    local origin=scope and Reproject(here,scope)
    if not origin then return false,"Your starter-zone position could not be converted to the parent map. Try again in the main zone." end
    if not Table(nodes) and type(M.GetNodes)=="function" then nodes=M:GetNodes() end
    if not Table(nodes) then return false,"No saved mining locations are available yet. Mine a vein first." end
    local skill=type(M.GetSkill)=="function" and M:GetSkill() or nil
    local current=Table(skill) and (Number(skill.effective) and skill.effective or skill.current)
    if not options.single and Table(skill) and skill.known==false then return false,"Learn Mining before starting a farm route." end
    local projection=Projection(scope)
    local candidates,buckets,scopes={}, {}, {[here.map]=scope}
    local projectionSkipped=0
    for index=1,math.min(#nodes,20000) do
        local node=nodes[index]
        if Point(node) then
            if scopes[node.map]==nil then scopes[node.map]=ScopeMap(node.map) or false end
        end
        if Point(node) and (options.single==true or scopes[node.map]==scope)
            and (options.single==true or not Number(current) or not Number(node.requiredSkill) or node.requiredSkill<=current) then
            local metric=options.single==true and {map=node.map,x=node.x,y=node.y} or Reproject(node,scope)
            if not metric then projectionSkipped=projectionSkipped+1
            else
            local bx,by=math.floor(metric.x/projection.hx),math.floor(metric.y/projection.hy)
            local duplicate=false
            for dx=-1,1 do
                for dy=-1,1 do
                    local bucket=buckets[scope..":"..(bx+dx)..":"..(by+dy)]
                    for _,point in ipairs(bucket or {}) do
                        if Distance(metric,point,projection)<=64 then duplicate=true; break end
                    end
                    if duplicate then break end
                end
                if duplicate then break end
            end
            if not duplicate then
                local point={map=node.map,x=node.x,y=node.y,name=Name(node),id=node.id,oreID=node.oreID,
                    reference=Public(node.reference) and node.reference==true,
                    observed=Public(node.observed) and node.observed==true,
                    metricX=metric.x,metricY=metric.y,worldMap=node.worldMap,wx=node.wx,wy=node.wy}
                point.rank=Distance(point,origin,projection)
                candidates[#candidates+1]=point
                local key=scope..":"..bx..":"..by
                buckets[key]=buckets[key] or {}; buckets[key][#buckets[key]+1]=point
            end
            end
        end
    end
    if #candidates==0 and projectionSkipped>0 then return false,"The saved mining locations could not be converted from the starter map. Try a location on the main zone map." end
    if #candidates==0 then return false,"No matching saved locations in this zone fit your current Mining skill." end
    table.sort(candidates,function(a,b)return a.rank<b.rank end)
    local truncated=math.max(0,#candidates-1024)
    for index=#candidates,1025,-1 do candidates[index]=nil end
    local closeLoop=Public(options.closeLoop) and options.closeLoop==true
    local maximum=Number(options.maxStops) and math.max(1,math.min(24,math.floor(options.maxStops))) or 24
    if closeLoop then maximum=math.min(23,maximum) end
    local ordered,from={},origin
    while #candidates>0 and #ordered<maximum do
        local best,score=1,nil
        for index,node in ipairs(candidates) do
            local distance=Distance(node,from,projection)
            if not score or distance<score then best,score=index,distance end
        end
        local nextNode=table.remove(candidates,best)
        ordered[#ordered+1]=nextNode; from=nextNode
    end
    -- The circuit is finite. Returning to its first vein is an explicit option,
    -- never an endless replay of historical locations.
    if closeLoop and #ordered>1 and #ordered<24 then
        local first=ordered[1]
        ordered[#ordered+1]={map=first.map,x=first.x,y=first.y,name=first.name,id=first.id,oreID=first.oreID,
            reference=first.reference,observed=first.observed,worldMap=first.worldMap,wx=first.wx,wy=first.wy}
    end
    local old={nodes=self.nodes,index=self.index,total=self.total,active=self.active,waitingAdvance=self.waitingAdvance,state=self.state,message=self.message}
    self.nodes,self.index,self.total,self.active,self.waitingAdvance=ordered,1,#ordered,true,false
    local started,message=self:BeginLeg()
    if not started then
        self.nodes,self.index,self.total,self.active,self.waitingAdvance,self.state,self.message=
            old.nodes,old.index,old.total,old.active,old.waitingAdvance,old.state,old.message
        return false,message
    end
    self.remaining=#candidates+truncated
    self.projectionSkipped=projectionSkipped
    self:SetWorking()
    return true,"Farm route started: "..self.total.." saved location"..(self.total==1 and "." or "s.")
end

function R:NavigateNode(node)
    return self:Start({node},{single=true,maxStops=1})
end

function R:Advance()
    if self.index>=self.total then
        self.active,self.waitingAdvance,self.state,self.message=false,false,"complete","Farm route complete. These were saved locations; veins may not currently be present."
    else
        self.index=self.index+1; self.waitingAdvance=true
        if Combat() then self.state,self.message="waiting","Next mining location is ready. Navigation resumes after combat."
        else
            local ok,message=self:BeginLeg()
            if not ok then self.active,self.state,self.message=false,"stopped",message end
        end
    end
    self:SetWorking()
end

function R:Next()
    if not self.active or self.waitingAdvance then return false,"No current mining location can be skipped." end
    local api,_,reason=self:Provider()
    if not api then return false,reason end
    if not Read(api.CurrentStop,self.owner) then
        self:Refresh()
        return false,"This mining route no longer owns navigation."
    end
    if Read(api.Cancel,self.owner)~=true then return false,"The navigator could not leave this mining location." end
    self:Advance()
    return true,self.message
end

-- A historical location stays selected while the player mines. Empty veins can
-- be skipped explicitly; proximity alone never pretends the vein was gathered.
function R:OnMinedNode(node)
    if not self.active or self.waitingAdvance or not Point(node) then return end
    local target=self.nodes and self.nodes[self.index]
    if not Point(target) then return end
    local matching=String(node.id) and String(target.id) and node.id==target.id
    if not matching and (target.reference==true or not (String(node.id) and String(target.id)))
        and Number(node.oreID) and node.oreID==target.oreID then
        local distance=WorldDistance(node,target)
        matching=distance~=nil and distance<=25^2
    end
    if matching then self:Next() end
end

function R:Refresh()
    if not self.active or self.refreshing then return end
    self.refreshing=true
    local api,bridge,reason=self:Provider()
    if not api then
        self.active,self.state,self.message=false,"unavailable",reason
    elseif self.waitingAdvance then
        if not Combat() then
            local ok,message=self:BeginLeg()
            if not ok then self.active,self.state,self.message=false,"stopped",message end
        end
    elseif not Read(api.CurrentStop,self.owner) then
        local ended=Read(api.Ended,self.owner)
        if ended=="arrived" then
            self:Advance()
        else
            self.active,self.state,self.message=false,"stopped","Mining route stopped or replaced by another journey."
        end
    else
        local status=Read(bridge.GetStatus,self.owner)
        if Table(status) and String(status.state) and String(status.message) then
            self.state,self.message=status.state,status.message
        end
    end
    self.refreshing=false
    self:SetWorking()
end

function R:Stop()
    local api=self:Provider()
    if api and Read(api.CurrentStop,self.owner) and Read(api.Cancel,self.owner)~=true then
        return false,"The navigator could not stop this mining route."
    end
    self.active,self.waitingAdvance,self.state,self.message=false,false,"idle","Mining route stopped."
    self:SetWorking()
    return true,self.message
end

function R:GetStatus()
    self:Refresh()
    local api,_,reason=self:Provider()
    local node=self.nodes and self.nodes[self.index]
    local message=api and self.message or reason
    if self.projectionSkipped and self.projectionSkipped>0 then message=message.." Some locations lacked usable map coordinates and were skipped." end
    return {ready=api~=nil,active=self.active==true,state=api and self.state or "unavailable",message=message,
        index=self.index,total=self.total,currentName=node and Name(node),remaining=self.remaining or 0,
        canNext=self.active==true and not self.waitingAdvance and api~=nil and Read(api.CurrentStop,self.owner)~=nil}
end

function R:Initialize()
    if self.driver then return end
    self.driver=CreateFrame("Frame")
    self.driver:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.driver:SetScript("OnEvent",function() R:Refresh() end)
end
