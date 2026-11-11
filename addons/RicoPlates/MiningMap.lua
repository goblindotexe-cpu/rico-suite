-- Historical mining observations, drawn with native map coordinates. No Questie.
local _, RP = ...
local M = RP.Mining or _G.RicoMining
local P = { worldPins={}, miniPins={}, points={}, worldCount=0, miniCount=0, spatial={}, dataVersion=0, catalogDirty=true }
M.Map = P
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CELL, HIT_CELLS, BATCH = 256, 32, 256
local iconCache = {}
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Number(value) return Public(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function Table(value) return Public(value) and type(value)=="table" and (not canaccesstable or canaccesstable(value)) end
local function Call(fn,...) if type(fn)~="function" then return false end; return pcall(fn,...) end
local function XY(position)
    if not Public(position) or position==nil then return end
    local ok,x,y=pcall(function()
        if type(position.GetXY)=="function" then return position:GetXY() end
        return position.x,position.y
    end)
    if ok and Number(x) and Number(y) then return x,y end
end
local function Valid(node)
    return Table(node) and Number(node.map) and node.map>0 and Number(node.x) and Number(node.y)
        and node.x>=0 and node.x<=1 and node.y>=0 and node.y<=1
end
local function Icon(node)
    local key=node.oreID or 0
    if iconCache[key] then return iconCache[key] end
    local ok,icon=Call(C_Item and C_Item.GetItemIconByID or GetItemIcon,node.oreID)
    iconCache[key]=ok and Public(icon) and icon or "Interface\\Icons\\Trade_Mining"
    return iconCache[key]
end
local function Observed(node) return node.observed~=false and node.reference~=true end
local function Age(timestamp)
    local ok,now=Call(GetServerTime or time)
    if not ok or not Number(now) or not Number(timestamp) then return "Last mined: earlier" end
    local minutes=math.max(0,math.floor((now-timestamp)/60))
    return minutes<1 and "Last mined: just now" or minutes<60 and ("Last mined: "..minutes.." min ago")
        or ("Last mined: "..math.floor(minutes/60).." h ago")
end
function P:ShowTooltip(pin)
    local node=pin.node
    if not Valid(node) or not GameTooltip then return end
    GameTooltip:SetOwner(pin,"ANCHOR_RIGHT")
    GameTooltip:SetText(node.name or node.nodeName or "Mining site",0.4,1,0.75)
    GameTooltip:AddLine(Observed(node) and "Personally mined · approximate gathering position" or "Reference location · "..(node.source or "Imported database"),0.9,0.8,0.45,true)
    GameTooltip:AddLine("Historical location; ore may not be present now.",0.8,0.85,0.9,true)
    GameTooltip:AddLine(string.format("%s · %.1f, %.1f",node.zone or "Area",node.x*100,node.y*100),0.8,0.85,0.9)
    if Observed(node) then GameTooltip:AddLine(Age(node.lastSeen),0.65,0.75,0.7) end
    if Number(node.requiredSkill) then GameTooltip:AddLine("Mining "..node.requiredSkill.." · "..(node.requirementSource or "Reference"),0.8,0.85,0.9,true) end
    GameTooltip:AddLine("Click to view this site in Rico Mining.",0.35,0.95,0.75,true)
    GameTooltip:Show()
end
function P:GetPin(index,mini,parent)
    local pool=mini and self.miniPins or self.worldPins
    local pin=pool[index]
    if not pin then
        pin=CreateFrame("Button",nil,parent)
        pin:SetSize(mini and 14 or 19,mini and 14 or 19); pin:EnableMouse(true)
        pin.border=pin:CreateTexture(nil,"BACKGROUND"); pin.border:SetAllPoints(); pin.border:SetTexture(WHITE)
        pin.border:SetVertexColor(0.035,0.075,0.055,0.95)
        pin.icon=pin:CreateTexture(nil,"ARTWORK"); pin.icon:SetPoint("TOPLEFT",1,-1); pin.icon:SetPoint("BOTTOMRIGHT",-1,1)
        pin.icon:SetTexCoord(0.08,0.92,0.08,0.92)
        pin:SetScript("OnEnter",function(self) P:ShowTooltip(self) end)
        pin:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        pin:SetScript("OnClick",function(self)
            if self.node and M.UI then M.UI.selectedID=self.node.id; M.UI:Show() end
        end)
        pool[index]=pin
    elseif pin:GetParent()~=parent then pin:SetParent(parent) end
    return pin
end
function P:HidePins(pool)
    for _,pin in ipairs(pool) do
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
        if pin:IsShown() then pin:Hide() end
        pin.node=nil
    end
end
function P:WorldSourceAllowed(source,map)
    if not Number(source) or not Number(map) then return false end
    if source==map then return true end
    local scope=self.worldScope
    if not scope or scope.map~=map then
        scope={map=map,allowed={},info={}}
        self.worldScope=scope
    end
    if scope.allowed[source]~=nil then return scope.allowed[source] end
    local function Info(id)
        if scope.info[id]==nil then
            local ok,info=Call(C_Map and C_Map.GetMapInfo,id)
            scope.info[id]=ok and Table(info) and info or false
        end
        return scope.info[id]
    end
    -- A zone's artwork can include neighbouring zones. In-bounds projected
    -- coordinates are not evidence that those foreign sources belong here.
    -- Only genuine descendants are included when viewing a continent/world.
    local current,seen=source,{}
    local allowed=false
    for depth=1,24 do
        if not Number(current) or current<=0 or seen[current] then break end
        if current==map then allowed=true; break end
        seen[current]=true
        local info=Info(current)
        if not info then break end
        local parent=info.parentMapID
        if not Number(parent) then break end
        current=parent
    end
    if not allowed then
        -- Outdoor starter micro-maps may store their veins on the parent zone.
        -- Do not make this exception for dungeon/floor maps or sibling zones.
        local view,origin=Info(map),Info(source)
        local kinds=Enum and Enum.UIMapType
        if view and origin and kinds and Number(kinds.Micro) and Number(kinds.Zone)
            and Number(view.mapType) and view.mapType==kinds.Micro
            and Number(origin.mapType) and origin.mapType==kinds.Zone
            and Number(view.parentMapID) and view.parentMapID==source then allowed=true end
    end
    scope.allowed[source]=allowed
    return allowed
end
function P:Project(node,map)
    if not Valid(node) or not Number(map) then return end
    if node.map==map then return node.x,node.y end
    if not self:WorldSourceAllowed(node.map,map) then return end
    -- Native map rectangles also cover parent/world maps for which a single
    -- world-coordinate conversion is unavailable (for example split continents).
    local rect,minX,maxX,minY,maxY=Call(C_Map and C_Map.GetMapRectOnMap,node.map,map)
    if rect and Number(minX) and Number(maxX) and Number(minY) and Number(maxY) and maxX>minX and maxY>minY then
        local x,y=minX+node.x*(maxX-minX),minY+node.y*(maxY-minY)
        if Number(x) and Number(y) and x>=0 and x<=1 and y>=0 and y<=1 then return x,y end
    end
    if not CreateVector2D then return end
    local ok,worldMap,position=Call(C_Map and C_Map.GetWorldPosFromMapPos,node.map,CreateVector2D(node.x,node.y))
    if not ok or not Number(worldMap) or not Public(position) or not position then return end
    local got,uiMap,projected=Call(C_Map and C_Map.GetMapPosFromWorldPos,worldMap,position,map)
    local x,y
    if got then x,y=XY(projected) end
    if Public(uiMap) and uiMap==map and Number(x) and Number(y) and x>=0 and x<=1 and y>=0 and y<=1 then return x,y end
end
function P:ClearWorld()
    self.worldRevision=(self.worldRevision or 0)+1
    for index=1,self.worldCount do
        local point=self.worldPins[index]
        point.icon:Hide(); point.node=nil
    end
    self.worldRendering=false; self.worldCount=0; self.worldGrid={}
    self.worldResizeIndex,self.worldResizeAgain=nil,nil
    if self.worldLayer then self.worldLayer:SetScript("OnUpdate",nil) end
    if self.worldHover then
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self.worldHover) then GameTooltip:Hide() end
        self.worldHover.node=nil; self.worldHover:Hide()
    end
