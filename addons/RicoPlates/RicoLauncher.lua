-- One launcher shared by every independently loadable Rico addon.
local addonName, Addon = ...
local L = _G.RicoLauncher
if not L then
    L = { registrations = {}, rows = {} }
    _G.RicoLauncher = L
    local unpack = unpack or table.unpack
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local actions = {
        {name="Rico Loot", hint="Creature loot, database and wishlist", addon="RicoLoot", module="UI", method="Toggle"},
        {name="Rico Fishing", hint="Fishing guide and catch tracker", addon="RicoFishing", module="UI", method="Toggle"},
        {name="Rico Plates", hint="Nameplates, unitframes and party", addon="RicoPlates", module="Options", method="Toggle"},
        {name="Quest routes", hint="Walking routes to quests or map pins", addon="RicoPlates", module="QuestRouteUI", method="Show"},
        {name="Rico Mining", hint="Mining sites, farm routes and skill help", addon="RicoMining", module="UI", method="Show"},
        {name="Inventory", hint="All carried bags together", addon="RicoPlates", module="Inventory", method="Toggle"},
    }
    local function Public(value) return not (issecretvalue and issecretvalue(value)) end
    local function Number(value)
        return Public(value) and type(value)=="number" and value==value and value>-math.huge and value<math.huge
    end
    local function Table(value)
        return Public(value) and type(value)=="table" and (not canaccesstable or canaccesstable(value))
    end
    local function Call(fn,...)
        if type(fn)~="function" then return false end
        return pcall(fn,...)
    end
    local function Now()
        local ok,value=Call(GetTime)
        return ok and Number(value) and value or nil
    end
    local function Text(parent,value,size,color)
        local T=L.theme
        local fs=(parent.ricoForeground or parent):CreateFontString(nil,"OVERLAY")
        fs:SetFont(T.font,size or 11,""); fs:SetTextColor(unpack(color or T.colors.text))
        fs:SetJustifyH("LEFT"); fs:SetText(value or "")
        return fs
    end
    function L:GetSuite()
        local suite=rawget(_G,"RicoSuite")
        if Table(suite) and type(suite.Initialize)=="function" then suite:Initialize(); return suite end
    end
    function L:GetAngle()
        local suite=self:GetSuite()
        local settings=suite and suite.db and suite.db.launcher
        return Table(settings) and Number(settings.angle) and settings.angle%360 or 220
    end
    function L:SaveAngle(angle)
        if not Number(angle) then return false end
        local suite=self:GetSuite()
        if not suite or not Table(suite.db) then return false end
        if not Table(suite.db.launcher) then suite.db.launcher={} end
        suite.db.launcher.angle=angle%360
        if type(suite.Touch)=="function" then suite:Touch() end
        return true
    end
    function L:PlaceButton(angle)
        if not self.button or not Minimap then return false end
        angle=Number(angle) and angle or self:GetAngle()
        local width,height=Minimap:GetWidth(),Minimap:GetHeight()
        if not Number(width) or not Number(height) or width<=0 or height<=0 then return false end
        local c,s=math.cos(math.rad(angle)),math.sin(math.rad(angle))
        local ok,shape=Call(GetMinimapShape)
        if ok and Public(shape) and shape=="SQUARE" then
            local stretch=1/math.max(math.abs(c),math.abs(s)); c,s=c*stretch,s*stretch
        end
        self.angle=angle%360
        self.button:ClearAllPoints()
        self.button:SetPoint("CENTER",Minimap,"CENTER",c*(width/2+7),s*(height/2+7))
        return true
    end
    function L:DragUpdate()
        if not Minimap then return end
        local ok,x,y=Call(GetCursorPosition)
        local scale=Minimap and Minimap:GetEffectiveScale()
        local cx,cy=Minimap:GetCenter()
        if not ok or not Number(x) or not Number(y) or not Number(scale) or scale<=0 or not Number(cx) or not Number(cy) then return end
        local dx,dy=x/scale-cx,y/scale-cy
        if dx==0 and dy==0 then return end
        local radians
        if math.atan2 then radians=math.atan2(dy,dx)
        elseif dx==0 then radians=dy>0 and math.pi/2 or -math.pi/2
        else radians=math.atan(dy/dx)+(dx<0 and math.pi or 0) end
        self:PlaceButton(math.deg(radians)%360)
    end
    function L:StartDrag()
        local ok,shift=Call(IsShiftKeyDown)
        if not self.button or not ok or not Public(shift) or shift~=true then return false end
        self.dragging=true
        self.button:SetScript("OnUpdate",function() L:DragUpdate() end)
        if GameTooltip then GameTooltip:Hide() end
        return true
    end
    function L:StopDrag()
        if not self.button or not self.dragging then return end
        self:DragUpdate(); self.dragging=false
        self.button:SetScript("OnUpdate",nil)
        self.lastDragStop=Now()
        self:SaveAngle(self.angle)
    end
    function L:RefreshAppearance()
        local T=self.theme
        if not T then return end
        if self.letter then self.letter:SetFont(T.font,17,"OUTLINE"); self.letter:SetTextColor(unpack(T.colors.text)) end
        if self.gem then self.gem:SetVertexColor(unpack(T.colors.mint)) end
        if self.title then T:Title(self.title,"MENU") end
        for _,row in ipairs(self.rows) do row.title:SetTextColor(unpack(T.colors.mint)) end
        if self.frame and self.frame:IsShown() then self:Refresh() end
    end
    function L:EnsureButton()
        if not self.theme or not Minimap or (Minimap.IsForbidden and Minimap:IsForbidden()) then return false end
        if self.button then if not self.dragging then self:PlaceButton() end; return true end
        local button=CreateFrame("Button","RicoSuiteMinimapButton",Minimap)
        self.button=button
        button:SetSize(32,32); button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(Minimap:GetFrameLevel()+15)
        button:RegisterForClicks("LeftButtonUp","RightButtonUp"); button:RegisterForDrag("LeftButton")
        local function Diamond(size,color,layer)
            local t=button:CreateTexture(nil,layer or "ARTWORK")
            t:SetTexture(WHITE); t:SetSize(size,size); t:SetPoint("CENTER"); t:SetRotation(math.pi/4)
            t:SetVertexColor(unpack(color)); return t
        end
        Diamond(22,{0.01,0.02,0.02,1},"BACKGROUND")
        Diamond(20,{0.42,0.34,0.16,1})
        Diamond(18,{0.015,0.05,0.035,1})
        self.gem=Diamond(14,self.theme.colors.mint)
        Diamond(11,{0.025,0.11,0.075,0.78})
        self.letter=Text(button,"R",17); self.letter:SetFont(self.theme.font,17,"OUTLINE"); self.letter:SetPoint("CENTER",0,0)
        button:SetScript("OnClick",function()
            local now=Now()
            if L.dragging or (now and L.lastDragStop and now-L.lastDragStop<0.15) then return end
            L:Toggle()
        end)
        button:SetScript("OnDragStart",function() L:StartDrag() end)
        button:SetScript("OnDragStop",function() L:StopDrag() end)
        button:SetScript("OnHide",function() L:StopDrag(); if L.frame then L.frame:Hide() end end)
        button:SetScript("OnEnter",function(self)
            if GameTooltip and not L.dragging then
                GameTooltip:SetOwner(self,"ANCHOR_LEFT")
                GameTooltip:SetText("Rico",0.4,0.95,0.7)
                GameTooltip:AddLine("Click to open the Rico menu.",1,1,1,true)
                GameTooltip:AddLine("Shift-drag to move this button.",0.65,0.75,0.7,true)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        if Minimap.HookScript then Minimap:HookScript("OnSizeChanged",function() if not L.dragging then L:PlaceButton() end end) end
        self:PlaceButton(); self:RefreshAppearance()
        return true
    end
    function L:Handler(index)
        local action=actions[index]
        if not action then return nil end
        local addon=rawget(_G,action.addon) or self.registrations[action.addon]
        local owner=Table(addon) and addon[action.module]
        local fn=Table(owner) and owner[action.method]
        if type(fn)=="function" then return owner,fn end
    end
    function L:Open(index)
        local owner,fn=self:Handler(index)
        if not owner then self.notice="This addon is not loaded."; self:Refresh(); return false end
        local ok=Call(fn,owner,true)
        if ok then self.notice=nil; if self.frame then self.frame:Hide() end
        else self.notice="This menu could not open. Reload the interface and try again."; self:Refresh() end
        return ok
    end
    function L:Build()
        if self.frame or not self.theme then return end
        local T=self.theme
        local frame=CreateFrame("Frame","RicoSuiteLauncherMenu",UIParent)
        self.frame=frame; self.menu=frame
        frame:SetSize(340,126+#actions*54); frame:SetFrameStrata("DIALOG"); frame:SetClampedToScreen(true); frame:EnableMouse(true)
        frame.ricoSkipSuiteButtons=true
        if Minimap then frame:SetPoint("TOPRIGHT",Minimap,"BOTTOMRIGHT",0,-16) else frame:SetPoint("CENTER") end
        T:Window(frame)
        local title=Text(frame,"",21,T.colors.mint); self.title=title; title:SetPoint("TOPLEFT",18,-22); T:Title(title,"MENU")
        local subtitle=Text(frame,"Your Rico addons",10,T.colors.muted); subtitle:SetPoint("TOPLEFT",18,-57)
        local close=CreateFrame("Button",nil,frame); self.closeButton=close
        close:SetSize(24,24); close:SetPoint("TOPRIGHT",-14,-25); close.background=T:Panel(close)
        close.label=Text(close,"X",11); close.label:SetPoint("CENTER")
        T:Button(close,close.background); close:SetScript("OnClick",function() frame:Hide() end)
        for index,action in ipairs(actions) do
            local actionIndex=index
            local row=CreateFrame("Button",nil,frame)
            row:SetSize(308,44); row:SetPoint("TOPLEFT",16,-88-(index-1)*54)
            row.background=T:Panel(row); T:Button(row,row.background)
            row.title=Text(row,action.name,13,T.colors.mint); row.title:SetPoint("TOPLEFT",10,-7)
            row.hint=Text(row,action.hint,9,T.colors.muted); row.hint:SetPoint("BOTTOMLEFT",10,7)
            row:SetScript("OnClick",function() L:Open(actionIndex) end)
            self.rows[index]=row
        end
        self.status=Text(frame,"",10,T.colors.muted)
        self.status:SetPoint("BOTTOMLEFT",18,16); self.status:SetWidth(304)
        frame:SetScript("OnShow",function() L:Refresh() end)
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="RicoSuiteLauncherMenu" end
        frame:Hide()
    end
    function L:Refresh()
        if not self.frame then return end
        for index,row in ipairs(self.rows) do
            local available=self:Handler(index)~=nil
            row:SetEnabled(available); row:SetAlpha(available and 1 or 0.45)
            row.hint:SetText(available and actions[index].hint or "Addon not loaded")
        end
        self.status:SetText(self.notice or "Rico suite · /rico also opens this menu")
    end
    function L:Toggle(force)
        self:EnsureButton(); self:Build()
        if not self.frame then return false end
        self:RefreshAppearance(); self:Refresh()
        self.frame:SetShown(force==nil and not self.frame:IsShown() or force==true)
        return true
    end
    function L:Attach(name,addon)
        self.registrations[name]=addon
        if not self.theme and Table(addon.Theme) then self.theme=addon.Theme end
        local suite=self:GetSuite()
        if suite and not self.appearanceHook and type(hooksecurefunc)=="function" then
            self.appearanceHook=true
            for _,method in ipairs({"SetAppearance","ApplyProfile"}) do
                if type(suite[method])=="function" then hooksecurefunc(suite,method,function() L:RefreshAppearance() end) end
            end
        end
        self:EnsureButton()
        if self.frame then self:Refresh() end
    end
    L.events=CreateFrame("Frame")
    L.events:RegisterEvent("ADDON_LOADED"); L.events:RegisterEvent("PLAYER_LOGIN")
    L.events:SetScript("OnEvent",function() L:EnsureButton(); if L.frame then L:Refresh() end end)
    SLASH_RICOMENU1,SLASH_RICOMENU2="/rico","/ricomenu"
    SlashCmdList.RICOMENU=function() L:Toggle() end
end
L:Attach(addonName,Addon)
