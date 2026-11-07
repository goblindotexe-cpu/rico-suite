-- Shared Rico profiles. Each addon carries this file and works on its own.
-- Import is a bounded, typed data format; imported text is never executed.
local addonName, Addon = ...
local S = _G.RicoSuite
if not S then
    S = { registrations = {}, windows = setmetatable({}, {__mode = "k"}), version = 1 }
    _G.RicoSuite = S
    local unpack = unpack or table.unpack
    local FONTS = {Friz = "Fonts\\FRIZQT__.TTF", Arial = "Fonts\\ARIALN.TTF"}
    local DEFAULT = {accent = {0.22, 0.83, 0.49}, font = "Friz", scale = 1}
    local PRESETS = {
        {"Emerald", {0.22, 0.83, 0.49}}, {"Sapphire", {0.25, 0.55, 0.95}},
        {"Amethyst", {0.66, 0.38, 0.94}}, {"Gold", {0.96, 0.72, 0.22}},
        {"Crimson", {0.92, 0.25, 0.32}},
    }
    local DENIED = {cvarBackup = true, worldCVars = true, locale = true,
        observations = true, obsSources = true, obsOrder = true, obsZones = true,
        wishlist = true, session = true, data = true}
    local FALLBACK = {
        RicoLoot = {zoneID = 0, tableIndex = 1, includeReference = true, x = 0, y = 0},
        RicoFishing = {selected = 6291, goal = 20, pins = true, reportedPins = false,
            hud = true, hudX = 0, hudY = 165},
        RicoPlates = {enabled = true, showFriendlyNPCs = false, showParty = true,
            showRaid = true, showPower = true, showPowerNPC = false, showClass = true,
            showFaction = true, showLevel = true, showCast = true, healthText = "percent",
            powerText = "value", width = 190, height = 19, scale = 1, fontSize = 11,
            verticalOffset = 0, bubbles = true, bubbleCount = 3, bubbleScale = 1.8,
            maxAnimatedPlates = 24, questMarkers = true, questText = false, useQuestie = true,
            showDebuffs = true, debuffSize = 18, maxDebuffs = 6, debuffsMineOnly = false,
            showBuffs = true, buffSize = 18, maxBuffs = 6, buffsMineOnly = false,
            grayTapped = true, grayTrivial = false, worldHighlight = true,
            worldArrow = true, worldArrowSize = 42, targetBorder = true,
            unitFramesEnabled = true, showPlayerFrame = true, showTargetFrame = true,
            showPetFrame = true, unitPortrait3D = true, unitPortraitZoom = 0.85,
            showClassResources = true, unitFrameWidth = 230, unitFrameHeight = 24,
            unitFrameScale = 1, showTargetOfTarget = true, layoutGridSnap = true,
            layoutFrameSnap = true, layoutGridSize = 8, layoutSnapDistance = 12,
            interruptIndicators = true, aggroIndicator = true, questRoutes = true,
            targetBuffsAll = true,
            partyFrames = true, partyFrameScale = 0.8, partyFrameWidth = 200, partyFrameHeight = 20,
            partyLowHealth = true, partyLowHealthThreshold = 25, partyDispels = true,
            unitFramePositions = {player = {x = -310, y = 250}, target = {x = 310, y = 250}, pet = {x = -310, y = 100}}},
    }
    local function Number(value)
        return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    end
    local function Copy(value, depth)
        if type(value) ~= "table" then return value end
        if (depth or 0) > 8 then return nil end
        local result = {}
        for key, child in pairs(value) do result[key] = Copy(child, (depth or 0) + 1) end
        return result
    end
    local function Name(value)
        return type(value) == "string" and #value > 0 and #value <= 48
            and not value:find("[%c]") and value:match("%S") ~= nil
    end
    local function Combat()
        if not InCombatLockdown then return false end
        local ok, value = pcall(InCombatLockdown)
        if not ok or (issecretvalue and issecretvalue(value)) then return true end
        return value == true or value == 1
    end
    local function Appearance(raw)
        if type(raw) ~= "table" or type(raw.accent) ~= "table" then return nil end
        for key in pairs(raw) do if key ~= "accent" and key ~= "font" and key ~= "scale" then return nil end end
        for key in pairs(raw.accent) do if key ~= 1 and key ~= 2 and key ~= 3 then return nil end end
        local out = {accent = {}, font = raw.font, scale = raw.scale}
        if not FONTS[out.font] or not Number(out.scale) or out.scale < 0.7 or out.scale > 1.3 then return nil end
        for i = 1, 3 do
            local value = raw.accent[i]
            if not Number(value) or value < 0 or value > 1 then return nil end
            out.accent[i] = value
        end
        return out
    end
    function S:Initialize()
        local incoming = type(_G.RicoSuiteDB) == "table" and _G.RicoSuiteDB or nil
        local db = self.db
        if db and incoming and incoming ~= db then
            -- Each independently loadable addon saves the same global. A copy
            -- belonging to a previously disabled addon can be older than the
            -- next copy restored by the client during this login.
            local newer = Number(incoming.revision) and incoming.revision > (db.revision or 0)
            if newer and not self.sessionChanged then
                db = incoming; self.externalRefresh = true
            elseif type(incoming.profiles) == "table" then
                for name, profile in pairs(incoming.profiles) do
                    if Name(name) and type(profile) == "table" and db.profiles[name] == nil then db.profiles[name] = Copy(profile) end
                end
            end
        end
        db = db or incoming or {}
        db.appearance = Appearance(db.appearance) or Copy(DEFAULT)
        db.profiles = type(db.profiles) == "table" and db.profiles or {}
        db.pending = type(db.pending) == "table" and db.pending or {}
        db.windows = type(db.windows) == "table" and db.windows or {}
        db.revision = Number(db.revision) and math.max(0, math.min(1000000000000, db.revision)) or 0
        self.db = db; _G.RicoSuiteDB = db
        return db
    end
    function S:Touch()
        self.db.revision = (self.db.revision or 0) + 1
        self.sessionChanged = true
    end
    function S:Schema(name)
        local reg = self.registrations[name]
        return reg and reg.addon.defaults or FALLBACK[name]
    end
    local function SchemaValue(value, schema, depth, strict)
        if type(schema) == "table" then
            if type(value) ~= "table" or depth > 5 then return nil, false end
            local out = {}
            for key, child in pairs(value) do
                if schema[key] == nil or DENIED[key] then if strict then return nil, false end
                else
                    local clean, ok = SchemaValue(child, schema[key], depth + 1, strict)
                    if not ok then if strict then return nil, false end else out[key] = clean end
                end
            end
            return out, true
        end
        if type(value) ~= type(schema) then return nil, false end
        if type(value) == "number" then return value, Number(value) and math.abs(value) <= 10000000 end
        if type(value) == "boolean" then return value, true end
        if type(value) == "string" then return value, #value <= 120 and not value:find("[%c]") end
        return nil, false
    end
    function S:Settings(name, raw, strict)
        local schema = self:Schema(name)
        if not schema or type(raw) ~= "table" then return nil end
        local out = {}
        for key, value in pairs(raw) do
            if DENIED[key] or schema[key] == nil or (type(schema[key]) == "table" and key ~= "unitFramePositions") then
                if strict then return nil end
            else
                local clean, ok = SchemaValue(value, schema[key], 1, strict)
                if ok then out[key] = clean elseif strict then return nil end
            end
        end
        return out
    end
    local function WindowID(id)
        return type(id) == "string" and #id <= 64 and id:match("^Rico[%w_]+$") ~= nil
    end
    local function Windows(raw)
        if type(raw) ~= "table" then return nil end
        local out, count = {}, 0
        for id, point in pairs(raw) do
            count = count + 1
            if count > 30 or not WindowID(id) or type(point) ~= "table" or not Number(point.x)
                or not Number(point.y) or math.abs(point.x) > 20000 or math.abs(point.y) > 20000 then return nil end
            for key in pairs(point) do if key ~= "x" and key ~= "y" then return nil end end
            out[id] = {x = point.x, y = point.y}
        end
        return out
    end
    function S:ValidateProfile(raw)
        if type(raw) ~= "table" then return nil, "Invalid profile data." end
        for key in pairs(raw) do
            if key ~= "name" and key ~= "appearance" and key ~= "addons" and key ~= "windows" then return nil, "Unknown profile field." end
        end
        if raw.name ~= nil and not Name(raw.name) then return nil, "Invalid profile name." end
        local appearance = Appearance(raw.appearance)
        if not appearance or type(raw.addons) ~= "table" then return nil, "Invalid profile appearance or settings." end
        local out = {name = raw.name, appearance = appearance, addons = {}, windows = Windows(raw.windows or {})}
        if not out.windows then return nil, "Invalid window positions." end
        for name, settings in pairs(raw.addons) do
            if not FALLBACK[name] then return nil, "Unknown addon in profile." end
            out.addons[name] = self:Settings(name, settings, true)
            if not out.addons[name] then return nil, "Invalid settings for " .. name .. "." end
        end
        return out
    end
    function S:Capture(name)
        self:Initialize()
        local profile = {name = name or self.db.active or "Shared", appearance = Copy(self.db.appearance), addons = {}, windows = Copy(self.db.windows)}
        for id, reg in pairs(self.registrations) do
            if type(reg.addon.db) == "table" then profile.addons[id] = self:Settings(id, reg.addon.db, false) end
        end
        -- Preserve settings for currently unloaded addons from the selected profile.
        local previous = self.db.active and self.db.profiles[self.db.active]
        if type(previous) == "table" then for id, settings in pairs(previous.addons or {}) do
            if not profile.addons[id] then profile.addons[id] = Copy(settings) end
        end end
        return profile
    end
    function S:Save(name)
        self:Initialize()
        if not Name(name) then return false, "Use a profile name of 1–48 characters." end
        local total = 0; for _ in pairs(self.db.profiles) do total = total + 1 end
        if total >= 50 and not self.db.profiles[name] then return false, "A maximum of 50 profiles is supported." end
        self.db.profiles[name] = self:Capture(name); self.db.active = name
        self:Touch()
        self:RefreshUI()
        return true, "Saved profile: " .. name
    end
    function S:GetNames()
        self:Initialize()
        local names = {}; for name in pairs(self.db.profiles) do if Name(name) then names[#names + 1] = name end end
        table.sort(names)
        return names
    end
    function S:Delete(name)
        self:Initialize()
        if not self.db.profiles[name] then return false, "Choose a saved profile." end
        if #self:GetNames() < 2 then return false, "Keep at least one saved profile." end
        self.db.profiles[name] = nil
        if self.db.active == name then self.db.active = self:GetNames()[1] end
        self:Touch()
        self:RefreshUI()
        return true, "Deleted profile: " .. name
    end
    local function WriteSettings(dst, src)
        for key, value in pairs(src) do dst[key] = Copy(value) end
    end
    function S:RefreshAddon(reg)
        local addon = reg.addon
        if type(addon.db) ~= "table" then return end
        local theme = addon.Theme
        if theme and theme.ApplyAppearance then theme:ApplyAppearance(self.db.appearance) end
        if addon.name == "RicoPlates" and not addon.initialized then self:RefreshFonts(reg); return end
        if addon.name == "RicoFishing" then
            if addon.GetEntry and not addon:GetEntry(addon.db.selected) then
                addon.db.selected = addon.defaults.selected
            end
            addon.db.goal = math.max(1, math.min(9999, tonumber(addon.db.goal) or 20))
            if addon.Map and addon.Map.Refresh then addon.Map:Refresh() end
            if addon.Refresh then addon:Refresh() end
        elseif addon.ApplySettings then addon:ApplySettings()
        elseif addon.RequestRefresh then addon:RequestRefresh() end
        self:RefreshFonts(reg)
        for frame, record in pairs(self.windows) do if record.name == addon.name then self:StyleWindow(frame, record) end end
        if addon.Options and addon.Options.RefreshControls then addon.Options:RefreshControls() end
    end
    function S:ApplyProfile(profile, name)
        local clean, err = self:ValidateProfile(profile)
        if not clean then return false, err end
        if Combat() then
            self.pendingApply = {profile = clean, name = name}
            return true, "Profile queued until combat ends."
        end
        self.db.appearance, self.db.windows = clean.appearance, clean.windows
        self.db.active = name or clean.name or self.db.active
        self:Touch()
        for id, settings in pairs(clean.addons) do
            local reg = self.registrations[id]
            if reg and type(reg.addon.db) == "table" then
                WriteSettings(reg.addon.db, settings); self.db.pending[id] = nil
            else self.db.pending[id] = Copy(settings) end
        end
        for _, reg in pairs(self.registrations) do self:RefreshAddon(reg) end
        self:RefreshUI()
        return true, "Loaded profile: " .. (name or clean.name or "Shared")
    end
    function S:Load(name)
        self:Initialize()
        if not self.db.profiles[name] then return false, "Choose a saved profile." end
        return self:ApplyProfile(self.db.profiles[name], name)
    end
    function S:SetAppearance(raw)
        self:Initialize()
        local appearance = Appearance(raw)
        if not appearance then return false, "Use RGB 0–255, a supported font and menu scale 0.70–1.30." end
        local profile = self:Capture(self.db.active or "Shared")
        profile.appearance = appearance
        return self:ApplyProfile(profile, self.db.active)
    end
    local function EncodeString(text)
        return (text:gsub("([^%w _%-%.])", function(c) return string.format("%%%02X", string.byte(c)) end))
    end
    local function DecodeString(text)
        if text:gsub("%%%x%x", ""):find("%", 1, true) then return nil end
        return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
    end
    function S:Export(name)
        self:Initialize()
        local profile = name and self.db.profiles[name] or self:Capture(self.db.active or "Shared")
        if not profile then return nil, "Choose a saved profile." end
        local lines = {"RICO-PROFILE-1"}
        local function Flatten(value, path)
            if type(value) == "table" then
                local keys = {}; for key in pairs(value) do keys[#keys + 1] = key end
                table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
                for _, key in ipairs(keys) do Flatten(value[key], path == "" and tostring(key) or path .. "." .. tostring(key)) end
            elseif type(value) == "boolean" then lines[#lines + 1] = path .. "=b:" .. (value and "1" or "0")
            elseif type(value) == "number" then lines[#lines + 1] = path .. "=n:" .. string.format("%.12g", value)
            elseif type(value) == "string" then lines[#lines + 1] = path .. "=s:" .. EncodeString(value) end
        end
        Flatten(profile, "")
        local result = table.concat(lines, "\n")
        if #result > 32768 then return nil, "Profile is too large to export." end
        return result
    end
    function S:Import(text, name)
        self:Initialize()
        if type(text) ~= "string" or #text > 32768 or #text < 15 then return false, "Invalid or oversized profile text." end
        text = text:gsub("\r\n", "\n")
        local header, rest = text:match("^([^\n]+)\n(.*)$")
        if header ~= "RICO-PROFILE-1" then return false, "Unsupported profile format." end
        local raw, paths, count = {}, {}, 0
        for line in (rest .. "\n"):gmatch("([^\n]*)\n") do
            if line ~= "" then
                count = count + 1
                if count > 512 then return false, "Too many profile fields." end
                local path, kind, value = line:match("^([%w_%.]+)=([bns]):(.*)$")
                if not path or #path > 160 or paths[path] or path:find("%.%.") or path:sub(1, 1) == "." or path:sub(-1) == "." then
                    return false, "Malformed or duplicate profile field."
                end
                paths[path] = true
                local pieces = {}; for part in path:gmatch("[^%.]+") do pieces[#pieces + 1] = tonumber(part) or part end
                if #pieces > 7 then return false, "Profile nesting is too deep." end
                local target = raw
                for i = 1, #pieces - 1 do
                    local key = pieces[i]
                    if target[key] ~= nil and type(target[key]) ~= "table" then return false, "Conflicting profile fields." end
                    target[key] = target[key] or {}; target = target[key]
                end
                if target[pieces[#pieces]] ~= nil then return false, "Conflicting profile fields." end
                local decoded
                if kind == "b" then if value ~= "0" and value ~= "1" then return false, "Invalid boolean." end; decoded = value == "1"
                elseif kind == "n" then decoded = tonumber(value); if not Number(decoded) then return false, "Invalid number." end
                else decoded = DecodeString(value); if not decoded then return false, "Invalid text encoding." end end
                target[pieces[#pieces]] = decoded
            end
        end
        raw.addons = raw.addons or {}; raw.windows = raw.windows or {}
        local clean, err = self:ValidateProfile(raw)
        if not clean then return false, err end
        local chosen = name and name ~= "" and name or clean.name or "Imported"
        if not Name(chosen) then return false, "Invalid profile name." end
        local total = #self:GetNames()
        if total >= 50 and not self.db.profiles[chosen] then return false, "A maximum of 50 profiles is supported." end
        clean.name = chosen; self.db.profiles[chosen] = clean
        self:Touch()
        self:RefreshUI()
        return true, chosen
    end
    function S:Font(text, theme)
        if not text or not text.GetFont or not text.SetFont then return end
        local ok, _, size, flags = pcall(text.GetFont, text)
        if ok and Number(size) then text:SetFont(theme.font, size, flags or "") end
    end
    function S:RefreshPlateFonts(p, theme)
        if not p or not theme then return end
        for _, fs in ipairs({p.name, p.healthText, p.level, p.power and p.power.text, p.cast and p.cast.text}) do self:Font(fs, theme) end
    end
    function S:RefreshFonts(reg)
        local addon, theme = reg.addon, reg.addon.Theme
        if not theme then return end
        if addon.Plates then for _, plate in pairs(addon.Plates.frames or {}) do self:RefreshPlateFonts(plate, theme) end end
        if addon.UnitFrames then for _, entry in pairs(addon.UnitFrames.frames or {}) do
            self:RefreshPlateFonts(entry.plate, theme); self:Font(entry.status, theme)
            self:Font(entry.rankBadge and entry.rankBadge.label, theme)
            self:Font(entry.classResources and entry.classResources.text, theme)
        end end
        local targetTarget = addon.UnitFrames and addon.UnitFrames.targetTarget
        if targetTarget then self:Font(targetTarget.name, theme); self:Font(targetTarget.label, theme) end
        if addon.PartyFrames and type(addon.PartyFrames.RefreshFonts) == "function" then addon.PartyFrames:RefreshFonts() end
        if addon.Dispels and type(addon.Dispels.RefreshFonts) == "function" then addon.Dispels:RefreshFonts() end
        if addon.Mining and addon.Mining.UI and type(addon.Mining.UI.RefreshFonts) == "function" then addon.Mining.UI:RefreshFonts() end
    end
    function S:RecordWindow(frame, record)
        local id = frame:GetName()
        if not WindowID(id) or id == "RicoSuiteProfiles" then return end
        local x, y = frame:GetCenter()
        local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if not Number(x) or not Number(y) or not Number(scale) or not Number(parentScale) or parentScale <= 0 then return end
        local px, py = x * scale / parentScale, y * scale / parentScale
        self.db.windows[id] = {x = px - UIParent:GetWidth() / 2, y = py - UIParent:GetHeight() / 2}
        self:Touch()
        if record.name == "RicoFishing" and id == "RicoFishingTracker" then
            local addon = self.registrations.RicoFishing.addon
            addon.db.hudX, addon.db.hudY = px - UIParent:GetWidth() / 2, py
        end
    end
    function S:StyleWindow(frame, record)
        if Combat() then return end
        local appearance = self.db.appearance
        local base = frame.ricoBaseScale or 1
        local width, height = frame:GetWidth(), frame:GetHeight()
        local scale = base * appearance.scale
        if Number(width) and Number(height) and width > 0 and height > 0 then
            scale = math.min(scale, math.max(0.4, (UIParent:GetWidth() - 24) / width), math.max(0.4, (UIParent:GetHeight() - 24) / height))
        end
        frame:SetScale(scale)
        local position = self.db.windows[frame:GetName() or ""]
        if type(position) == "table" and Number(position.x) and Number(position.y) then
            frame:ClearAllPoints(); frame:SetPoint("CENTER", UIParent, "CENTER", position.x / scale, position.y / scale)
        elseif frame:GetName() == "RicoFishingTracker" then
            local addon = self.registrations.RicoFishing and self.registrations.RicoFishing.addon
            if addon and addon.db then
                frame:ClearAllPoints(); frame:SetPoint("CENTER", UIParent, "BOTTOM", addon.db.hudX / scale, addon.db.hudY / scale)
            end
        end
        if record.theme.RefreshWindow then record.theme:RefreshWindow(frame) end
    end
    function S:AttachWindow(addon, frame, compact)
        self:Initialize()
        local record = {name = addon.name or addonName, theme = addon.Theme}
        self.windows[frame] = record
        frame.ricoBaseScale = frame:GetScale()
        frame:HookScript("OnDragStop", function() S:RecordWindow(frame, record) end)
        if not compact and not frame.ricoSkipSuiteButtons then
            local theme = addon.Theme
            local button = CreateFrame("Button", nil, frame)
            button:SetSize(88, 28)
            button:SetPoint("TOPRIGHT", record.name == "RicoLoot" and -204 or -108, -29)
            button.background = theme:Panel(button)
            button.label = button:CreateFontString(nil, "OVERLAY")
            button.label:SetFont(theme.font, 11, "")
            button.label:SetPoint("CENTER"); button.label:SetText("Profiles")
            button:SetScript("OnClick", function() S:Toggle(true) end)
            theme:Button(button, button.background)
            frame.ricoProfilesButton = button
        end
        local function Finish() S:StyleWindow(frame, record) end
        if C_Timer and C_Timer.After then C_Timer.After(0, Finish) else Finish() end
    end
    function S:InstallHooks(reg)
        local addon = reg.addon
        local function Wrap(owner, key, after)
            if not owner or type(owner[key]) ~= "function" then return end
            reg.hooks = reg.hooks or {}
            local id = tostring(owner) .. key
            if reg.hooks[id] then return end
            reg.hooks[id] = true
            local original = owner[key]
            owner[key] = function(self, ...)
                local wasMoving = self.moving
                local args = {...}
                local results = {original(self, ...)}
                after(self, wasMoving, unpack(args))
                return unpack(results)
            end
        end
        local function WindowsRefresh()
            if addon.Theme.ApplyAppearance then addon.Theme:ApplyAppearance(S.db.appearance) end
            for frame, record in pairs(S.windows) do if record.name == addon.name then S:StyleWindow(frame, record) end end
        end
        for _, owner in ipairs({addon.UI or false, addon.MobLoot or false, addon.Options or false}) do
            if owner then
                Wrap(owner, "Build", WindowsRefresh)
                Wrap(owner, "Toggle", WindowsRefresh)
                Wrap(owner, "Open", WindowsRefresh)
                Wrap(owner, "FinishMove", function(self, moving)
                    if moving and self.frame then S:RecordWindow(self.frame, S.windows[self.frame] or {name = addon.name}) end
                end)
                Wrap(owner, "FitWindow", function(self)
                    if self.frame then self.frame.ricoBaseScale = self.frame:GetScale(); S:StyleWindow(self.frame, S.windows[self.frame] or {name = addon.name, theme = addon.Theme}) end
                end)
            end
        end
        Wrap(addon, "ApplySettings", function() S:RefreshFonts(reg) end)
        Wrap(addon.Plates, "Layout", function(_, _, plate) S:RefreshPlateFonts(plate, addon.Theme) end)
        Wrap(addon.UnitFrames, "ConfigureTargetTarget", function() S:RefreshFonts(reg) end)
    end
    function S:Register(name, addon)
        self:Initialize()
        self.registrations[name] = self.registrations[name] or {addon = addon}
        local reg = self.registrations[name]; reg.addon = addon
        if addon.Theme and addon.Theme.ApplyAppearance then addon.Theme:ApplyAppearance(self.db.appearance) end
        self:ProcessRegistrations()
    end
    function S:ProcessRegistrations()
        self:Initialize()
        for name, reg in pairs(self.registrations) do
            if type(reg.addon.db) == "table" then
                self:InstallHooks(reg)
                local refresh = not reg.ready or self.db.pending[name] ~= nil or self.externalRefresh
                if self.db.pending[name] and not Combat() then
                    local values = self:Settings(name, self.db.pending[name], true)
                    if values then WriteSettings(reg.addon.db, values) end
                    self.db.pending[name] = nil
                end
                reg.ready = true
                if refresh then self:RefreshAddon(reg) end
            end
        end
        self.externalRefresh = nil
    end
    function S:Message(text, success)
        if self.status then
            self.status:SetText(text or "")
            self.status:SetTextColor(success and 0.45 or 1, success and 0.92 or 0.65, success and 0.67 or 0.27)
        end
    end
    function S:BuildUI()
        if self.frame then return end
        local owner
        for _, reg in pairs(self.registrations) do if reg.addon.Theme then owner = reg.addon; break end end
        if not owner then return end
        local T = owner.Theme
        local frame = CreateFrame("Frame", "RicoSuiteProfiles", UIParent)
        frame:SetSize(680, 540); frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG"); frame:SetClampedToScreen(true)
        frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        frame.ricoSkipSuiteButtons = true
        T:Window(frame); self.frame = frame
        local function Text(parent, text, size)
            local fs = (parent.ricoForeground or parent):CreateFontString(nil, "OVERLAY")
            fs:SetFont(T.font, size or 11, ""); fs:SetTextColor(unpack(T.colors.text))
            fs:SetJustifyH("LEFT"); fs:SetText(text or "")
            return fs
        end
        local function Button(label, width, x, y, action)
            local b = CreateFrame("Button", nil, frame); b:SetSize(width, 28); b:SetPoint("TOPLEFT", x, y)
            b.background = T:Panel(b); b.label = Text(b, label); b.label:SetPoint("CENTER")
            b:SetScript("OnClick", action); T:Button(b, b.background); return b
        end
        local function Input(width, x, y, max)
            local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            input:SetSize(width, 28); input:SetPoint("TOPLEFT", x, y); input:SetAutoFocus(false)
            input:SetMaxLetters(max or 48); T:Input(input)
            input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            return input
        end
        local title = Text(frame, "", 26); title:SetPoint("TOPLEFT", 24, -22); T:Title(title, "PROFILES")
        local hint = Text(frame, "Appearance and saved layouts for every loaded Rico addon", 10)
        hint:SetPoint("TOPLEFT", 24, -57)
        local close = Button("Close", 72, 584, -29, function() frame:Hide() end)
        close:SetFrameLevel(frame:GetFrameLevel() + 5)
        local label = Text(frame, "Profile name", 11); label:SetPoint("TOPLEFT", 24, -95)
        self.nameBox = Input(272, 112, -86)
        Button("Save", 76, 396, -86, function() local ok, msg = S:Save(S.nameBox:GetText()); S:Message(msg, ok) end)
        Button("Load", 76, 482, -86, function() local ok, msg = S:Load(S.nameBox:GetText()); S:Message(msg, ok) end)
        Button("Delete", 76, 568, -86, function() local ok, msg = S:Delete(S.nameBox:GetText()); S:Message(msg, ok) end)
        self.choose = Button("Saved profiles", 360, 24, -126, function()
            local names = S:GetNames(); if #names == 0 then return end
            local current = 0; for i, name in ipairs(names) do if name == S.nameBox:GetText() then current = i end end
            S.nameBox:SetText(names[current % #names + 1]); S.choose.label:SetText("Choose: " .. names[current % #names + 1])
        end)
        local cycleHint = Text(frame, "Click to cycle through saved profiles", 10); cycleHint:SetPoint("TOPLEFT", 400, -135)
        local appearance = Text(frame, "SHARED APPEARANCE", 11); appearance:SetPoint("TOPLEFT", 24, -174)
        self.palette = 1
        self.preset = Button("Emerald", 130, 24, -198, function()
            S.palette = S.palette % #PRESETS + 1; S.preset.label:SetText(PRESETS[S.palette][1])
            for i = 1, 3 do S.rgb[i]:SetText(tostring(math.floor(PRESETS[S.palette][2][i] * 255 + 0.5))) end
        end)
        self.rgb = {Input(42, 170, -198, 3), Input(42, 221, -198, 3), Input(42, 272, -198, 3)}
        self.fontChoice = "Friz"
        self.fontButton = Button("Font: Friz", 148, 332, -198, function()
            S.fontChoice = S.fontChoice == "Friz" and "Arial" or "Friz"; S.fontButton.label:SetText("Font: " .. S.fontChoice)
        end)
        local scaleLabel = Text(frame, "Menu scale", 10); scaleLabel:SetPoint("TOPLEFT", 496, -206)
        self.scaleBox = Input(72, 572, -198, 4)
        Button("Apply appearance", 148, 496, -238, function()
            local raw = {accent = {}, font = S.fontChoice, scale = tonumber(S.scaleBox:GetText())}
            for i = 1, 3 do raw.accent[i] = tonumber(S.rgb[i]:GetText()); if raw.accent[i] then raw.accent[i] = raw.accent[i] / 255 end end
            local ok, msg = S:SetAppearance(raw); S:Message(ok and (Combat() and msg or "Appearance applied to all loaded Rico addons.") or msg, ok)
        end)
        local help = Text(frame, "RGB 0–255 • scale 0.70–1.30\nProfiles also save unit-frame settings and positions.", 10)
        help:SetPoint("TOPLEFT", 24, -238); help:SetWidth(440)
        local sharing = Text(frame, "SHARE SETTINGS — loot records, wishlist and session data are excluded", 10)
        sharing:SetPoint("TOPLEFT", 24, -286)
        local scroll = CreateFrame("ScrollFrame", nil, frame)
        scroll:SetSize(620, 126); scroll:SetPoint("TOPLEFT", 24, -308); T:Panel(scroll)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetSize(600, 126); edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetMaxLetters(32768)
        edit:EnableMouse(true)
        edit:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
        edit:SetFont(T.font, 10, ""); edit:SetTextColor(unpack(T.colors.text)); edit:SetTextInsets(8, 8, 8, 8)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnTextChanged", function(self)
            local _, lines = self:GetText():gsub("\n", "")
            self:SetHeight(math.max(126, math.min(16000, (lines + 2) * 14)))
        end)
        scroll:SetScrollChild(edit)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            S.scrollOffset = math.max(0, math.min(math.max(0, edit:GetHeight() - 126), (S.scrollOffset or 0) - delta * 24))
            self:SetVerticalScroll(S.scrollOffset)
        end)
        self.shareBox = edit
        Button("Export current", 174, 24, -450, function()
            local data, err = S:Export()
            if data then S.shareBox:SetText(data); S.shareBox:SetFocus(); S.shareBox:HighlightText(); S:Message("Press Ctrl+C to copy this profile.", true)
            else S:Message(err, false) end
        end)
        Button("Import & load", 174, 210, -450, function()
            local ok, name = S:Import(S.shareBox:GetText(), S.nameBox:GetText())
            if ok then local loaded, message = S:Load(name); S:Message(message, loaded) else S:Message(name, false) end
        end)
        self.status = Text(frame, "", 11); self.status:SetPoint("TOPLEFT", 24, -498); self.status:SetWidth(620)
        self.status:SetWordWrap(true)
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "RicoSuiteProfiles" end
        frame:Hide()
    end
    function S:RefreshUI()
        if not self.frame then return end
        local a = self.db.appearance
        self.nameBox:SetText(self.db.active or self:GetNames()[1] or "Default")
        self.choose.label:SetText("Choose: " .. self.nameBox:GetText())
        self.fontChoice = a.font; self.fontButton.label:SetText("Font: " .. a.font)
        self.scaleBox:SetText(string.format("%.2f", a.scale))
        for i = 1, 3 do self.rgb[i]:SetText(tostring(math.floor(a.accent[i] * 255 + 0.5))) end
    end
    function S:Toggle(force)
        self:Initialize(); self:ProcessRegistrations()
        if #self:GetNames() == 0 then self:Save("Default") end
        self:BuildUI(); if not self.frame then return end
        self:RefreshUI(); self.frame:SetShown(force == nil and not self.frame:IsShown() or force == true)
    end
    S.events = CreateFrame("Frame")
    S.events:RegisterEvent("ADDON_LOADED"); S.events:RegisterEvent("PLAYER_LOGIN"); S.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    S.events:SetScript("OnEvent", function(_, event)
        local function Ready()
            S:ProcessRegistrations()
            if event == "PLAYER_REGEN_ENABLED" and S.pendingApply then
                local pending = S.pendingApply; S.pendingApply = nil; S:ApplyProfile(pending.profile, pending.name)
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, Ready) else Ready() end
    end)
    SLASH_RICOPROFILES1, SLASH_RICOPROFILES2 = "/rprofiles", "/ricoprofiles"
    SlashCmdList.RICOPROFILES = function() S:Toggle() end
end
S:Register(addonName, Addon)