end
function P:WorldScale()
    local ok,scale=Call(WorldMapFrame and WorldMapFrame.GetCanvasScale,WorldMapFrame)
    return ok and Number(scale) and scale>0 and scale or 1
end
function P:ResizeWorldIcons()
    if not self.worldLayer or self.worldCount==0 then return end
    if self.worldResizeIndex then self.worldResizeAgain=true; return end
    self.worldResizeIndex=1
    self.worldLayer:SetScript("OnUpdate",function(layer)
        local first=self.worldResizeIndex
        if not first then layer:SetScript("OnUpdate",nil); return end
        local scale=self:WorldScale()
        local last=math.min(self.worldCount,first+BATCH-1)
        for index=first,last do self.worldPins[index].icon:SetSize(16/scale,16/scale) end
        self.worldResizeIndex=last+1
        if self.worldResizeIndex>self.worldCount then
            if self.worldResizeAgain then self.worldResizeAgain=nil; self.worldResizeIndex=1
            else self.worldResizeIndex=nil; layer:SetScript("OnUpdate",nil) end
        end
    end)
end
function P:WorldLayer(canvas)
    if not self.worldLayer then
        self.worldLayer=CreateFrame("Frame",nil,canvas)
        self.worldLayer:EnableMouse(false)
        self.worldHover=CreateFrame("Frame",nil,self.worldLayer)
        self.worldHover:EnableMouse(false); self.worldHover:SetSize(2,2)
    elseif self.worldLayer:GetParent()~=canvas then self.worldLayer:SetParent(canvas) end
    self.worldLayer:SetAllPoints(canvas); self.worldLayer:SetFrameLevel(canvas:GetFrameLevel()+8)
    return self.worldLayer
