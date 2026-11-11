-- Rico Mining shares the suite's live liquid header, typography and controls.
local _, RP = ...
local M = RP.Mining or _G.RicoMining
local T = RP.Theme
local U = {rows={},page=1,query="",currentZone=true,sourceFilter="all",fonts=setmetatable({},{__mode="k"})}
M.UI=U
local unpack=unpack or table.unpack
local function Public(v) return not (issecretvalue and issecretvalue(v)) end
local function Number(v) return Public(v) and type(v)=="number" and v==v and v>-math.huge and v<math.huge end
local function Call(fn,...) if type(fn)~="function" then return false end; return pcall(fn,...) end
local function Text(parent,value,size,color)
    local fs=(parent.ricoForeground or parent):CreateFontString(nil,"OVERLAY")
    size=size or 11; fs:SetFont(T.font,size,""); fs:SetTextColor(unpack(color or T.colors.text)); fs:SetJustifyH("LEFT")
    fs:SetText(value or ""); U.fonts[fs]=size
    return fs
end
local function Button(parent,label,width,callback)
    local button=CreateFrame("Button",nil,parent)
    button:SetSize(width,28); button.background=T:Panel(button)
    button.label=Text(button,label); button.label:SetPoint("CENTER")
    button:SetScript("OnClick",callback); T:Button(button,button.background)
    return button
end
local function Check(parent,label,x,y,click)
    local check=CreateFrame("CheckButton",nil,parent)
    check:SetSize(23,23); check:SetPoint("TOPLEFT",x,y); T:Check(check)
    check.label=Text(check,label,11); check.label:SetPoint("LEFT",check,"RIGHT",5,0)
    check:SetScript("OnClick",function(self) click(self:GetChecked()==true) end)
    return check
end
local function Icon(oreID)
    local ok,icon=Call(C_Item and C_Item.GetItemIconByID or GetItemIcon,oreID)
    return ok and Public(icon) and icon or "Interface\\Icons\\Trade_Mining"
end
local function Observed(node) return node.observed~=false and node.reference~=true end
local function CurrentMap()
    local ok,map=Call(C_Map and C_Map.GetBestMapForUnit,"player")
    return ok and Number(map) and map>0 and map or nil
end
local function MapName(map)
    local ok,info=Call(C_Map and C_Map.GetMapInfo,map)
    if ok and Public(info) and type(info)=="table" and Public(info.name) and type(info.name)=="string" then return info.name end
    return Number(map) and ("Map "..map) or "Current zone"
end
local function Clean(text)
    if not Public(text) or type(text)~="string" then return "" end
    return text:lower()
