local _, NS = ...
-- Built-in procs (Windfury of the weapon and of the totem). Pure logic, no WoW API, no timer.
-- The client delivers no UNIT_SPELLCAST_SUCCEEDED for the Windfury proc. The candidate is
-- SPELL_UPDATE_COOLDOWN with a readable spell ID, accepted only when it is tied in time to an own
-- main-hand swing or to Stormstrike. Everything is driven by the events the caller passes in.
local P = {}
NS.Procs = P

P.WEAPON_IDS = {439440, 16361}
P.TOTEM_IDS = {8516, 10608, 10610}
P.STORMSTRIKE = 17364
P.SWING_LAG = 0.20   -- weapon: the proc event follows the swing (or Stormstrike) at most this long
P.TOTEM_LAG = 0.25
P.SWING_LEAD = 0.05  -- the event may come this much BEFORE the swing: it waits for the swing
P.WEAPON_GAP = 1.4   -- shortest distance between two accepted weapon procs
P.TOTEM_GAP = 0.6
P.CAST_GUARD = 0.5   -- an own cast of the same totem this short before rules the proc out

local SWING_LAG, TOTEM_LAG, SWING_LEAD = P.SWING_LAG, P.TOTEM_LAG, P.SWING_LEAD
local WEAPON_GAP, TOTEM_GAP, CAST_GUARD = P.WEAPON_GAP, P.TOTEM_GAP, P.CAST_GUARD
local STORMSTRIKE = P.STORMSTRIKE

-- spell ID -> family; the only table the event handler touches for a foreign ID.
local family = {}
for _, id in ipairs(P.WEAPON_IDS) do family[id] = "weapon" end
for _, id in ipairs(P.TOTEM_IDS) do family[id] = "totem" end
P.Family = family

local totemSet = {}
for _, id in ipairs(P.TOTEM_IDS) do totemSet[id] = true end

local KNOWN = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK",
    "MONK", "DRUID", "DEMONHUNTER"}
local NO_TOTEM = {MAGE = true, PRIEST = true, WARLOCK = true}
P.Classes = {weapon = {SHAMAN = true}, totem = {}}
for _, class in ipairs(KNOWN) do
    if not NO_TOTEM[class] then P.Classes.totem[class] = true end
end
local knownClass = {}
for _, class in ipairs(KNOWN) do knownClass[class] = true end

function P.Available(class)
    if type(class) ~= "string" or not knownClass[class] then return {weapon = false, totem = false} end
    return {weapon = P.Classes.weapon[class] == true, totem = P.Classes.totem[class] == true}
end

-- Which families the configuration watches: available, switched on, any output, addon on.
function P.Watches(class, config)
    if type(config) ~= "table" or config.enabled == false then return false, false end
    if config.procGraphics ~= true and config.procSound ~= true then return false, false end
    local available = P.Available(class)
    return available.weapon and config.procWindfuryWeapon == true,
        available.totem and config.procWindfuryTotem == true
end

function P.NewState()
    return {
        anchorAt = nil,                  -- time of the last own main-hand swing or Stormstrike
        lastProc = {},                   -- family -> time of the last accepted proc
        castAt = {[8516] = -math.huge, [10608] = -math.huge, [10610] = -math.huge},
        pending = {},                    -- family -> time of a candidate that waits for its swing
        slots = {weapon = {}, totem = {}}, -- settled candidates not returned yet (see Drain)
    }
end

local FAMILIES = {"weapon", "totem"}

local function setSlot(state, fam, result, reason, lag)
    local slot = state.slots[fam]
    slot.set, slot.result, slot.reason, slot.lag = true, result, reason, lag
end

-- Settles the waiting candidates against an anchor that arrives at `now` (nil: no anchor, a stale
-- candidate is rejected). Returns the first decision; further ones wait in the slots (Drain).
local function settle(state, now, anchored)
    local first
    for _, fam in ipairs(FAMILIES) do
        local at = state.pending[fam]
        if at then
            state.pending[fam] = nil
            local result, reason, lag
            if anchored and now - at <= SWING_LEAD + 1e-9 then
                state.lastProc[fam] = at
                result, lag = "proc", at - now
            else
                result, reason = "rejected", "no_swing"
            end
            if first == nil then
                first = {fam, result, reason, lag}
            else
                setSlot(state, fam, result, reason, lag)
            end
        end
    end
    return first
end

local function settleOut(state, now, anchored)
    local decision = settle(state, now, anchored)
    if decision then return decision[1], decision[2], decision[3], decision[4] end
end

-- A settled candidate that could not be returned directly. Call after every entry point until nil.
function P.Drain(state)
    for _, fam in ipairs(FAMILIES) do
        local slot = state.slots[fam]
        if slot.set then
            slot.set = false
            return fam, slot.result, slot.reason, slot.lag
        end
    end
end

-- Closes every waiting candidate as "no swing" (end of a test).
function P.Settle(state)
    local first = settle(state, 0, false)
    if first then return first[1], first[2], first[3], first[4] end
end

-- hand 0 = main hand. Anything else (ranged 2, off hand) is no anchor.
function P.OnSwing(state, now, hand)
    if hand ~= 0 then return nil end
    state.anchorAt = now
    return settleOut(state, now, true)
end

-- Stormstrike is an anchor like a swing; an own totem cast is remembered per ID.
function P.OnCast(state, now, spellID)
    if spellID == STORMSTRIKE then
        state.anchorAt = now
        return settleOut(state, now, true)
    elseif totemSet[spellID] then
        state.castAt[spellID] = now
    end
    return nil
end

function P.OnCooldown(state, now, spellID, watchWeapon, watchTotem)
    local fam = family[spellID]
    if not fam then return nil end
    local watched = fam == "weapon" and watchWeapon or fam == "totem" and watchTotem
    if not watched then return fam, "rejected", "off", nil end
    -- A candidate that waited too long is closed first (returned by Drain), then this event counts.
    local pendingAt = state.pending[fam]
    if pendingAt then
        if now - pendingAt <= SWING_LEAD + 1e-9 then
            return fam, "rejected", "too_soon", nil -- the same proc, a second ID
        end
        state.pending[fam] = nil
        setSlot(state, fam, "rejected", "no_swing", nil)
    end
    if fam == "totem" then
        local cast = state.castAt[spellID]
        if now >= cast and now - cast < CAST_GUARD then return fam, "rejected", "own_cast", nil end
    end
    local last = state.lastProc[fam]
    local gap = fam == "weapon" and WEAPON_GAP or TOTEM_GAP
    if last and now >= last and now - last < gap then return fam, "rejected", "too_soon", nil end
    local anchor = state.anchorAt
    local lag = anchor and now - anchor
    if lag and lag >= 0 and lag <= (fam == "weapon" and SWING_LAG or TOTEM_LAG) then
        state.lastProc[fam] = now
        return fam, "proc", nil, lag
    end
    state.pending[fam] = now
    return fam, "waiting", nil, nil
end
