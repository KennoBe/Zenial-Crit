local _, NS = ...
local api = NS.Adapter.New(_G)
local app = {api = api, state = NS.Logic.NewState(), initialized = false, killRegistered = false, critRegistered = false,
    spellcastRegistered = false, eventState = {unitCombat = "off", partyKill = "off", spellcast = "off"},
    situation = "world", procSeen = {}, views = {}, sessionRecords = {}}
NS.App = app
local frame = api:Frame()
if not frame then return end
app.frame = frame

local VERSION = "2.0.0"
app.version = VERSION

-- Config used before login (damage font): the profile of this character, else root.last, else "Standard",
-- else a flat legacy table. The identity can be missing this early; nothing is stored here.
local function savedConfig()
    local saved = ZenialCritDB
    if type(saved) ~= "table" then saved = ZenialComixDB end
    if type(saved) == "table" and type(saved.profiles) == "table" then
        local profile
        local identified, key = pcall(api.CharacterIdentity, api)
        if identified and type(key) == "string" and key ~= "" then
            local resolved, _, config = pcall(NS.Profiles.Resolve, saved, key)
            if resolved and type(config) == "table" then profile = config end
        end
        if not profile then profile = type(saved.last) == "string" and saved.profiles[saved.last] or nil end
        return NS.Logic.Sanitize(profile or saved.profiles[NS.Profiles.DefaultName])
    end
    return NS.Logic.Sanitize(saved)
end

api:ApplyDamageFont(savedConfig().critFont)

-- Plates are followed only while a crit or kill text can actually appear over one.
function app:WantsNameplateTracking()
    local db = self.db
    return db.displayMode == "nameplate" and db.enabled ~= false
        and (db.critGraphics == true or db.killGraphics == true)
end

-- ZenialCritDB is the profile root; app.db is the flat config of the active profile.
function app:Changed()
    self.db = NS.Logic.Sanitize(self.db)
    if self.root then
        self.root.profiles[self.profile] = self.db
        ZenialCritDB = self.root
    end
    api:ApplyDamageFont(self.db.critFont)
    api:TrackNameplates(self:WantsNameplateTracking())
    if self.initialized then self:SyncEvents() end
    for _, view in ipairs(self.views) do view:Refresh() end
end

local textKinds = {killTexts = "kill", healTexts = "heal", streakTexts = "streak"}
function app:TextsChanged(key, value, sourceView)
    self.db[key] = NS.Logic.SanitizeTexts(value, textKinds[key] or "crit")
    if self.root then
        self.root.profiles[self.profile] = self.db
        ZenialCritDB = self.root
    end
    for _, view in ipairs(self.views) do view:Refresh() end
end

function app:SetProfile(name)
    if not self.root or type(name) ~= "string" or not self.root.profiles[name] then return false end
    self.root.profiles[self.profile] = self.db
    local key = self:EnsureCharacter()
    local assignError
    if key then
        local assigned, err = NS.Profiles.Assign(self.root, key, name)
        if not assigned then assignError = err end
    end
    self.root.last = name
    self.profile, self.db = name, self.root.profiles[name]
    self:Changed()
    -- A failed assignment does not stop the profile from being active for this session.
    return true, assignError
end

function app:CreateProfile(name)
    if not self.root then return nil, "Profiles are not ready." end
    self.root.profiles[self.profile] = self.db
    local created, err = NS.Profiles.Create(self.root, name, self.profile)
    if not created then return nil, err end
    self:Changed()
    return created
end

function app:DeleteProfile(name)
    if not self.root then return nil, "Profiles are not ready." end
    local ok, result = NS.Profiles.Delete(self.root, name)
    if not ok then return nil, result end
    if self.profile == name or not self.root.profiles[self.profile] then
        self.profile, self.db = NS.Profiles.Resolve(self.root, self:EnsureCharacter())
    end
    self:Changed()
    return true
end

function app:ApplyPreset(name)
    if not NS.Logic.ApplyPreset(self.db, name) then return false end
    self:Changed()
    return true
end

function app:ResetKeys(keys)
    NS.Logic.ResetKeys(self.db, keys)
    self:Changed()
end