end
function P:FindWorldNode(x,y)
    if not Number(x) or not Number(y) or not self.worldWidth or not self.worldHeight then return end
    if x<0 or y<0 or x>self.worldWidth or y>self.worldHeight then return end
    local nx,ny=x/self.worldWidth,y/self.worldHeight
    local gx,gy=math.floor(nx*HIT_CELLS),math.floor(ny*HIT_CELLS)
    local radius=9/self:WorldScale()
    local rx,ry=math.ceil(radius/self.worldWidth*HIT_CELLS),math.ceil(radius/self.worldHeight*HIT_CELLS)
    local best,score
    for dx=-rx,rx do for dy=-ry,ry do
        local bucket=self.worldGrid and self.worldGrid[(gx+dx)..":"..(gy+dy)]
        for _,point in ipairs(bucket or {}) do
            local distance=(point.x-x)^2+(point.y-y)^2
            if distance<=radius^2 and (not score or distance<score) then best,score=point.node,distance end
        end
    end end
    return best
end
function P:WorldCursor()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    -- Our textures do not take focus. Native quest/vendor pins keep theirs.
    local focus=WorldMapFrame.IsCanvasMouseFocus or WorldMapFrame.IsCanvasMouseFocusOrPinFocus
    local focused,value=Call(focus,WorldMapFrame)
    if focused and (not Public(value) or value~=true) then return end
    if not focused then
        local surface=WorldMapFrame.ScrollContainer or WorldMapFrame
        local ok,over=Call(surface.IsMouseOver,surface)
        if not ok or not Public(over) or not over then return end
    end
    local ok,x,y=Call(WorldMapFrame.GetNormalizedCursorPosition,WorldMapFrame)
    if ok and Number(x) and Number(y) and self.worldWidth and self.worldHeight then return x*self.worldWidth,y*self.worldHeight end
    local got,cx,cy=Call(GetCursorPosition)
    local canvas=self.worldLayer and self.worldLayer:GetParent()
    if not got or not Number(cx) or not Number(cy) or not canvas then return end
    local scale,left,top=canvas:GetEffectiveScale(),canvas:GetLeft(),canvas:GetTop()
    if Number(scale) and scale>0 and Number(left) and Number(top) then return cx/scale-left,top-cy/scale end
