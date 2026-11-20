local _, NS = ...
local api = NS.Adapter.New(_G)
local app = {api = api, state = NS.Logic.NewState(), initialized = false, killRegistered = false, critRegistered = false,
    spellcastRegistered = false, cooldownRegistered = false, swingRegistered = false, syncPending = false,
    eventState = {unitCombat = "off", partyKill = "off", spellcast = "off", cooldown = "off", swing = "off"},
    situation = "world", procSeen = {}, views = {}, sessionRecords = {},
    procState = NS.Procs.NewState(), watchWeapon = false, watchTotem = false,
    -- spellLog.test exists only while the recording runs (Windfury test, see BeginTest).
    spellLog = {active = false, list = {}}}
NS.App = app
local frame = api:Frame()
if not frame then return end
app.frame = frame

local VERSION = "2.2.1"
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

local SPELL_LOG_MAX, COOLDOWN_STEP, TIMELINE_MAX, TEST_SPELLS = 12, 0.1, 60, 12
local REJECTED_KEY = {no_swing = "noSwing", too_soon = "tooSoon", own_cast = "ownCast", off = "off"}
local STORMSTRIKE = NS.Procs.STORMSTRIKE

local function round3(value) return math.floor(value * 1000 + .5) / 1000 end

local function familyCounters() return {events = 0, procs = 0, noSwing = 0, tooSoon = 0, ownCast = 0, off = 0} end

-- Session-only list of the spells the player casts, so a trigger needs no spell ID typed in. While it runs
-- it is also the Windfury test: it counts swings and proc candidates and writes a report when it ends.
function app:SetSpellCapture(enabled)
    enabled = enabled == true
    if self.spellLog.active and not enabled then self:FinishTest() end
    self.spellLog.active = enabled
    if enabled then self:BeginTest() end
    if self.initialized then self:SyncEvents() end
    for _, view in ipairs(self.views) do view:Refresh() end
end

function app:ClearSpellLog()
    self.spellLog.list = {}
end

-- The test starts when the events can be registered, never in combat (see SyncEvents).
function app:BeginTest()
    local log = self.spellLog
    if log.test or not log.active or api:InCombat() then return false end
    log.test = {startedAt = api:Time() or 0, swings = 0, unreadableCasts = 0, unreadableCooldowns = 0,
        weapon = familyCounters(), totem = familyCounters(), timeline = {}, entries = 0, pending = {}, seenCast = {}}
    self.procState = NS.Procs.NewState()
    return true
end

function app:TimelineAdd(now, event, id)
    local test = self.spellLog.test
    local entry = {t = round3(math.max(0, now - test.startedAt)), e = event, id = id}
    test.entries = test.entries + 1
    test.timeline[(test.entries - 1) % TIMELINE_MAX + 1] = entry
    return entry
end