function app:EnsureCharacter()
    if self.characterKey then return self.characterKey end
    self.characterKey, self.characterName = api:CharacterIdentity()
    return self.characterKey
end

function app:HistoryChanged()
    ZenialCritHistoryDB = self.history
    for _, view in ipairs(self.views) do
        if view.RefreshHistory then view:RefreshHistory() end
    end
end

function app:SetHistoryEnabled(enabled)
    NS.History.SetEnabled(self.history, enabled)
    self:HistoryChanged()
    if self.initialized then self:SyncEvents() end
end

local eventNames = {unitCombat = "UNIT_COMBAT", partyKill = "PARTY_KILL", spellcast = "UNIT_SPELLCAST_SUCCEEDED"}

-- Registers only the events the current configuration needs.
function app:SyncEvents()
    if not self.db then return end
    local needs = NS.Logic.Needs(self.db, self.history and self.history.enabled == true)
    local function sync(name, flag, register)
        if needs[name] then
            if not self[flag] then self[flag] = register() end
            self.eventState[name] = self[flag] and "on" or "failed"
        else
            if self[flag] then api:Unregister(frame, eventNames[name]) end
            self[flag] = false
            self.eventState[name] = "off"
        end
    end
    sync("unitCombat", "critRegistered", function()
        local ok, mode = api:RegisterUnit(frame, "UNIT_COMBAT", "target", "player")
        self.critRegistration = ok and mode or nil
        return ok
    end)
    sync("partyKill", "killRegistered", function() return api:Register(frame, "PARTY_KILL") end)
    sync("spellcast", "spellcastRegistered", function()
        return (api:RegisterUnit(frame, "UNIT_SPELLCAST_SUCCEEDED", "player"))
    end)
    return self.eventState
end

function app:UpdateSituation()
    self.situation = NS.Logic.Situation(api:InstanceType())
end

-- Master switch and situation filter for real (non-preview) output.
function app:Allowed(kind, classification)
    return self.db.enabled ~= false
        and NS.Logic.SituationAllows(self.db, self.situation or "world", kind, classification)
end

function app:ClearHistory()
    local key = self:EnsureCharacter()
    if not key then return false end
    local changed = NS.History.Clear(self.history, key)
    NS.History.ResetSession(self.sessionRecords, key)
    if changed then self:HistoryChanged() end
    return changed
end

function app:RecordObserved(amount, school, snapshot, kind)
    if not self.history or self.history.enabled ~= true then return false end
    local key = self:EnsureCharacter()
    if not key then return false end
    snapshot = snapshot or api:CritSnapshot(amount, school, kind == "heal" and "player" or "target")
    if not snapshot then return false end
    local recorded = NS.History.Record(self.history, key, self.characterName, snapshot, kind)
    if recorded then self:HistoryChanged() end
    return recorded
end

-- One static handler for all effects; it detaches itself when none remain.
local function onUpdate()
    local time = api:Time()
    if not time then app.effects:Clear(); frame:SetScript("OnUpdate", nil); return end
    app.effects:Update(time)
    if not app.effects:Busy() then frame:SetScript("OnUpdate", nil) end
end

function app:Trigger(kind, preview, soundCategory, victimGUID, opts)
    api:Diagnostic("trigger", kind, preview == true, self.db.displayMode, self.db.critGraphics,
        self.db.killGraphics, self.effects:Count(), soundCategory)
    if not preview and self.db.enabled == false then return false end
    local now = api:Time()
    if not now then return false end
    self.effects:Update(now)
    if not NS.Logic.Allow(self.state, self.db, kind, now, self.effects:Count(), preview == true) then return false end
    if preview and not soundCategory then soundCategory = kind end
    local anchor, note
    -- Only crit and kill follow the nameplate; heal, streak and proc stay at the fixed position.
    if self.db.displayMode == "nameplate" and (kind == "crit" or kind == "kill") then
        local ok, result = pcall(api.NameplateContext, api, victimGUID)
        api.traceNameplate = false
        api:Diagnostic("anchor_call", ok, ok and result ~= nil or false, not ok and result or nil)
        if ok then anchor = result end
        if preview and not anchor then
            local copy = {}
            for key, value in pairs(opts or {}) do copy[key] = value end
            copy.fixed, opts, note = true, copy, "no_target"
        end
    end
    local ok, graphic, played, reason = pcall(self.effects.Show, self.effects, kind, soundCategory, self.db, now, preview == true, anchor, opts)
    api:Diagnostic("show_result", kind, ok, graphic, played, reason, self.effects:Count(), self.effects.graphicsPaused[kind])
    if not ok then self.effects:Clear(); return false end
    if self.effects:Busy() then frame:SetScript("OnUpdate", onUpdate) end
    return true, note, graphic == true, played == true