end
function P:UpdateWorldHover()
    if not self.worldHover then return end
    local x,y=self:WorldCursor()
    local node=x and self:FindWorldNode(x,y)
    if node then
        self.worldHover:ClearAllPoints(); self.worldHover:SetPoint("CENTER",self.worldLayer,"TOPLEFT",x,-y)
        self.worldHover:Show()
        if not self.worldHover.node or self.worldHover.node.id~=node.id then
            self.worldHover.node=node; self:ShowTooltip(self.worldHover)
        end
    else
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self.worldHover) then GameTooltip:Hide() end
        self.worldHover.node=nil; self.worldHover:Hide()
    end
end
function P:WorldClick(button,x,y)
    if button~="LeftButton" or not M.db or M.db.pins==false then return false end
    for _,name in ipairs({"IsShiftKeyDown","IsControlKeyDown","IsAltKeyDown"}) do
        local ok,value=Call(rawget(_G,name))
        if ok and (not Public(value) or value==true) then return false end
    end
    if Number(x) and Number(y) and self.worldWidth and self.worldHeight then x,y=x*self.worldWidth,y*self.worldHeight
    else x,y=self:WorldCursor() end
    local node=x and self:FindWorldNode(x,y)
    if not node or not M.UI then return false end
    M.UI.selectedID,M.UI.selectedNode=node.id,node; M.UI:Show()
    return true