end
function U:GetFilteredNodes()
    local map=self.currentZone and CurrentMap() or nil
    local nodes=M:GetNodes(map,self.oreID)
    -- Starter micro-zones can report their own map while observations use the parent.
    if self.currentZone and map then
        local ok,info=Call(C_Map and C_Map.GetMapInfo,map)
        if ok and Public(info) and type(info)=="table" and Number(info.parentMapID) and info.parentMapID>0 then
            local micro=Enum and Enum.UIMapType and Enum.UIMapType.Micro
            if #nodes==0 or (Public(info.mapType) and info.mapType==micro and micro~=nil) then
                local included={}
                for _,node in ipairs(nodes) do included[node.id]=true end
                for _,node in ipairs(M:GetNodes(info.parentMapID,self.oreID)) do
                    if not included[node.id] then nodes[#nodes+1]=node; included[node.id]=true end
                end
            end
        end
    end
    local filtered={}
    local query=Clean(self.query)
    local skill=M:GetSkill()
    local effective=skill and (skill.effective or skill.current)
    for _,node in ipairs(nodes) do
        local observed=Observed(node)
        local matchesSource=self.sourceFilter=="all" or (self.sourceFilter=="observed" and observed) or (self.sourceFilter=="reference" and not observed)
        local matchesSkill=not (M.db and M.db.skillFilter) or (Number(effective) and Number(node.requiredSkill) and node.requiredSkill<=effective)
        if matchesSource and matchesSkill and (query=="" or Clean((node.name or "").." "..(node.nodeName or "").." "..(node.zone or "")):find(query,1,true)) then
            filtered[#filtered+1]=node
        end
    end
    return filtered
end
function U:GetSelected()
    if not self.selectedID then return end
    if self.selectedNode and self.selectedNode.id==self.selectedID then return self.selectedNode end
    for _,node in ipairs(M:GetNodes()) do if node.id==self.selectedID then self.selectedNode=node; return node end end
    self.selectedID,self.selectedNode=nil,nil
end
function U:Act(method,...)
    if not M.Routes or type(M.Routes[method])~="function" then self.notice="Mining navigation is unavailable. Use /reload to load the update."
    else
        local ok,success,message=pcall(M.Routes[method],M.Routes,...)
        self.notice=ok and (message or (success and "Navigation started." or "No route was started.")) or "The navigator reported an error. Open Quest routes > Details for its status."
    end
    self:RefreshStatus()
end
function U:Build()
    if self.frame then return end
    self.building=true
    local frame=CreateFrame("Frame","RicoMiningWindow",UIParent)
    self.frame=frame
    frame:SetSize(1000,710); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    T:Window(frame)
    self.title=Text(frame,"",24,T.colors.mint); self.title:SetPoint("TOPLEFT",24,-22); T:Title(self.title,"MINING")
    self.subtitle=Text(frame,"Mining sites · farming routes · skill guide",11,T.colors.muted); self.subtitle:SetPoint("TOPLEFT",24,-57)
    self.closeButton=Button(frame,"Close",74,function() frame:Hide() end); self.closeButton:SetPoint("TOPRIGHT",-22,-29)

    local ribbon=CreateFrame("Frame",nil,frame); ribbon:SetPoint("TOPLEFT",18,-88); ribbon:SetSize(964,59); T:Panel(ribbon)
    self.skillText=Text(ribbon,"Mining",17,T.colors.mint); self.skillText:SetPoint("TOPLEFT",13,-9)
    self.skillNote=Text(ribbon,"",10,T.colors.muted); self.skillNote:SetPoint("BOTTOMLEFT",13,10)
    self.statsText=Text(ribbon,"",11); self.statsText:SetPoint("TOPLEFT",315,-12); self.statsText:SetWidth(405)
    self.sessionText=Text(ribbon,"",10,T.colors.muted); self.sessionText:SetPoint("BOTTOMLEFT",315,11); self.sessionText:SetWidth(405)
    self.pinCheck=Check(ribbon,"Show all map sites",789,-18,function(value) M:SetOption("pins",value); U:Refresh() end)

    self.zoneButton=Button(frame,"Current zone",156,function() U.currentZone=not U.currentZone; U.page=1; U:Refresh() end)
    self.zoneButton:SetPoint("TOPLEFT",18,-160)
    self.oreButton=Button(frame,"All ores",155,function()
        local ores=M.Data and M.Data.ores or {}
        local nextIndex=1
        for index,ore in ipairs(ores) do if ore.id==U.oreID then nextIndex=index+1 end end
        U.oreID=ores[nextIndex] and ores[nextIndex].id or nil; U.page=1; U:Refresh()
    end)
    self.oreButton:SetPoint("LEFT",self.zoneButton,"RIGHT",10,0)
    self.sourceButton=Button(frame,"All sources",137,function()
        U.sourceFilter=U.sourceFilter=="all" and "observed" or U.sourceFilter=="observed" and "reference" or "all"
        U.page=1; U:Refresh()
    end)
    self.sourceButton:SetPoint("LEFT",self.oreButton,"RIGHT",10,0)
    self.skillCheck=Check(frame,"Within my skill",503,-163,function(value) M:SetOption("skillFilter",value); U.page=1; U:Refresh() end)
    self.search=CreateFrame("EditBox",nil,frame,"InputBoxTemplate")
    self.search:SetSize(292,27); self.search:SetPoint("TOPRIGHT",-22,-160); self.search:SetAutoFocus(false)
    self.search:SetFont(T.font,12,""); self.fonts[self.search]=12; self.search:SetMaxLetters(80); T:Input(self.search)
    self.search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    self.search:SetScript("OnTextChanged",function(self) if not U.building then U.query=self:GetText(); U.page=1; U:Refresh() end end)
    self.searchHint=Text(frame,"Search ore, node or zone",9,T.colors.muted); self.searchHint:SetPoint("TOPLEFT",self.search,"BOTTOMLEFT",0,-4)

    self.listPanel=CreateFrame("Frame",nil,frame); self.listPanel:SetPoint("TOPLEFT",18,-207); self.listPanel:SetSize(606,352); T:Panel(self.listPanel)
    self.listHeading=Text(self.listPanel,"Known mining sites",12,T.colors.mint); self.listHeading:SetPoint("TOPLEFT",11,-10)
    for index=1,8 do
        local row=CreateFrame("Button",nil,frame); row:SetSize(582,36); row:SetPoint("TOPLEFT",30,-242-(index-1)*38)
        row.background=T:Panel(row); T:Row(row,false,false)
        row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetSize(27,27); row.icon:SetPoint("LEFT",5,0); row.icon:SetTexCoord(0.08,0.92,0.08,0.92)
        row.name=Text(row,"",12); row.name:SetPoint("TOPLEFT",41,-4); row.name:SetWidth(360); row.name:SetWordWrap(false)
        row.note=Text(row,"",9,T.colors.muted); row.note:SetPoint("BOTTOMLEFT",41,4); row.note:SetWidth(450); row.note:SetWordWrap(false)
        row.skill=Text(row,"",11); row.skill:SetPoint("RIGHT",-10,0)
        row:SetScript("OnClick",function(self) if self.node then U.selectedID,U.selectedNode=self.node.id,self.node; U.notice=nil; U:Refresh() end end)
        row:SetScript("OnEnter",function(self) T:Row(self,self.node and self.node.id==U.selectedID,true) end)
        row:SetScript("OnLeave",function(self) T:Row(self,self.node and self.node.id==U.selectedID,false) end)
        self.rows[index]=row
    end
    self.empty=Text(frame,"",12,T.colors.muted); self.empty:SetPoint("TOPLEFT",35,-265); self.empty:SetWidth(570); self.empty:SetHeight(100); self.empty:SetJustifyV("TOP")
    self.previous=Button(frame,"Previous",83,function() U.page=math.max(1,U.page-1); U:Refresh() end); self.previous:SetPoint("TOPLEFT",18,-569)
    self.nextButton=Button(frame,"Next",83,function() U.page=U.page+1; U:Refresh() end); self.nextButton:SetPoint("TOPLEFT",541,-569)
    self.pageText=Text(frame,"",10,T.colors.muted); self.pageText:SetPoint("TOP",frame,"TOPLEFT",320,-579)

    self.detailPanel=CreateFrame("Frame",nil,frame); self.detailPanel:SetPoint("TOPLEFT",638,-207); self.detailPanel:SetSize(344,390); T:Panel(self.detailPanel)
    self.detailIcon=self.detailPanel:CreateTexture(nil,"ARTWORK"); self.detailIcon:SetSize(40,40); self.detailIcon:SetPoint("TOPLEFT",13,-13); self.detailIcon:SetTexCoord(0.08,0.92,0.08,0.92)
    self.detailTitle=Text(self.detailPanel,"Choose a mining site",16,T.colors.mint); self.detailTitle:SetPoint("TOPLEFT",64,-13); self.detailTitle:SetWidth(266); self.detailTitle:SetWordWrap(false)
    self.detailZone=Text(self.detailPanel,"",10,T.colors.muted); self.detailZone:SetPoint("TOPLEFT",64,-38); self.detailZone:SetWidth(266)
    self.detailText=Text(self.detailPanel,"",11); self.detailText:SetPoint("TOPLEFT",13,-69); self.detailText:SetWidth(318); self.detailText:SetHeight(114); self.detailText:SetJustifyV("TOP")
    self.helpTitle=Text(self.detailPanel,"Skill help",13,T.colors.mint); self.helpTitle:SetPoint("TOPLEFT",13,-193)
    self.helpText=Text(self.detailPanel,"",11); self.helpText:SetPoint("TOPLEFT",13,-217); self.helpText:SetWidth(318); self.helpText:SetHeight(156); self.helpText:SetJustifyV("TOP")

    self.navigateButton=Button(frame,"Navigate selected",163,function() U:Act("NavigateNode",U:GetSelected()) end)
    self.navigateButton:SetPoint("BOTTOMLEFT",18,70)
    self.farmButton=Button(frame,"Start farm route",170,function() U:Act("Start",U.filtered or {},{maxStops=24}) end)
    self.farmButton:SetPoint("LEFT",self.navigateButton,"RIGHT",10,0)
    self.stopButton=Button(frame,"Stop mining route",163,function() U:Act("Stop") end)
    self.stopButton:SetPoint("LEFT",self.farmButton,"RIGHT",10,0)
    self.nextSiteButton=Button(frame,"Next location",129,function() U:Act("Next") end)
    self.nextSiteButton:SetPoint("LEFT",self.stopButton,"RIGHT",10,0)
    self.mapButton=Button(frame,"View on map",135,function()
        if M.Map then local ok,message=M.Map:OpenNode(U:GetSelected()); U.notice=message; U:RefreshStatus() end
    end)
    self.mapButton:SetPoint("LEFT",self.nextSiteButton,"RIGHT",10,0)
    self.routeStatus=Text(frame,"",11,T.colors.mint); self.routeStatus:SetPoint("BOTTOMLEFT",20,28); self.routeStatus:SetWidth(960); self.routeStatus:SetHeight(34); self.routeStatus:SetJustifyV("TOP")
    self.footer=Text(frame,"All known sites on the world map; nearby sites on the minimap. No active route needed. Ore may be absent.",9,T.colors.muted)
    self.footer:SetPoint("BOTTOMLEFT",20,11)
    frame:SetScript("OnShow",function(self)
        U.elapsed=0; U:Refresh()
        self:SetScript("OnUpdate",function(_,elapsed) U.elapsed=U.elapsed+elapsed; if U.elapsed>=0.5 then U.elapsed=0; U:RefreshStatus() end end)
    end)
    frame:SetScript("OnHide",function(self) self:SetScript("OnUpdate",nil) end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="RicoMiningWindow" end
    frame:Hide(); self.building=false
end
function U:RefreshDetails()
    local node=self:GetSelected()
    self.detailIcon:SetTexture(Icon(node and node.oreID))
    self.detailTitle:SetText(node and (node.nodeName or node.name or "Mining site") or "Choose a mining site")
    self.detailZone:SetText(node and (node.zone or MapName(node.map)) or "Select a location in the list")
    if node then
        local observed=Observed(node)
        local lines={string.format("Coordinates: %.1f, %.1f",node.x*100,node.y*100)}
        lines[#lines+1]=Number(node.requiredSkill) and ("Required Mining: "..node.requiredSkill.." ("..(node.requirementSource or "Reference")..")") or "Required Mining: unknown"
        lines[#lines+1]=observed and ("Mined here "..(node.count or 1).." time(s). Gathering position is approximate.") or ("Reference location · "..(node.source or "Imported database"))
        lines[#lines+1]="Ore is not guaranteed to be present now."
        self.detailText:SetText(table.concat(lines,"\n"))
    else self.detailText:SetText("Mine an ore vein to remember its gathering position. Imported locations are shown separately as references.\n\nSelect a site to view its skill requirement and start navigation.") end
    local help=M.GetSkillHelp and M:GetSkillHelp() or {}
    local lines={help.message or "Mining skill information is unavailable."}
    local skill=M:GetSkill() or {}
    local current=skill.effective or skill.current
    local first=1
    for index,entry in ipairs(help.entries or {}) do
        if Number(current) and Number(entry.requiredSkill) and entry.requiredSkill<=current then first=math.max(1,index-2) end
    end
    for index=first,math.min(#(help.entries or {}),first+4) do
        local entry=help.entries[index]
        lines[#lines+1]=(entry.name or "Ore")..": Mining "..(entry.requiredSkill or "?")..(entry.quest and " · quest ore" or entry.canMine==true and " · available" or entry.canMine==false and " · too high" or "")
    end
    lines[#lines+1]="Reference skill values may differ in Forever."
    self.helpText:SetText(table.concat(lines,"\n"))
    self.navigateButton:SetEnabled(node~=nil); self.mapButton:SetEnabled(node~=nil)
end
function U:RefreshStatus()
    if not self.frame or not self.frame:IsShown() then return end
    local status=M.Routes and M.Routes:GetStatus() or {ready=false,message="Mining navigation is unavailable."}
    self.routeStatus:SetText(self.notice or status.message or "Choose a site or start a farm route.")
    self.farmButton:SetEnabled(status.ready==true and #(self.filtered or {})>0)
    self.stopButton:SetEnabled(status.active==true)
    self.nextSiteButton:SetEnabled(status.canNext==true)
    self.navigateButton:SetEnabled(self:GetSelected()~=nil and status.ready==true)
end
function U:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self.filtered=self:GetFilteredNodes()
    if self.selectedID then
        self.selectedNode=nil
        for _,node in ipairs(self.filtered) do if node.id==self.selectedID then self.selectedNode=node; break end end
    end
    local pages=math.max(1,math.ceil(#self.filtered/8)); self.page=math.max(1,math.min(self.page,pages))
    local skill=M:GetSkill() or {}
    local effective=skill.effective or skill.current
    self.skillText:SetText(skill.known and ("Mining "..(skill.current or "?").." / "..(skill.max or "?")) or "Mining not learned")
    self.skillNote:SetText(skill.known and ("Effective skill: "..(effective or "?").." · select a site for its requirement") or "Learn Mining from a profession trainer to gather ore.")
    local stats=M:GetStats() or {}
    self.statsText:SetText((stats.observedNodes or stats.nodes or 0).." personally mined · "..(stats.referenceNodes or 0).." reference sites")
    self.sessionText:SetText("This session: "..(stats.sessionNodes or 0).." veins · "..(stats.sessionQuantity or 0).." gathered items")
    self.pinCheck:SetChecked(M.db and M.db.pins~=false); self.skillCheck:SetChecked(M.db and M.db.skillFilter==true)
    self.zoneButton.label:SetText(self.currentZone and "Current zone" or "All zones")
    local oreName="All ores"
    for _,ore in ipairs(M.Data and M.Data.ores or {}) do if ore.id==self.oreID then oreName=ore.name end end
    self.oreButton.label:SetText(oreName)
    self.sourceButton.label:SetText(self.sourceFilter=="observed" and "Personally mined" or self.sourceFilter=="reference" and "Reference sites" or "All sources")
    local referenceCount,observedCount=0,0
    for _,node in ipairs(self.filtered) do if Observed(node) then observedCount=observedCount+1 else referenceCount=referenceCount+1 end end
    self.listHeading:SetText("Mining sites · "..observedCount.." observed / "..referenceCount.." reference")
    for index,row in ipairs(self.rows) do
        local node=self.filtered[(self.page-1)*8+index]; row.node=node; row:SetShown(node~=nil)
        if node then
            row.name:SetText(node.nodeName or node.name or "Mining site"); row.icon:SetTexture(Icon(node.oreID))
            row.note:SetText(string.format("%s · %.1f, %.1f · %s",node.zone or MapName(node.map),node.x*100,node.y*100,Observed(node) and "Personally mined" or "Reference"))
            row.skill:SetText(Number(node.requiredSkill) and ("Skill "..node.requiredSkill) or "Skill ?")
            local canMine=Number(effective) and Number(node.requiredSkill) and effective>=node.requiredSkill
            row.skill:SetTextColor(unpack(canMine and T.colors.mint or T.colors.amber))
        end
        T:Row(row,node and node.id==self.selectedID,false)
    end
    self.empty:SetShown(#self.filtered==0)
    self.empty:SetText(self.currentZone and "No matching mining sites in this zone. Try All zones, change the filters, or mine a vein to save a personal location.\n\nSaved and reference locations are historical; they do not show live ore spawns." or "No matching mining sites. Change the filters, or mine a vein to save a personal location.")
    self.previous:SetEnabled(self.page>1); self.nextButton:SetEnabled(self.page<pages)
    self.pageText:SetText(self.page.." / "..pages.." · "..#self.filtered.." sites")
    self:RefreshDetails(); self:RefreshStatus()
end
function U:RefreshFonts()
    for font,size in pairs(self.fonts) do font:SetFont(T.font,size,"") end
    if self.title then T:Title(self.title,"MINING") end
    if self.frame and self.frame:IsShown() then self:Refresh() end
end
function U:Show() self:Build(); self.frame:Show(); self:Refresh() end
function U:Toggle(force) self:Build(); self.frame:SetShown(force==nil and not self.frame:IsShown() or force==true); self:Refresh() end
function U:Initialize()
    if self.initialized then return end
    self.initialized=true
    SLASH_RICOMINING1,SLASH_RICOMINING2="/rm","/rmining"
    SlashCmdList.RICOMINING=function() U:Toggle() end
end