-- The timeline in the order of the events (the buffer keeps the last 60).
function app:TestTimeline()
    local test, list = self.spellLog.test, {}
    if not test then return list end
    local count = math.min(test.entries, TIMELINE_MAX)
    local first = test.entries > TIMELINE_MAX and test.entries % TIMELINE_MAX or 0
    for index = 0, count - 1 do list[#list + 1] = test.timeline[(first + index) % TIMELINE_MAX + 1] end
    return list
end

local function copyCounters(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function rejectedCount(counters) return counters.noSwing + counters.tooSoon + counters.ownCast end

-- Ends the test: waiting candidates are closed, the report goes to the saved root and one line to the chat.
function app:FinishTest()
    local log = self.spellLog
    local test = log.test
    if not test then return false end
    local now = api:Time() or test.startedAt
    local family, result, reason, lag = NS.Procs.Settle(self.procState)
    while family do
        self:ProcDecision(family, result, reason, lag, nil, now)
        family, result, reason, lag = NS.Procs.Drain(self.procState)
    end
    local spells = {}
    for index = 1, math.min(#log.list, TEST_SPELLS) do
        local entry = log.list[index]
        spells[index] = {id = entry.id, casts = entry.casts, cooldowns = entry.cooldowns}
    end
    local report = {
        at = api:Epoch() or 0, version = VERSION, class = self.playerClass or "",
        seconds = round3(math.max(0, now - test.startedAt)),
        counters = {swings = test.swings, unreadableCasts = test.unreadableCasts,
            unreadableCooldowns = test.unreadableCooldowns,
            weapon = copyCounters(test.weapon), totem = copyCounters(test.totem)},
        spells = spells, timeline = self:TestTimeline(),
    }
    log.test = nil
    if self.root then
        self.root.procTest = NS.Profiles.SanitizeProcTest(report)
        ZenialCritDB = self.root
    end
    local available = NS.Procs.Available(self.playerClass)
    if available.weapon or available.totem then
        api:Chat(string.format(NS.Locale.Text("|cff00e5ff[ZenialCrit]|r Windfury test: %d swings, weapon %d procs, %d rejected, totem %d procs, %d rejected. Type /reload to save it."),
            test.swings, test.weapon.procs, rejectedCount(test.weapon), test.totem.procs, rejectedCount(test.totem)))
    end
    return true
end

local eventNames = {unitCombat = "UNIT_COMBAT", partyKill = "PARTY_KILL", spellcast = "UNIT_SPELLCAST_SUCCEEDED",
    cooldown = "SPELL_UPDATE_COOLDOWN", swing = "PLAYER_SWING"}

-- Registers only the events the current configuration needs. Never in combat: the change is kept
-- and made up for at PLAYER_REGEN_ENABLED (the handlers check the configuration themselves).
function app:SyncEvents()
    if not self.db then return end
    self.playerClass = self.playerClass or api:PlayerClass()
    self.watchWeapon, self.watchTotem = NS.Procs.Watches(self.playerClass, self.db)
    if api:InCombat() then
        self.syncPending = true
        return self.eventState
    end
    self.syncPending = false
    self:BeginTest()
    local needs = NS.Logic.Needs(self.db, self.history and self.history.enabled == true, self.spellLog.active, self.playerClass)
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
    sync("cooldown", "cooldownRegistered", function() return api:Register(frame, "SPELL_UPDATE_COOLDOWN") end)
    sync("swing", "swingRegistered", function() return api:Register(frame, "PLAYER_SWING") end)
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
    elseif kind == "windfury" or kind == "windfuryTotem" then
        return self:FireWindfury(kind == "windfury" and "weapon" or "totem", true)
    end
    return self:Trigger(kind, true, kind, nil, opts)
end

function app:PreviewSound(category, retryID, tier)
    local now = api:Time()
    if not now then return false, "Time could not be read." end
    return self.effects:PlayCategory(category, self.db, now, true, retryID, tier)
end

function app:PreviewSoundRef(id, category, tier)
    self.effects:RetrySound(id)
    local path = NS.Sounds.ResolveRef(self.db, id, api.env, math.random, tier)
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
        local _, tier = NS.Logic.StreakStep(self.state, now, db.streakWindow, db.streakSteps)
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

-- Newest first, one entry per spell, at most SPELL_LOG_MAX spells (the one seen longest ago drops out).
-- kind "cast" counts a cast; kind "cd" a cooldown event, at most once per COOLDOWN_STEP and spell.
function app:LogSpell(spellID, now, kind)
    local list = self.spellLog.list
    local index
    for position = 1, #list do
        if list[position].id == spellID then index = position break end
    end
    local entry = index and list[index]
    if entry and kind == "cd" and entry.cdAt and now >= entry.cdAt and now - entry.cdAt < COOLDOWN_STEP then return end
    if entry then table.remove(list, index) else entry = {id = spellID, casts = 0, cooldowns = 0, at = now} end
    entry.at = now
    if kind == "cast" then
        entry.casts = entry.casts + 1
    else
        entry.cooldowns, entry.cdAt = entry.cooldowns + 1, now
    end
    table.insert(list, 1, entry)
    while #list > SPELL_LOG_MAX do table.remove(list) end
end

-- Weapon and totem families: one decision of Procs becomes a count (test), a timeline entry (test) and,
-- for a proc of a watched family, the effect. entry is the timeline entry of the event itself; a candidate
-- that waited for its swing is found through test.pending.
function app:ProcDecision(family, result, reason, lag, entry, now)
    local test = self.spellLog.test
    if test then
        local counters = test[family]
        if result == "proc" then
            counters.procs = counters.procs + 1
        elseif result == "rejected" and REJECTED_KEY[reason] then
            counters[REJECTED_KEY[reason]] = counters[REJECTED_KEY[reason]] + 1
        end
        if result == "waiting" then
            if entry then entry.r, test.pending[family] = "waiting", entry end
        else
            local target = entry or test.pending[family]
            if target then
                target.r = result == "proc" and "proc" or reason
                target.lag = lag and round3(lag) or nil
            end
            if not entry then test.pending[family] = nil end
        end
    end
    if result ~= "proc" then return false end
    local watched
    if family == "weapon" then watched = self.watchWeapon else watched = self.watchTotem end
    if not watched then return false end
    return self:FireWindfury(family)
end

-- Settled candidates first (they belong to earlier events), then the decision of the current call.
function app:ProcResults(now, entry, family, result, reason, lag)
    local staleFamily, staleResult, staleReason, staleLag = NS.Procs.Drain(self.procState)
    while staleFamily do
        self:ProcDecision(staleFamily, staleResult, staleReason, staleLag, nil, now)
        staleFamily, staleResult, staleReason, staleLag = NS.Procs.Drain(self.procState)
    end
    if family then self:ProcDecision(family, result, reason, lag, entry, now) end
end

function app:HandleCooldown(spellID)
    local test = self.spellLog.test
    if not api:Public(spellID) or type(spellID) ~= "number" then
        if test then test.unreadableCooldowns = test.unreadableCooldowns + 1 end
        return false
    end
    local family = NS.Procs.Family[spellID]
    if not family and not test then return false end
    local now = api:Time()
    if not now then return false end
    if not test then
        local fam, result, reason, lag = NS.Procs.OnCooldown(self.procState, now, spellID, self.watchWeapon, self.watchTotem)
        self:ProcResults(now, nil, fam, result, reason, lag)
        return fam ~= nil
    end
    self:LogSpell(spellID, now, "cd")
    if family then
        local counters = test[family]
        counters.events = counters.events + 1
        local watched
        if family == "weapon" then watched = self.watchWeapon else watched = self.watchTotem end
        if not watched then counters.off = counters.off + 1 end
        -- The test always evaluates both families; without the switch the proc only stays a count.
        local fam, result, reason, lag = NS.Procs.OnCooldown(self.procState, now, spellID, true, true)
        self:ProcResults(now, self:TimelineAdd(now, "cd", spellID), fam, result, reason, lag)
    elseif not test.seenCast[spellID] then
        -- Never cast in this recording: a possible proc.
        self:TimelineAdd(now, "cd", spellID)
    end
    return family ~= nil
end

function app:HandleSwing(_, hand)
    if not api:Public(hand) or type(hand) ~= "number" then return false end
    local test = self.spellLog.test
    if not test and (hand ~= 0 or (not self.watchWeapon and not self.watchTotem)) then return false end
    local now = api:Time()
    if not now then return false end
    if test and hand == 0 then
        test.swings = test.swings + 1
        self:TimelineAdd(now, "swing")
    end
    local family, result, reason, lag = NS.Procs.OnSwing(self.procState, now, hand)
    self:ProcResults(now, nil, family, result, reason, lag)
    return true
end

function app:HandleSpellcast(unit, _, spellID)
    if not api:Public(unit) or unit ~= "player" then return false end
    local test = self.spellLog.test
    if not api:Public(spellID) or type(spellID) ~= "number" then
        if test then test.unreadableCasts = test.unreadableCasts + 1 end
        return false
    end
    local now = api:Time()
    if test then
        self:LogSpell(spellID, now or 0, "cast")
        test.seenCast[spellID] = true
        if spellID == STORMSTRIKE then self:TimelineAdd(now or test.startedAt, "cast", spellID) end
    end
    if now and (test or self.watchWeapon or self.watchTotem) then
        local family, result, reason, lag = NS.Procs.OnCast(self.procState, now, spellID)
        self:ProcResults(now, nil, family, result, reason, lag)
    end
    local trigger = NS.Logic.ProcMatch(self.db, spellID)
    if not trigger then return false end
    if not now then return false end
    local last = self.procSeen[spellID]
    if last and now >= last and now - last < .3 then return false end
    self.procSeen[spellID] = now
    if not self:Allowed("proc") then return false end
    return self:Trigger("proc", false, NS.Logic.SoundCategory(self.db, nil, "proc"), nil, {text = trigger.text})
end

-- Windfury of the weapon or of the totem; the text and the screen flash are their own settings.
function app:FireWindfury(family, preview)
    local db = self.db
    if not preview and not self:Allowed("proc") then return false end
    local text = family == "totem" and db.procWindfuryTotemText or db.procWindfuryWeaponText
    local category = (preview or db.procSound) and "windfury" or nil
    return self:Trigger("proc", preview == true, category, nil, {text = text, flash = db.procWindfuryFlash == true})
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
    self.playerClass = api:PlayerClass()
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
        elseif command == "windfury" then
            self:Preview("windfury")
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
                if command == "settings" then self.ui:Open("overview")
                else self.ui:Toggle() end
            end
        end
    end)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        app:Init()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if app.initialized then app:HandleCooldown(...) end
    elseif event == "PLAYER_SWING" then
        if app.initialized then app:HandleSwing(...) end
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
        -- The class can be unreadable at login; it is read again once the world is there.
        if not app.playerClass and api:PlayerClass() then app:SyncEvents() end
    elseif event == "PLAYER_REGEN_ENABLED" and app.initialized then
        if app.syncPending then
            app:SyncEvents()
            for _, view in ipairs(app.views) do view:Refresh() end
        end
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
api:Register(frame, "PLAYER_REGEN_ENABLED")

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