end
function P:RefreshWorld()
    self:ClearWorld()
    self.worldScope=nil
    if not M.db or M.db.pins==false or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local ok,canvas=Call(WorldMapFrame.GetCanvas,WorldMapFrame)
    local got,map=Call(WorldMapFrame.GetMapID,WorldMapFrame)
    if not ok or not canvas or not got or not Number(map) or not canvas.GetWidth then return end
    local width,height=canvas:GetWidth(),canvas:GetHeight()
    if not Number(width) or not Number(height) or width<=0 or height<=0 then return end
    local layer=self:WorldLayer(canvas)
    self.worldWidth,self.worldHeight=width,height
    local revision=self.worldRevision
    local cached=self.projected and self.projected.map==map and self.projected.version==self.dataVersion and self.projected.complete
    local projection=cached and self.projected or {map=map,version=self.dataVersion,points={}}
    self.projected=projection
    local index=1
    local entries=cached and projection.points or self.points
    self.worldRendering=true
    local function Paint()
        if self.worldRevision~=revision then return end
        if not WorldMapFrame:IsShown() or not M.db or M.db.pins==false then self:ClearWorld(); return end
        local scale=P:WorldScale()
        local last=math.min(#entries,index+BATCH-1)
        for at=index,last do
            local entry=entries[at]
            local node=entry.node
            local x,y
            if cached then x,y=entry.x,entry.y else x,y=P:Project(node,map) end
            if x and y then
                if not cached then projection.points[#projection.points+1]={node=node,x=x,y=y} end
                P.worldCount=P.worldCount+1
                local point=P.worldPins[P.worldCount]
                if not point then
                    point={icon=layer:CreateTexture(nil,"OVERLAY")}
                    point.icon:SetTexCoord(0.08,0.92,0.08,0.92)
                    P.worldPins[P.worldCount]=point
                end
                point.node,point.x,point.y=node,x*width,y*height
                point.icon:SetTexture(Icon(node)); point.icon:SetSize(16/scale,16/scale)
                point.icon:SetVertexColor(1,Observed(node) and 1 or 0.88,Observed(node) and 1 or 0.65,1)
                point.icon:ClearAllPoints(); point.icon:SetPoint("CENTER",layer,"TOPLEFT",point.x,-point.y); point.icon:Show()
                local key=math.floor(x*HIT_CELLS)..":"..math.floor(y*HIT_CELLS)
                P.worldGrid[key]=P.worldGrid[key] or {}; P.worldGrid[key][#P.worldGrid[key]+1]=point
            end
        end
        index=last+1
        if index<=#entries then
            if C_Timer and C_Timer.After then C_Timer.After(0,Paint) else Paint() end
        else
            projection.complete=true; P.worldRendering=false; P:UpdateWorldHover()
        end
    end
    Paint()
end
function P:NearbyPoints(instance,px,py,radius)
    local result={}
    local grid=self.spatial and self.spatial[instance]
    if not grid then return result end
    for x=math.floor((px-radius)/CELL),math.floor((px+radius)/CELL) do
        for y=math.floor((py-radius)/CELL),math.floor((py+radius)/CELL) do
            for _,point in ipairs(grid[x..":"..y] or {}) do result[#result+1]=point end
        end
    end
    return result
end
function P:ClearMini()
    if self.miniView or self.miniCount>0 then self:HidePins(self.miniPins) end
    self.miniView=nil
    self.miniCount=0
end
function P:RefreshMini(ifChanged)
    if not M.db or M.db.pins==false or not Minimap or not Minimap:IsVisible() then self:ClearMini(); return end
    local ok,radius=Call(C_Minimap and C_Minimap.GetViewRadius)
    local got,px,py,_,instance=Call(UnitPosition,"player")
    if not ok or not Number(radius) or radius<=0 or not got or not Number(px) or not Number(py) or not Number(instance) then self:ClearMini(); return end
    local width,height=Minimap:GetWidth(),Minimap:GetHeight()
    if not Number(width) or not Number(height) or width<=0 or height<=0 then self:ClearMini(); return end
    local rotating,rotation=Call(GetCVarBool,"rotateMinimap")
    local ignored,ignoreRotation=Call(C_Minimap and C_Minimap.IsRotateMinimapIgnored)
    local facing=0
    if rotating and Public(rotation) and rotation==true and not (ignored and Public(ignoreRotation) and ignoreRotation==true) then
        local read,value=Call(GetPlayerFacing)
        if read and Number(value) then facing=value end
    end
    local shapeOK,shape=Call(GetMinimapShape)
    local square=shapeOK and Public(shape) and shape=="SQUARE"
    local level=Minimap:GetFrameLevel()+6
    local view=self.miniView
    if ifChanged and view and view.version==self.dataVersion and view.map==Minimap and view.instance==instance
        and view.x==px and view.y==py and view.radius==radius and view.facing==facing
        and view.width==width and view.height==height and view.square==square and view.level==level then return end

    self.miniView=nil
    self.miniCount=0
    local visible={}
    local cos,sin=math.cos(facing),math.sin(facing)
    -- A rotated square's corners extend beyond the unrotated radius AABB.
    -- Query its circumscribed circle, then apply the exact visible bounds.
    local queryRadius=square and radius*math.sqrt(2) or radius
    for _,point in ipairs(self:NearbyPoints(instance,px,py,queryRadius)) do
        if point.instance==instance and Number(point.wx) and Number(point.wy) then
            local east,north=-(point.wy-py)/radius,(point.wx-px)/radius
            local x,y=east*cos+north*sin,-east*sin+north*cos
            local distance=x*x+y*y
            if (square and math.abs(x)<=1 and math.abs(y)<=1) or (not square and distance<=1) then
                visible[#visible+1]={point=point,x=x,y=y,distance=distance}
            end
        end
    end
    table.sort(visible,function(a,b) return a.distance<b.distance end)
    local limit=#visible
    local desired,existing,used={},{},{}
    for index=1,limit do desired[visible[index].point.node.id]=true end
    for _,pin in ipairs(self.miniPins) do if pin.node then existing[pin.node.id]=pin end end
    for index=1,limit do
        local value=visible[index]
        local pin=existing[value.point.node.id]
        if not pin then
            -- Do not borrow a frame reserved for another still-visible node.
            -- Stable node/frame identity keeps a hovered tooltip readable.
            for _,candidate in ipairs(self.miniPins) do
                if not used[candidate] and (not candidate.node or not desired[candidate.node.id]) then pin=candidate; break end
            end
            pin=pin or self:GetPin(#self.miniPins+1,true,Minimap)
        end
        local previous=pin.node
        local node=value.point.node
        local changed=not previous or previous.id~=node.id or previous.lastSeen~=node.lastSeen or previous.count~=node.count
            or previous.requiredSkill~=node.requiredSkill or previous.requirementSource~=node.requirementSource
        if pin:GetParent()~=Minimap then pin:SetParent(Minimap) end
        pin.node=node; pin.icon:SetTexture(Icon(pin.node)); pin:ClearAllPoints()
        pin:SetPoint("CENTER",Minimap,"CENTER",value.x*width/2,value.y*height/2)
        pin:SetFrameLevel(level)
        if not pin:IsShown() then pin:Show() end
        if changed and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(pin) then self:ShowTooltip(pin) end
        used[pin]=true; self.miniCount=index
    end
    for _,pin in ipairs(self.miniPins) do
        if not used[pin] then
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
            if pin:IsShown() then pin:Hide() end
            pin.node=nil
        end
    end
    self.miniView={version=self.dataVersion,map=Minimap,instance=instance,x=px,y=py,radius=radius,facing=facing,
        width=width,height=height,square=square,level=level}
end
function P:HookWorldMap()
    if self.mapHooked or not WorldMapFrame then return end
    self.mapHooked=true
    WorldMapFrame:HookScript("OnShow",function() P:RefreshWorld() end)
    WorldMapFrame:HookScript("OnHide",function() P:ClearWorld() end)
    if hooksecurefunc and type(WorldMapFrame.SetMapID)=="function" then hooksecurefunc(WorldMapFrame,"SetMapID",function() P:RefreshWorld() end) end
    if hooksecurefunc and type(WorldMapFrame.OnCanvasScaleChanged)=="function" then
        hooksecurefunc(WorldMapFrame,"OnCanvasScaleChanged",function() P:ResizeWorldIcons() end)
    end
    if type(WorldMapFrame.AddCanvasClickHandler)=="function" then
        WorldMapFrame:AddCanvasClickHandler(function(_,button,x,y) return P:WorldClick(button,x,y) end)
    end
    local ok,canvas=Call(WorldMapFrame.GetCanvas,WorldMapFrame)
    if ok and canvas and canvas.HookScript then canvas:HookScript("OnSizeChanged",function() P:RefreshWorld() end) end
end
local function WorldPosition(map,x,y)
    if not CreateVector2D then return end
    local ok,instance,position=Call(C_Map and C_Map.GetWorldPosFromMapPos,map,CreateVector2D(x,y))
    local wx,wy=XY(position)
    if ok and Number(instance) and Number(wx) and Number(wy) then return instance,wx,wy end
end
local function Projection(map)
    -- UI-map coordinates are affine rectangles. Sample the client's own axes;
    -- a map that cannot supply all three falls back to per-point conversion.
    local a,ax,ay=WorldPosition(map,0,0)
    local b,bx,by=WorldPosition(map,1,0)
    local c,cx,cy=WorldPosition(map,0,1)
    if a and a==b and a==c then
        return {instance=a,x=ax,y=ay,xx=bx-ax,xy=by-ay,yx=cx-ax,yy=cy-ay}
    end
end
function P:RebuildCatalog()
    local points,spatial,matrices={},{},{}
    local nodes=M:GetNodes()
    for _,node in ipairs(nodes) do
        if Valid(node) then
            local point={node=node}
            if matrices[node.map]==nil then matrices[node.map]=Projection(node.map) or false end
            local matrix=matrices[node.map]
            if matrix then
                point.instance=matrix.instance
                point.wx=matrix.x+node.x*matrix.xx+node.y*matrix.yx
                point.wy=matrix.y+node.x*matrix.xy+node.y*matrix.yy
            else point.instance,point.wx,point.wy=WorldPosition(node.map,node.x,node.y) end
            if Number(point.instance) and Number(point.wx) and Number(point.wy) then
                local grid=spatial[point.instance]
                if not grid then grid={}; spatial[point.instance]=grid end
                local key=math.floor(point.wx/CELL)..":"..math.floor(point.wy/CELL)
                grid[key]=grid[key] or {}; grid[key][#grid[key]+1]=point
            end
            points[#points+1]=point
        end
    end
    self.points,self.spatial=points,spatial
    self.dataVersion=self.dataVersion+1
    self.catalogDirty=false
    self.projected=nil
end
function P:Refresh(viewOnly)
    self:HookWorldMap()
    if viewOnly~=true then self.catalogDirty=true end
    if not M.db or M.db.pins==false then
        if self.markersEnabled then
            self:ClearWorld(); self:ClearMini()
            if self.worker then self.worker:SetScript("OnUpdate",nil) end
        end
        self.markersEnabled=false
        return
    end
    local rebuild=self.catalogDirty
    if rebuild then self:RebuildCatalog() end
    if rebuild or not self.markersEnabled then self:RefreshWorld() end
    self.markersEnabled=true
    self:RefreshMini(true)
    if self.worker then
        if #self.points==0 then self.worker:SetScript("OnUpdate",nil)
        elseif not self.worker:GetScript("OnUpdate") then
            self.elapsed=0
            self.worker:SetScript("OnUpdate",function(_,elapsed)
                P.elapsed=P.elapsed+elapsed
                if P.elapsed>=0.15 then P.elapsed=0; P:RefreshMini(true); P:UpdateWorldHover() end
            end)
        end
    end
end
function P:OpenNode(node)
    if not Valid(node) then return false,"Select a saved mining site first." end
    if not WorldMapFrame then return false,"The world map is unavailable." end
    local ok=Call(WorldMapFrame.SetMapID,WorldMapFrame,node.map)
    if not ok then return false,"This map could not be opened." end
    if ShowUIPanel then Call(ShowUIPanel,WorldMapFrame) else WorldMapFrame:Show() end
    self:RefreshWorld()
    return true
end
function P:GetStatus()
    if not M.db or M.db.pins==false then return "Mining map markers are off." end
    return string.format("All known sites: %d world-map markers, %d within minimap range.%s",self.worldCount,self.miniCount,
        self.worldRendering and " Drawing map markers…" or " No active route required.")
end
function P:Initialize()
    if self.initialized then return end
    self.initialized=true
    self.worker=CreateFrame("Frame",nil,Minimap or UIParent)
    self.events=CreateFrame("Frame")
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA","ZONE_CHANGED","MINIMAP_UPDATE_ZOOM","ADDON_LOADED"}) do self.events:RegisterEvent(event) end
    self.events:SetScript("OnEvent",function(_,event)
        if event=="ADDON_LOADED" then P:HookWorldMap()
        elseif event=="MINIMAP_UPDATE_ZOOM" then P:RefreshMini()
        elseif event=="PLAYER_ENTERING_WORLD" and #P.points>0 and not next(P.spatial) then
            -- Conversion may have been unavailable while the client was loading.
            P:Refresh()
        else P:Refresh(true) end
    end)
    self:Refresh()
end
