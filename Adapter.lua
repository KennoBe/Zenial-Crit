local _, NS = ...
local Adapter = {}
NS.Adapter = Adapter

function Adapter.New(env)
    local A = {env = env, handles = {}, nameplateCache = {}, nameplateGenerations = {}, nameplateUnits = {}}

    -- Opt-in trace, routed through the DevLogger's bounded, secret-aware encoder.
    function A:Diagnostic(stage, ...)
        local logger = env.ZenialDevLogger
        if type(logger) ~= "table" or not logger.db or logger.running ~= true
            or logger.mode ~= "crit" or type(logger.Add) ~= "function" then return end
        pcall(logger.Add, "CRIT_TRACE", stage, ...)
    end

    function A:NameplateRead(label, fn, ...)
        if not self.traceNameplate then return pcall(fn, ...) end
        local function pack(...) return {n = select("#", ...), ...} end
        local result = pack(pcall(fn, ...))
        local fields = {}
        for index = 1, result.n do
            local value = result[index]
            -- Do not enumerate Blizzard frame tables in the logger export.
            if self:Public(value) and (type(value) == "table" or type(value) == "userdata") then
                fields[index] = "<" .. type(value) .. ">"
            else fields[index] = value end
        end
        self:Diagnostic(label, unpack(fields, 1, result.n))
        return unpack(result, 1, result.n)
    end

    function A:Public(value)
        if type(env.issecretvalue) ~= "function" then return false end
        local ok, secret = pcall(env.issecretvalue, value)
        return ok and secret == false
    end

    function A:Time()
        if type(env.GetTime) ~= "function" then return nil end
        local ok, result = pcall(env.GetTime)
        if ok and self:Public(result) and type(result) == "number" and result == result
            and result ~= math.huge and result ~= -math.huge then return result end
    end

    function A:Epoch()
        if type(env.GetServerTime) ~= "function" then return nil end
        local ok, result = pcall(env.GetServerTime)
        if ok and self:Public(result) and type(result) == "number" and result == result
            and result >= 1 and result <= 4102444800 then return math.floor(result) end
    end

    function A:Text(fn, limit, ...)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, ...)
        if not ok or not self:Public(value) or type(value) ~= "string" then return nil end
        value = value:gsub("[%c]", ""):match("^%s*(.-)%s*$") or ""
        if value == "" then return nil end
        return value:sub(1, limit or 80)
    end

    function A:Frame(kind, name, parent, template)
        if type(env.CreateFrame) ~= "function" then return nil end
        local ok, result = pcall(env.CreateFrame, kind or "Frame", name, parent or env.UIParent, template)
        if ok then return result end
    end

    function A:Root() return env.UIParent end
    function A:Font() return env.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end
    function A:FontStyle(style)
        local locale = "enUS"
        if type(env.GetLocale) == "function" then
            local ok, value = pcall(env.GetLocale)
            if ok and type(value) == "string" then locale = value end
        end
        local latin = locale ~= "koKR" and locale ~= "zhCN" and locale ~= "zhTW"
        local specs = {
            standard = {self:Font(), 55, "OUTLINE"},
            comic = {latin and "Fonts\\SKURRI_CYR.TTF" or self:Font(), 62, "THICKOUTLINE"},
            epic = {latin and "Fonts\\MORPHEUS_CYR.TTF" or self:Font(), 58, "THICKOUTLINE"},
            heavy = {"Fonts\\ARIALN.TTF", 64, "THICKOUTLINE"},
        }
        local spec = specs[style] or specs.standard
        return spec[1], spec[2], spec[3]
    end

    function A:ApplyDamageFont(style)
        local path = self:FontStyle(style)
        if self.damageFontPath == path then return false end
        self.damageFontPath = path
        env.DAMAGE_TEXT_FONT = path
        return true
    end

    function A:Position(frame)
        local ok, x, y = pcall(frame.GetCenter, frame)
        local rootOK, rootX, rootY = pcall(env.UIParent.GetCenter, env.UIParent)
        if ok and rootOK and self:Public(x) and self:Public(y) and self:Public(rootX) and self:Public(rootY)
            and type(x) == "number" and type(y) == "number"
            and type(rootX) == "number" and type(rootY) == "number" then
            return x - rootX, y - rootY
        end
    end

    function A:Register(frame, event)
        if not frame or type(frame.RegisterEvent) ~= "function" then return false end
        local ok, result = pcall(frame.RegisterEvent, frame, event)
        if not ok or not self:Public(result) then return false end
        return result ~= false
    end

    -- Unit-filtered registration only when the client confirms it with true.
    -- Otherwise register globally; the handler still filters the unit token.
    function A:RegisterUnit(frame, event, ...)
        if frame and type(frame.RegisterUnitEvent) == "function" then
            local ok, result = pcall(frame.RegisterUnitEvent, frame, event, ...)
            if ok and self:Public(result) and result == true then return true, "unit" end
        end
        return self:Register(frame, event), "global"
    end

    function A:GUID(unit)
        if type(env.UnitGUID) ~= "function" then return nil end
        if self.traceNameplate then self:Diagnostic("guid_unit", unit) end
        local ok, guid = self:NameplateRead("UnitGUID", env.UnitGUID, unit)
        if ok and self:Public(guid) and type(guid) == "string" and guid ~= "" then return guid end
    end

    -- Resolve public identity only. Native nameplate geometry cannot be measured in Forever.
    local function accessible(frame)
        if not A:Public(frame) then return false, "frame secret/inspector unavailable" end
        if type(frame) ~= "table" and type(frame) ~= "userdata" then return false, "frame missing" end
        if type(frame.IsForbidden) == "function" then
            local ok, forbidden = A:NameplateRead("IsForbidden", frame.IsForbidden, frame)
            if not ok or not A:Public(forbidden) or forbidden ~= false then return false, "frame forbidden/unreadable" end
        end
        return true
    end

    function A:PlateUnit(plate)
        if not accessible(plate) then return nil end
        if type(plate.GetUnit) == "function" then
            local ok, unit = self:NameplateRead("plate.GetUnit", plate.GetUnit, plate)
            if ok and self:Public(unit) and type(unit) == "string" then return unit end
        end
        local unitFrame = plate.UnitFrame
        if accessible(unitFrame) and self:Public(unitFrame.unit) and type(unitFrame.unit) == "string" then
            return unitFrame.unit
        end
    end

    function A:GetNameplate(unit)
        if not self:Public(unit) or type(unit) ~= "string" then return nil end
        if type(env.C_NamePlate) ~= "table" or type(env.C_NamePlate.GetNamePlateForUnit) ~= "function" then return nil end
        local ok, plate = self:NameplateRead("GetNamePlateForUnit:" .. unit, env.C_NamePlate.GetNamePlateForUnit, unit)
        local readable, reason = accessible(plate)
        if self.traceNameplate then self:Diagnostic("plate_access:" .. unit, readable, reason) end
        if ok and readable then return plate end
    end

    function A:RememberNameplate(plate, fallbackUnit, now)
        if not accessible(plate) then return nil end
        local unit = self:PlateUnit(plate) or fallbackUnit
        local guid = unit and self:GUID(unit)
        if self.traceNameplate then self:Diagnostic("remember_identity", unit, guid) end
        if not guid then return nil end
        local shownOK, shown = self:NameplateRead("plate.IsShown", plate.IsShown, plate)
        if not shownOK or not self:Public(shown) or shown ~= true then return nil end
        local anchor = {plate = plate, unit = unit, guid = guid, at = now,
            generation = self.nameplateGenerations[unit] or 0}
        self.nameplateCache[guid] = anchor
        self.nameplateUnits[unit] = guid
        return anchor
    end

    -- Unit tokens that were not usable at NAME_PLATE_UNIT_ADDED (plate nil, hidden or
    -- unreadable) stay pending (token -> plate or nil + generation) until resolved, removed
    -- or expired (~2 s). Retried on OnShow, on-demand scans, REMOVED, and by a ~10 Hz
    -- OnUpdate that only exists while the pending set is non-empty.
    local PENDING_TTL, PENDING_STEP = 2, 0.1

    function A:HookPlate(plate)
        self.hookedPlates = self.hookedPlates or setmetatable({}, {__mode = "k"})
        if self.hookedPlates[plate] or type(plate.HookScript) ~= "function" then return end
        local ok = pcall(plate.HookScript, plate, "OnShow", function()
            local now = self:Time()
            for pendingUnit, entry in pairs(self.pendingPlates or {}) do
                if entry.plate == plate then pcall(self.RetryPending, self, pendingUnit, now) end
            end
        end)
        if ok then self.hookedPlates[plate] = true end
    end

    function A:SyncPendingPump()
        local tracker = self.nameplateTracker
        if not tracker then return end
        if self.pendingPlates and next(self.pendingPlates) then
            if self.pendingPumpActive then return end
            self.pendingPumpActive, self.pendingPumpAcc = true, 0
            tracker:SetScript("OnUpdate", function(_, elapsed)
                if type(elapsed) ~= "number" then return end
                self.pendingPumpAcc = (self.pendingPumpAcc or 0) + elapsed
                if self.pendingPumpAcc < PENDING_STEP then return end
                local step = self.pendingPumpAcc; self.pendingPumpAcc = 0
                local now = self:Time()
                for unit, entry in pairs(self.pendingPlates or {}) do
                    entry.age = (entry.age or 0) + step
                    if entry.age > PENDING_TTL then self.pendingPlates[unit] = nil
                    else pcall(self.RetryPending, self, unit, now) end
                end
                self:SyncPendingPump()
            end)
        elseif self.pendingPumpActive then
            self.pendingPumpActive = false
            tracker:SetScript("OnUpdate", nil)
        end
    end

    function A:AddPending(plate, unit)
        self.pendingPlates = self.pendingPlates or {}
        self.pendingPlates[unit] = {plate = plate, generation = self.nameplateGenerations[unit] or 0, age = 0}
        if plate then self:HookPlate(plate) end
        self:SyncPendingPump()
    end

    function A:ClearPending(unit)
        if self.pendingPlates then self.pendingPlates[unit] = nil end
        self:SyncPendingPump()
    end

    function A:RetryPending(unit, now)
        local entry = self.pendingPlates and self.pendingPlates[unit]
        if not entry then return nil end
        if entry.generation ~= (self.nameplateGenerations[unit] or 0) then
            self:ClearPending(unit)
            return nil
        end
        if not entry.plate then
            entry.plate = self:GetNameplate(unit)
            if entry.plate then self:HookPlate(entry.plate) end
        end
        local ok, anchor = pcall(self.RememberNameplate, self, entry.plate, unit, now or self:Time())
        if ok and anchor then self:ClearPending(unit); return anchor end
    end

    function A:ScanNameplates()
        local now = self:Time()
        if not now then return end
        if self.pendingPlates then
            for unit in pairs(self.pendingPlates) do self:RetryPending(unit, now) end
        end
        -- Cache all visible victims so pet kills and non-target kills can use their own plate.
        if type(env.C_NamePlate) == "table" and type(env.C_NamePlate.GetNamePlates) == "function" then
            local ok, plates = pcall(env.C_NamePlate.GetNamePlates)
            if ok and self:Public(plates) and type(plates) == "table" then
                if type(env.canaccesstable) == "function" then
                    local allowed, readable = pcall(env.canaccesstable, plates)
                    if not allowed or not self:Public(readable) or readable ~= true then plates = {} end
                end
                for _, plate in pairs(plates) do self:RememberNameplate(plate, nil, now) end
            end
        end
        self:RememberNameplate(self:GetNameplate("target"), "target", now)
        -- Short-lived identity references support kill events after nameplate removal.
        for guid, anchor in pairs(self.nameplateCache) do
            if now - anchor.at > 1 then self.nameplateCache[guid] = nil end
        end
    end

    -- Removed plates (and plates whose token now shows another unit) stay
    -- usable as kill anchors for one second; visible plates never expire here.
    function A:PruneNameplates(now)
        if not now then return end
        for guid, anchor in pairs(self.nameplateCache) do
            if (anchor.removed or self.nameplateUnits[anchor.unit] ~= guid) and now - anchor.at > 1 then
                self.nameplateCache[guid] = nil
            end
        end
    end

    -- Event-driven identity cache: ADDED/REMOVED keep it current, triggers scan
    -- on demand (NameplateContext). No permanent per-frame scan.
    function A:TrackNameplates(enabled)
        if not enabled then
            if self.nameplateTracker then self.nameplateTracker:SetScript("OnUpdate", nil) end
            if self.nameplateTracker then self.nameplateTracker:UnregisterAllEvents() end
            self.nameplateTracking = false
            self.nameplateCache = {}
            self.nameplateUnits, self.nameplateGenerations, self.pendingPlates = {}, {}, {}
            self.pendingPumpActive = false
            return
        end
        if not self.nameplateTracker then self.nameplateTracker = self:Frame() end
        if not self.nameplateTracker or self.nameplateTracking then return end
        self.nameplateTracking = true
        self:Register(self.nameplateTracker, "NAME_PLATE_UNIT_ADDED")
        self:Register(self.nameplateTracker, "NAME_PLATE_UNIT_REMOVED")
        self.nameplateTracker:SetScript("OnEvent", function(_, event, unit)
            if not self:Public(unit) or type(unit) ~= "string" then return end
            local now = self:Time()
            if event == "NAME_PLATE_UNIT_ADDED" then
                self.nameplateGenerations[unit] = (self.nameplateGenerations[unit] or 0) + 1
                self:ClearPending(unit)
                local plate = self:GetNameplate(unit)
                local ok, anchor = pcall(self.RememberNameplate, self, plate, unit, now)
                if not (ok and anchor) then self:AddPending(plate, unit) end
            else
                local guid = self.nameplateUnits[unit]
                local anchor = guid and self.nameplateCache[guid]
                if not anchor or anchor.unit ~= unit then
                    -- The binding was not cached while visible; read it once before removal.
                    local ok, result = pcall(self.RememberNameplate, self, self:GetNameplate(unit), unit, now)
                    anchor = ok and result or nil
                    if not anchor then
                        -- Plate was shown after ADDED (hook) but is already hidden/unresolvable now.
                        anchor = self:RetryPending(unit, now)
                    end
                end
                self:ClearPending(unit)
                if anchor then anchor.at, anchor.removed = now or anchor.at, true end
            end
            self:PruneNameplates(now)
        end)
        self:ScanNameplates()
    end

    function A:NameplateContext(victimGUID)
        local logger = env.ZenialDevLogger
        self.traceNameplate = type(logger) == "table" and logger.running == true and logger.mode == "crit"
        self:Diagnostic("anchor_begin", victimGUID)
        self:ScanNameplates()
        local anchor
        if victimGUID then
            anchor = self.nameplateCache[victimGUID]
        else
            -- Crits/previews require a currently visible target; only kills may use the death cache.
            anchor = self:RememberNameplate(self:GetNameplate("target"), "target", self:Time())
        end
        if not anchor or not self:FollowNameplate(anchor) then
            self:Diagnostic("anchor_missing", victimGUID and "victim cache empty/expired/reused" or "target plate has no readable identity")
            self.traceNameplate = false
            return nil
        end
        self:Diagnostic("anchor_ready", anchor.unit, anchor.guid, "native-relative")
        self.traceNameplate = false
        -- Effects own a snapshot; target switches and pooled-plate reuse cannot retarget it.
        return {plate = anchor.plate, unit = anchor.unit, guid = anchor.guid, generation = anchor.generation}
    end

    function A:FollowNameplate(anchor)
        if not accessible(anchor.plate) or (self.nameplateGenerations[anchor.unit] or 0) ~= anchor.generation then return false end
        local unit = self:PlateUnit(anchor.plate)
        if unit then
            if unit ~= anchor.unit then return false end
            local guid = self:GUID(unit)
            if guid and guid ~= anchor.guid then return false end
            local plate = self:GetNameplate(unit)
            if plate and plate ~= anchor.plate then return false end
            if plate then return guid == anchor.guid end
        end
        -- Keep the engine-managed reference for the remaining fade after removal.
        -- Its parent stays UIParent, so hiding the native plate does not hide the text.
        return true
    end

    function A:CharacterIdentity()
        local guid = self:GUID("player")
        local name, realm
        if type(env.UnitFullName) == "function" then
            local ok, first, second = pcall(env.UnitFullName, "player")
            if ok and self:Public(first) and self:Public(second) then
                if type(first) == "string" then name = first end
                if type(second) == "string" then realm = second end
            end
        end
        name = name or self:Text(env.UnitName, 48, "player")
        realm = realm or self:Text(env.GetRealmName, 48)
        if type(name) == "string" then name = name:gsub("[%c]", ""):match("^%s*(.-)%s*$") end
        if type(realm) == "string" then realm = realm:gsub("[%c]", ""):match("^%s*(.-)%s*$") end
        local display = name and name ~= "" and (realm and realm ~= "" and name .. "-" .. realm or name) or nil
        if guid then return "guid:" .. guid, display or name or guid end
        if display then return "name:" .. display, display end
    end

    function A:CritSnapshot(amount, school, unit)
        if not self:Public(amount) or type(amount) ~= "number" or amount ~= amount
            or amount == math.huge or amount == -math.huge or amount <= 0 then return nil end
        if not self:Public(school) or type(school) ~= "number" or school ~= school
            or school == math.huge or school == -math.huge or school < 0 then return nil end
        local at = self:Epoch()
        if not at then return nil end
        return {
            amount = amount,
            school = school,
            at = at,
            target = self:Text(env.UnitName, 80, unit or "target") or "",
            zone = self:Text(env.GetZoneText, 80) or "",
            subzone = self:Text(env.GetSubZoneText, 80) or "",
        }
    end

    function A:Date(at, pattern)
        if type(env.date) ~= "function" or type(at) ~= "number" then return nil end
        local ok, value = pcall(env.date, pattern or "%Y-%m-%d %H:%M", at)
        if ok and self:Public(value) and type(value) == "string" then return value end
    end

    function A:OwnedKill(attackerGUID, victimGUID)
        if not self:Public(attackerGUID) or not self:Public(victimGUID)
            or type(attackerGUID) ~= "string" or attackerGUID == ""
            or type(victimGUID) ~= "string" or victimGUID == "" then return false end
        local playerGUID, petGUID = self:GUID("player"), self:GUID("pet")
        return (playerGUID and attackerGUID == playerGUID) or (petGUID and attackerGUID == petGUID) or false
    end

    function A:TargetCrit(unit, action, modifier, amount, school)
        if not self:Public(unit) or not self:Public(action) or not self:Public(modifier)
            or not self:Public(amount) or not self:Public(school) then return false end
        return unit == "target" and action == "WOUND" and modifier == "CRITICAL"
            and type(amount) == "number" and amount == amount and amount ~= math.huge and amount ~= -math.huge
            and amount > 0 and type(school) == "number" and school == school
            and school ~= math.huge and school ~= -math.huge and school >= 0
    end

    function A:ObservedHeal(unit, action, modifier, amount, school)
        if not self:Public(unit) or not self:Public(action) or not self:Public(modifier)
            or not self:Public(amount) or not self:Public(school) then return false end
        if action ~= "HEAL" or modifier ~= "CRITICAL" or (unit ~= "target" and unit ~= "player") then return false end
        if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge or amount <= 0
            or type(school) ~= "number" or school ~= school or school == math.huge or school == -math.huge or school < 0 then return false end
        if unit == "player" and type(env.UnitIsUnit) == "function" then
            local ok, same = pcall(env.UnitIsUnit, "player", "target")
            if ok and self:Public(same) and same == true then return false end
        end
        return true
    end

    function A:PlayPath(path, channel)
        if type(path) ~= "string" or not path:match("^Interface\\")
            or type(env.PlaySoundFile) ~= "function" then return false end
        local ext = path:lower():match("%.([^.\\]+)$")
        if ext ~= "mp3" and ext ~= "ogg" and ext ~= "wav" then return false end
        if channel ~= "Dialog" and channel ~= "SFX" then channel = "Master" end
        local ok, success, handle = pcall(env.PlaySoundFile, path, channel)
        if not ok or not self:Public(success) or success ~= true then return false end
        if self:Public(handle) and type(handle) == "number" then
            self.handles[#self.handles + 1] = handle
            if #self.handles > 5 then table.remove(self.handles, 1) end
        end
        return true
    end

    function A:StopAudio()
        if type(env.StopSound) == "function" then
            for _, handle in ipairs(self.handles) do pcall(env.StopSound, handle) end
        end
        self.handles = {}
    end

    function A:Chat(message)
        if type(message) ~= "string" or message == "" then return false end
        local chat = env.DEFAULT_CHAT_FRAME
        if type(chat) ~= "table" or type(chat.AddMessage) ~= "function" then return false end
        return pcall(chat.AddMessage, chat, message)
    end

    function A:Slash(callback)
        env.SLASH_ZENIALCRIT1 = "/zcrit"
        env.SlashCmdList.ZENIALCRIT = callback
    end

    return A
end
