-- Kampflog-Zeilen als Typsignal: eigene Farbpalette im Blizzard-Filter "Meine Aktionen" (nur nach
-- Zustimmung, mit Feld-Backup), Status, Zeilen im Kampf aktiv halten, Klassifikation einer
-- COMBAT_LOG_MESSAGE-Zeile allein an ihrer oeffentlichen Farbe. Der Text der Zeile (message) ist
-- geschuetzt und wird hier nie angefasst. Alles ueber env (_G im Spiel, Fake im Test).
local _, NS = ...
local L = {}
NS.LogLines = L

local STORE_VERSION = 1
local TOLERANCE = 2 / 255 + 1e-9
local EPS = 1e-6

-- Blizzard faerbt Spellmisses je Missgrund unter "SPELL_MISSED_<Grund>" (Processor, SPELL_MISSED:
-- event wird immer um den Missgrund erweitert); SWING_/RANGE_MISSED nur bei fullText, das wir aus lassen.
local MISS_REASONS = { "ABSORB", "BLOCK", "DEFLECT", "DODGE", "EVADE", "IMMUNE", "MISS", "PARRY", "REFLECT", "RESIST" }
L.MISS_REASONS = MISS_REASONS

local RAW = {
    SWING_DAMAGE = { 122, 78, 141 }, SPELL_DAMAGE = { 52, 58, 64 }, RANGE_DAMAGE = { 133, 54, 169 },
    SWING_MISSED = { 94, 49, 62 }, SPELL_MISSED = { 151, 147, 57 }, SPELL_EXTRA_ATTACKS = { 101, 63, 148 },
    DAMAGE_SHIELD = { 55, 71, 97 }, PARTY_KILL = { 55, 141, 52 },
}
local RAW_MISS = {
    ABSORB = { 114, 147, 76 }, BLOCK = { 70, 118, 86 }, DEFLECT = { 66, 88, 135 }, DODGE = { 92, 167, 149 },
    EVADE = { 120, 159, 156 }, IMMUNE = { 132, 116, 103 }, MISS = { 154, 113, 58 }, PARRY = { 70, 147, 82 },
    REFLECT = { 127, 78, 165 }, RESIST = { 147, 50, 59 },
}

local function Rgb(t) return { r = t[1] / 255, g = t[2] / 255, b = t[3] / 255 } end

-- Eintraege: key = Blizzards eventColoring-Schluessel, kind = Typ, reason = Missgrund oder nil
local ENTRIES = {}
local PALETTE = {}
do
    for kind, t in pairs(RAW) do
        PALETTE[kind] = Rgb(t)
        ENTRIES[#ENTRIES + 1] = { key = kind, kind = kind, color = PALETTE[kind] }
    end
    for _, reason in ipairs(MISS_REASONS) do
        local key = "SPELL_MISSED_" .. reason
        PALETTE[key] = Rgb(RAW_MISS[reason])
        ENTRIES[#ENTRIES + 1] = { key = key, kind = "SPELL_MISSED", reason = reason, color = PALETTE[key] }
    end
end
L.Palette = PALETTE
L.Entries = ENTRIES

local TARGET_SETTINGS = {
    lineColoring = true, lineColorPriority = 3, fullText = false, timestamp = false,
    unitColoring = false, amountColoring = false, amountHighlighting = true,
}
local SETTING_KEYS = { "lineColoring", "lineColorPriority", "fullText", "timestamp", "unitColoring", "amountColoring", "amountHighlighting" }
local EVENT_ADDITIONS = { "SWING_MISSED", "SPELL_MISSED", "SPELL_EXTRA_ATTACKS", "DAMAGE_SHIELD" }

-- ---------------------------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------------------------

local function NewStore() return { version = STORE_VERSION, settings = {}, colors = {}, events = {} } end

local function SanitizeStore(store)
    if type(store) ~= "table" then return NewStore() end
    if store.version ~= STORE_VERSION then
        for k in pairs(store) do store[k] = nil end
        for k, v in pairs(NewStore()) do store[k] = v end
        return store
    end
    for _, part in ipairs({ "settings", "colors", "events" }) do
        local t = store[part]
        if type(t) ~= "table" then
            store[part] = {}
        else
            for key, item in pairs(t) do
                if type(key) ~= "string" or type(item) ~= "table" or item.applied == nil then t[key] = nil end
            end
        end
    end
    return store
end

local function Copy(v, depth)
    if type(v) ~= "table" then return v end
    depth = depth or 0
    if depth > 6 then return nil end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x, depth + 1) end
    return out
end

local function Same(a, b, depth)
    depth = depth or 0
    if type(a) ~= type(b) or depth > 6 then return false end
    if type(a) == "number" then return math.abs(a - b) <= EPS end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k], depth + 1) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Farbtabelle (r,g,b, ggf. a) gleich wie Soll {r,g,b}; a wird nicht verglichen.