end

-- Preview through the normal path; ignores switches, situation, threshold and sound pause.
function app:Preview(kind, tier)
    if not self.effects then return false end
    local opts
    if kind == "streak" then
        tier = type(tier) == "number" and tier >= 1 and math.floor(tier) or 1
        opts = {text = NS.Logic.StreakText(self.db, tier), tier = tier}
    elseif kind == "proc" then
        local text = "PROC!"
        for _, item in ipairs(self.db.procTriggers or {}) do
            if item.enabled ~= false then text = item.text; break end
        end
        opts = {text = text}
    end
    return self:Trigger(kind, true, kind, nil, opts)
end

function app:PreviewSound(category, retryID)
    local now = api:Time()
    if not now then return false, "Time could not be read." end
    return self.effects:PlayCategory(category, self.db, now, true, retryID)
end

function app:PreviewSoundRef(id, category)
    self.effects:RetrySound(id)
    local path = NS.Sounds.ResolveRef(self.db, id, api.env, math.random)
    if not path then return false, "Sound source is currently unavailable." end
    api:StopAudio()
    if api:PlayPath(path, NS.Logic.SoundChannel(self.db, category or "crit")) then return true end
    self.effects.failedSounds[id] = true
    return false, "File could not be played. Check path and WoW restart."
end


