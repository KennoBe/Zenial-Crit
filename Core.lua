local _, NS = ...
local api = NS.Adapter.New(_G)
local app = {api = api, state = NS.Logic.NewState(), initialized = false, killRegistered = false, critRegistered = false, views = {}, sessionRecords = {}}
NS.App = app
local frame = api:Frame()
if not frame then return end
app.frame = frame

local function savedConfig()
    local saved = ZenialCritDB
    if type(saved) ~= "table" then saved = ZenialComixDB end
    return NS.Logic.Sanitize(saved)
end

api:ApplyDamageFont(savedConfig().critFont)

function app:Changed()
    self.db = NS.Logic.Sanitize(self.db)
    ZenialCritDB = self.db
    api:ApplyDamageFont(self.db.critFont)
    api:TrackNameplates(self.db.displayMode == "nameplate")
    for _, view in ipairs(self.views) do view:Refresh() end
end

function app:TextsChanged(key, value, sourceView)
    local kind = key == "killTexts" and "kill" or "crit"
    self.db[key] = NS.Logic.SanitizeTexts(value, kind)
    ZenialCritDB = self.db
    for _, view in ipairs(self.views) do view:Refresh() end
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
    if app.effects:Count() == 0 then frame:SetScript("OnUpdate", nil) end
end

function app:Trigger(kind, preview, soundCategory, victimGUID)
    api:Diagnostic("trigger", kind, preview == true, self.db.displayMode, self.db.critGraphics,
        self.db.killGraphics, self.effects:Count(), soundCategory)
    local now = api:Time()
    if not now then return false end
    self.effects:Update(now)
    if not NS.Logic.Allow(self.state, self.db, kind, now, self.effects:Count(), preview == true) then return false end
    if preview and not soundCategory then soundCategory = kind end
    local anchor
    if self.db.displayMode == "nameplate" and kind ~= "heal" then
        local ok, result = pcall(api.NameplateContext, api, victimGUID)
        api.traceNameplate = false
        api:Diagnostic("anchor_call", ok, ok and result ~= nil or false, not ok and result or nil)
        if ok then anchor = result end
    end
    local ok, graphic, played, reason = pcall(self.effects.Show, self.effects, kind, soundCategory, self.db, now, preview == true, anchor)
    api:Diagnostic("show_result", kind, ok, graphic, played, reason, self.effects:Count(), self.effects.graphicsPaused[kind])
    if not ok then self.effects:Clear(); return false end
    if self.effects:Count() > 0 then frame:SetScript("OnUpdate", onUpdate) end
    return true
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
    self:EmitChat("kill")
    return self:Trigger("kill", false, self.db.killSound and "kill" or nil, victimGUID)
end

function app:HandleObserved(kind, unit, amount, school)
    local key = self:EnsureCharacter()
    local classification = "normal"
    if key then
        local isRecord, previous = NS.History.Compare(
            self.history, key, amount, school, self.history.enabled == true, self.sessionRecords, kind
        )
        classification = isRecord and "record" or NS.Logic.ClassifyCrit(amount, previous, self.db, kind)
    end
    local snapshot = api:CritSnapshot(amount, school, unit)
    if snapshot and self.history.enabled then self:RecordObserved(amount, school, snapshot, kind) end
    local chatCategory = NS.Logic.ChatCategory(classification, kind)
    self:EmitChat(chatCategory, amount, school, snapshot and snapshot.target)
    return self:Trigger(kind, false, NS.Logic.SoundCategory(self.db, classification, kind))
end

function app:HandleCombat(unit, action, modifier, amount, school)
    if api:TargetCrit(unit, action, modifier, amount, school) then
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
    self.db = NS.Logic.Sanitize(saved)
    ZenialCritDB = self.db
    api:ApplyDamageFont(self.db.critFont)
    ZenialComixDB = nil
    self.history = NS.History.Sanitize(ZenialCritHistoryDB)
    ZenialCritHistoryDB = self.history
    self:EnsureCharacter()
    self.effects = NS.Effects.New(api)
    api:TrackNameplates(self.db.displayMode == "nameplate")
    self.killRegistered = api:Register(frame, "PARTY_KILL")
    self.critRegistered, self.critRegistration = api:RegisterUnit(frame, "UNIT_COMBAT", "target", "player")
    NS.Setup.Initialize(self,fresh)
    NS.Setup.Schedule()
    api:Slash(function(command)
        command = string.lower(command or ""):match("^%s*(.-)%s*$")
        if command == "preview" or command == "vorschau" then
            self:Trigger("crit", true, "crit")
        elseif command == "kill" or command == "last-hit" then
            self:Trigger("kill", true, "kill")
        elseif command == "heal" then
            self:PreviewSound("heal")
        elseif command == "config" then
            NS.Setup.Open()
        else
            if NS.Setup.wizard.frame then NS.Setup.wizard.frame:Hide() end
            if not self.ui then
                local ok, result = pcall(NS.UI.New, self)
                if ok then self.ui = result end
            end
            if self.ui then
                if command == "settings" then self.ui:SetPage("settings"); self.ui:Refresh(); self.ui.frame:Show()
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

_G.ZenialAddonPanels = _G.ZenialAddonPanels or {}
_G.ZenialAddonPanels.ZenialCrit = {
    apiVersion = 1,
    Diagnostics = function()
        return {version = "1.9.0", initialized = app.initialized,
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