local function SameColor(c, want)
    return type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number"
        and math.abs(c.r - want.r) <= EPS and math.abs(c.g - want.g) <= EPS and math.abs(c.b - want.b) <= EPS
end

function L.New(env, store)
    local self = { Palette = PALETTE }
    store = SanitizeStore(store)
    self.store = store
    local enabled = false
    local lastStatus, lastAt
    local forced = false -- wir haben SetFilteredEventsEnabled(true) gesetzt

    -- Ein Wert ist nutzbar, wenn er nicht geschuetzt ist; Fehler der Pruefung zaehlen als geschuetzt.
    local function Plain(v)
        local f = env.issecretvalue
        if f == nil then return true end
        local ok, secret = pcall(f, v)
        return ok and secret == false
    end

    local function PlainTable(t) return type(t) == "table" and Plain(t) end

    local function Loaded(name)
        local a = env.C_AddOns
        if type(a) ~= "table" or type(a.IsAddOnLoaded) ~= "function" then return false end
        local ok, v = pcall(a.IsAddOnLoaded, name)
        return ok and v == true
    end

    -- Nur der gespeicherte erste Filter "Meine Aktionen" mit Quellen ausschliesslich der eigenen Person.
    local function MyActions()
        local saved, mine, name = env.Blizzard_CombatLog_Filters, env.COMBATLOG_FILTER_MINE, env.QUICKBUTTON_NAME_MY_ACTIONS
        if not (PlainTable(saved) and PlainTable(saved.filters)) then return nil end
        if not (Plain(name) and type(name) == "string" and Plain(mine) and type(mine) == "number") then return nil end
        local f = saved.filters[1]
        if not PlainTable(f) then return nil end
        if not (Plain(f.name) and f.name == name and Plain(f.quickButtonName) and f.quickButtonName == name) then return nil end
        if not (PlainTable(f.filters) and PlainTable(f.settings) and PlainTable(f.colors)
            and PlainTable(f.colors.eventColoring)) then return nil end
        local found = false
        for key, sub in pairs(f.filters) do
            if not (Plain(key) and type(key) == "number" and PlainTable(sub)) then return nil end
            local src, dst = sub.sourceFlags, sub.destFlags
            if (src ~= nil and not PlainTable(src)) or (dst ~= nil and not PlainTable(dst)) then return nil end
            local srcOn, dstOn, foreign, hasMine = false, false, false, false
            for _, pair in ipairs({ { src, true }, { dst, false } }) do
                local flags = pair[1]
                if flags then
                    for flag, on in pairs(flags) do
                        if not (Plain(flag) and Plain(on) and type(flag) == "number") then return nil end
                        if on then
                            if pair[2] then
                                srcOn = true
                                if flag == mine then hasMine = true else foreign = true end
                            else
                                dstOn = true
                            end
                        end
                    end
                end
            end
            local disabled = (src ~= nil and not srcOn) or (dst ~= nil and not dstOn)
            if not disabled then
                if not srcOn or foreign then return nil end
                found = found or hasMine
            end
        end
        if not found then return nil end
        local events = f.filters[1] and f.filters[1].eventList
        if not PlainTable(events) then return nil end
        return f, events
    end

    -- Felder, die wir schreiben: { part = Tabelle, key, want }
    local function Fields(f, events)
        local out = {}
        for _, key in ipairs(SETTING_KEYS) do out[#out + 1] = { part = "settings", t = f.settings, key = key, want = TARGET_SETTINGS[key] } end
        for _, e in ipairs(ENTRIES) do out[#out + 1] = { part = "colors", t = f.colors.eventColoring, key = e.key, want = e.color, color = true } end
        for _, ev in ipairs(EVENT_ADDITIONS) do out[#out + 1] = { part = "events", t = events, key = ev, want = true } end
        return out
    end

    local function Matches(fld, value)
        if fld.color then return SameColor(value, fld.want) end
        return value == fld.want
    end

    local function Restore()
        local f, events = MyActions()
        if not f then return end
        local lookup = {}
        for _, fld in ipairs(Fields(f, events)) do lookup[fld.part .. "\0" .. fld.key] = fld end
        for part, items in pairs(store) do
            if type(items) == "table" and part ~= "version" then
                for key, item in pairs(items) do
                    local fld = lookup[part .. "\0" .. key]
                    if fld then
                        local cur = fld.t[key]
                        local same = Plain(cur) and (fld.color and SameColor(cur, item.applied) or (not fld.color and Same(cur, item.applied)))
                        if same then
                            if item.absent then fld.t[key] = nil else fld.t[key] = Copy(item.value) end
                        end
                    end
                end
            end
        end
        store.settings, store.colors, store.events = {}, {}, {}
    end

    local function Write()
        local f, events = MyActions()
        if not f then return end
        for _, fld in ipairs(Fields(f, events)) do
            local cur = fld.t[fld.key]
            if not Plain(cur) then return end -- unlesbares Feld: nichts anfassen
        end
        for _, fld in ipairs(Fields(f, events)) do
            local cur = fld.t[fld.key]
            if not Matches(fld, cur) then
                local applied = fld.color and Copy({ r = fld.want.r, g = fld.want.g, b = fld.want.b, a = 1 }) or fld.want
                store[fld.part][fld.key] = { value = Copy(cur), absent = cur == nil or nil, applied = Copy(applied) }
                fld.t[fld.key] = applied
            end
        end
    end

    -- PLAYER_LOGOUT: einrichten oder zurueckbauen. Kein ApplyFilterSettings (Zeilen stuerben bis zum Neuladen).
    function self:Prepare(on)
        enabled = on == true
        local ok = pcall(function()
            if on == true then
                if Loaded("HIVECombat") or not Loaded("Blizzard_CombatLog") then return end
                Write()
            else
                Restore()
            end
        end)
        lastStatus = nil
        return ok
    end

    function self:SetEnabled(on)
        enabled = on == true
        lastStatus = nil
    end

    local function ComputeStatus()
        if not enabled then return "off" end
        if Loaded("HIVECombat") then return "foreign" end
        if not Loaded("Blizzard_CombatLog") then return "noaddon" end
        local filters = env.Blizzard_CombatLog_Filters
        local cur = env.Blizzard_CombatLog_CurrentSettings
        if not (PlainTable(filters) and PlainTable(filters.filters) and PlainTable(cur)) then return "noaddon" end
        local f, events = MyActions()
        if not f or cur ~= f then return "filter" end
        -- Zeitstempel im Kampflog setzen Ziffern vor jede Zeile (settings.timestamp des Filters).
        local timestamp = f.settings.timestamp
        if Plain(timestamp) and timestamp == true then return "timestamps" end
        -- Live-Werte (die geladenen) tragen Palette und Einstellungen?
        for _, fld in ipairs(Fields(f, events)) do
            if not (Plain(fld.t[fld.key]) and Matches(fld, fld.t[fld.key])) then return "reload" end
        end
        return "ok"
    end

    function self:Status()
        local ok, s = pcall(ComputeStatus)
        lastStatus = ok and s or "filter"
        lastAt = type(env.GetTime) == "function" and select(2, pcall(env.GetTime)) or nil
        return lastStatus
    end

    local function CachedStatus()
        if lastStatus and lastAt and type(env.GetTime) == "function" then
            local ok, now = pcall(env.GetTime)
            if ok and type(now) == "number" and now - lastAt < 1 and now >= lastAt then return lastStatus end
        end
        return self:Status()
    end

    function self:KeepLines(inCombat)
        local C = env.C_CombatLog
        if type(C) ~= "table" then return end
        if inCombat then
            if forced or self:Status() ~= "ok" then return end
            local okA, was = pcall(C.AreFilteredEventsEnabled)
            if okA and was == true then return end
            if pcall(C.SetFilteredEventsEnabled, true) then forced = true end
        elseif forced then
            forced = false
            local w = env.COMBATLOG
            local shown = false
            if w ~= nil then
                local ok, v = pcall(function() return w:IsShown() end)
                shown = ok and v == true
            end
            pcall(C.SetFilteredEventsEnabled, shown)
        end
    end

    local function NewestOrder()
        local e = env.Enum
        local o = type(e) == "table" and type(e.CombatLogMessageOrder) == "table" and e.CombatLogMessageOrder.Newest
        if type(o) == "number" then return o end
        return 0 -- Dokumentation: Newest = 0, Oldest = 1
    end

    local function Near(v, c, highlight)
        if highlight then c = math.min(1, c * 1.5) end
        return math.abs(v - c) <= TOLERANCE
    end

    -- Typ der Zeile an ihrer Farbe. Zweiter Wert: Missgrund bei SPELL_MISSED.
    function self:Classify(r, g, b, order)
        if not (Plain(r) and Plain(g) and Plain(b) and Plain(order)) then return nil end
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" or type(order) ~= "number" then return nil end
        if order ~= NewestOrder() then return nil end
        if CachedStatus() ~= "ok" then return nil end
        for _, e in ipairs(ENTRIES) do
            local c = e.color
            -- PARTY_KILL darf von Blizzard um 1.5 hervorgehoben sein
            if (Near(r, c.r) and Near(g, c.g) and Near(b, c.b))
                or (e.kind == "PARTY_KILL" and Near(r, c.r, true) and Near(g, c.g, true) and Near(b, c.b, true)) then
                return e.kind, e.reason
            end
        end
        return nil
    end

    return self
end

return L