local schoolNames = {{1,"Physical"},{2,"Holy"},{4,"Fire"},{8,"Nature"},{16,"Frost"},{32,"Shadow"},{64,"Arcane"}}
local function schoolLabel(value)
    local mask, names = type(value) == "number" and math.floor(value) or 0, {}
    for _, school in ipairs(schoolNames) do
        if math.floor(mask / school[1]) % 2 == 1 then names[#names + 1] = NS.Locale.Text(school[2]) end
    end
    return #names > 0 and table.concat(names, "/") or NS.Locale.Text("Unknown")
end

local function formatAmount(value)
    local result = tostring(math.floor(value or 0))
    local separator = NS.Locale.isGerman and "." or ","
    while true do
        local changed; result, changed = result:gsub("^(%-?%d+)(%d%d%d)", "%1" .. separator .. "%2")
        if changed == 0 then break end
    end
    return result
end

function app:EmitChat(category, amount, school, target)
    if not NS.Logic.ChatAllowed(self.db, category) then return false end
    if category == "kill" then return api:Chat(NS.Locale.Text("|cff00e5ff[ZenialCrit]|r Own kill detected.")) end
    local templates = {
        crit="|cff00e5ff[ZenialCrit]|r Crit: |cffffcc45%s|r %s on %s",
        record="|cff00e5ff[ZenialCrit]|r New crit record: |cffffcc45%s|r %s on %s",
        low="|cff00e5ff[ZenialCrit]|r Weak crit: |cffff9a70%s|r %s on %s",
        heal="|cff00e5ff[ZenialCrit]|r Heal crit: |cff72e58a%s|r %s on %s",
        healRecord="|cff00e5ff[ZenialCrit]|r New heal record: |cff72e58a%s|r %s on %s",
        healLow="|cff00e5ff[ZenialCrit]|r Weak heal crit: |cff9ad6a7%s|r %s on %s",
    }
    local template = templates[category]
    if not template then return false end
    target = type(target) == "string" and target ~= "" and target or NS.Locale.Text("Unknown")
    local message = string.format(NS.Locale.Text(template), formatAmount(amount), schoolLabel(school), target)
    return api:Chat(message)
end

function app:HandleKill(attackerGUID, victimGUID)
    local now = api:Time()
    if not now or not api:OwnedKill(attackerGUID, victimGUID) then return false end
    if not NS.Logic.AllowKill(self.state, victimGUID, now) then return false end
    local db = self.db
    if not self:Allowed("kill") then return false end
    self:EmitChat("kill")
    local killSound, killOpts = db.killSound and "kill" or nil, nil
    if (db.streakGraphics or db.streakSound) and (db.streakTargets ~= "players" or api:IsPlayerGUID(victimGUID)) then
        local _, tier = NS.Logic.StreakStep(self.state, now, db.streakWindow)
        if tier >= 1 then
            local streakSound = NS.Logic.SoundCategory(db, nil, "streak")
            local shown, _, graphic, played = self:Trigger("streak", false, streakSound, nil,
                {text = NS.Logic.StreakText(db, tier), tier = tier})
            if shown then
                -- The streak replaces only what it really showed or played: its text replaces the kill text,
                -- its sound the kill sound. A streak that drew or played nothing hides nothing.
                if db.streakHideKill and graphic then killOpts = {noGraphic = true} end
                if played then killSound = nil end
            end
        end
    end
    return self:Trigger("kill", false, killSound, victimGUID, killOpts)
end

function app:HandleSpellcast(unit, _, spellID)
    if not api:Public(unit) or unit ~= "player" then return false end
    if not api:Public(spellID) or type(spellID) ~= "number" then return false end
    local trigger = NS.Logic.ProcMatch(self.db, spellID)
    if not trigger then return false end
    local now = api:Time()
    if not now then return false end
    local last = self.procSeen[spellID]
    if last and now >= last and now - last < .3 then return false end
    self.procSeen[spellID] = now
    if not self:Allowed("proc") then return false end
    return self:Trigger("proc", false, NS.Logic.SoundCategory(self.db, nil, "proc"), nil, {text = trigger.text})
end

function app:HandleObserved(kind, unit, amount, school)
    local key = self:EnsureCharacter()
    local classification, previous = "normal", nil
    if key then
        local isRecord
        isRecord, previous = NS.History.Compare(
            self.history, key, amount, school, self.history.enabled == true, self.sessionRecords, kind
        )
        classification = isRecord and "record" or NS.Logic.ClassifyCrit(amount, previous, self.db, kind)
    end
    local chatCategory = NS.Logic.ChatCategory(classification, kind)
    -- The snapshot reads names from the client: only when it is recorded or written to the chat.
    local recording = self.history.enabled == true
    local snapshot
    if recording or NS.Logic.ChatAllowed(self.db, chatCategory) then
        snapshot = api:CritSnapshot(amount, school, unit)
    end
    if snapshot and recording then self:RecordObserved(amount, school, snapshot, kind) end
    if not self:Allowed(kind, classification) then return false end
    self:EmitChat(chatCategory, amount, school, snapshot and snapshot.target)
    local category, opts = NS.Logic.SoundCategory(self.db, classification, kind), nil
    if not NS.Logic.PassesThreshold(self.db, kind, amount, previous) then
        -- Below the threshold: no graphic and no normal sound; record and weak sounds stay.
        opts = {noGraphic = true}
        if category == kind then category = nil end
        if not category then return false end
    end
    return self:Trigger(kind, false, category, nil, opts)
end

function app:HandleCombat(unit, action, modifier, amount, school)
    if api:TargetCrit(unit, action, modifier, amount, school) then
        if not api:Public(amount) or not api:Public(school) then
            -- Generic output needs only the public crit flag. Never compare,
            -- record or format protected numeric payloads, including chat text.
            if not self:Allowed("crit", "unknown") then return false end
            return self:Trigger("crit", false, NS.Logic.SoundCategory(self.db, "unknown", "crit"))
        end
        return self:HandleObserved("crit", unit, amount, school)
    end
    if api:ObservedHeal(unit, action, modifier, amount, school) then
        return self:HandleObserved("heal", unit, amount, school)
    end
    return false
end

function app:AddOrUpdateCustomSound(name, file, editID)
    local id, err = NS.Sounds.AddOrUpdate(self.db, name, file, editID)
    if not id then return nil, err end
    self:Changed()
    return id
end

function app:RemoveCustomSound(id)
    local changed = NS.Sounds.Remove(self.db, id)
    if changed then self:Changed() end
    return changed
end

function app:Init()
    if self.initialized then return end
    self.initialized = true
    local saved = ZenialCritDB
    if type(saved) ~= "table" then saved = ZenialComixDB end
    local fresh = type(saved) ~= "table" or next(saved) == nil
    self.root = NS.Profiles.SanitizeRoot(saved)
    ZenialCritDB = self.root
    self:EnsureCharacter()
    self.profile, self.db = NS.Profiles.Resolve(self.root, self.characterKey)
    self.root.last = self.profile
    self:UpdateSituation()
    api:ApplyDamageFont(self.db.critFont)
    ZenialComixDB = nil
    self.history = NS.History.Sanitize(ZenialCritHistoryDB)
    ZenialCritHistoryDB = self.history
    self.effects = NS.Effects.New(api)
    api:TrackNameplates(self:WantsNameplateTracking())
    self:SyncEvents()
    NS.Setup.Initialize(self,fresh)
    NS.Setup.Schedule()
    api:Slash(function(command)
        command = string.lower(command or ""):match("^%s*(.-)%s*$")
        local streakTier = command:match("^streak%s*(%d*)$")
        if command == "preview" or command == "vorschau" then
            self:Preview("crit")
        elseif command == "kill" or command == "last-hit" then
            self:Preview("kill")
        elseif command == "heal" then
            self:Preview("heal")
        elseif streakTier then
            self:Preview("streak", tonumber(streakTier))
        elseif command == "proc" then
            self:Preview("proc")
        elseif command == "config" then
            NS.Setup.Open()
        else
            if NS.Setup.wizard.frame then NS.Setup.wizard.frame:Hide() end
            if not self.ui then
                local ok, result = pcall(NS.UI.New, self)
                if ok then self.ui = result end
            end
            if self.ui then
                -- /zcrit toggles the window on the page shown last; /zcrit settings opens the overview.
                if command == "settings" then self.ui:SetPage("overview"); self.ui.frame:Show()
                else self.ui:Toggle() end
            end
        end
    end)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        app:Init()
    elseif event == "PARTY_KILL" and app.initialized then
        app:HandleKill(...)
    elseif event == "UNIT_COMBAT" and app.initialized then
        -- Readable token first; the global fallback also delivers other units.
        local unit = ...
        if api:Public(unit) and (unit == "target" or unit == "player") then app:HandleCombat(...) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and app.initialized then
        app:HandleSpellcast(...)
    elseif (event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA") and app.initialized then
        app:UpdateSituation()
    elseif event == "ADDON_LOADED" then
        local name = ...
        if name == "ZenialCrit" then api:ApplyDamageFont(savedConfig().critFont) end
        if app.initialized then
            for _, view in ipairs(app.views) do if view.RefreshSounds then view:RefreshSounds() end end
        end
    end
end)
api:Register(frame, "PLAYER_LOGIN")
api:Register(frame, "ADDON_LOADED")
api:Register(frame, "PLAYER_ENTERING_WORLD")
api:Register(frame, "ZONE_CHANGED_NEW_AREA")

_G.ZenialAddonPanels = _G.ZenialAddonPanels or {}
_G.ZenialAddonPanels.ZenialCrit = {
    apiVersion = 1,
    Diagnostics = function()
        return {version = VERSION, initialized = app.initialized,
            killRegistered = app.killRegistered, critRegistered = app.critRegistered,
            displayMode = app.db and app.db.displayMode,
            critGraphics = app.db and app.db.critGraphics, killGraphics = app.db and app.db.killGraphics,
            activeGraphics = app.effects and app.effects:Count(),
            nameplateAPI = type(_G.C_NamePlate) == "table" and type(_G.C_NamePlate.GetNamePlateForUnit)}
    end,
    CreatePanel = function(parent)
        app:Init()
        local view = NS.UI.New(app, parent, true)
        if not view then return nil end
        return view.frame, function() view:Refresh() end
    end,
}
