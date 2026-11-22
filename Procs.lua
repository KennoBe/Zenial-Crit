local _, NS = ...
-- Pure proc logic. Cooldown correlation can drive the legacy effects; cards also require
-- independently verified evidence of an own proc on a specific nameplate binding.
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
local MAX_OPEN, MAX_ANCHORS, MAX_SEEN = 8, 8, 64
local EPSILON = 1e-9
local EXTRA_GAP, EXTRA_MIN_PERIOD, EXTRA_GRACE = .45, 1, .25
-- Own combat-log lines (typed by their public colour, text opaque) supply the amounts on a card.
P.LINE_TAIL = .23        -- a strike's line follows its swing at most this long
P.LINE_MISS_TAIL = .42   -- a strike's miss line may come later
P.STRIKES_MAX = 2        -- Windfury Weapon strikes per proc
local LINE_TAIL, LINE_MISS_TAIL, STRIKES_MAX = P.LINE_TAIL, P.LINE_MISS_TAIL, P.STRIKES_MAX
local MAX_LINES, LINE_KEEP = 24, 1.5

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
        anchorAt = nil,
        lastProc = {},
        castAt = {[8516] = -math.huge, [10608] = -math.huge, [10610] = -math.huge},
        cooldowns = {},
        pending = {},
        anchors = {},
        candidates = {},
        evidence = {},
        decisions = {},
        finalized = {},
        seen = {},
        unkeyed = {},
        targetRevision = 0,
        nextID = 0,
        lines = {},
        wantLines = false,
    }
end

-- Whether cards wait for own combat-log lines (the option is on and the log is ready).
function P.SetLines(state, enabled)
    state.wantLines = enabled == true
    if not state.wantLines then state.lines, state.castMark = {}, nil end
end

local FAMILIES = {"weapon", "totem"}

local function window(fam)
    return fam == "weapon" and SWING_LAG or TOTEM_LAG
end

local function finite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

local function targetSnapshot(ref)
    if type(ref) ~= "table" then return nil end
    local unit, plate, guid, generation = ref.unit, ref.plate, ref.guid, ref.generation
    local plateType = type(plate)
    if type(unit) ~= "string" or unit == "" or (plateType ~= "table" and plateType ~= "userdata")
        or (guid ~= nil and (type(guid) ~= "string" or guid == ""))
        or not finite(generation) or generation < 1 or generation % 1 ~= 0 then return nil end
    return {unit = unit, plate = plate, guid = guid, generation = generation}
end

local function sameTarget(left, right)
    return left.unit == right.unit and rawequal(left.plate, right.plate)
        and left.guid == right.guid and left.generation == right.generation
end

local function claimUnkeyed(state, family, target, now)
    for index = #state.unkeyed, 1, -1 do
        local entry = state.unkeyed[index]
        if entry.untilAt <= now then
            table.remove(state.unkeyed, index)
        elseif entry.family == family and sameTarget(entry.targetRef, target) then
            return "duplicate"
        end
    end
    if #state.unkeyed >= MAX_SEEN then return "queue_full" end
    local gap = family == "weapon" and WEAPON_GAP or family == "totem" and TOTEM_GAP or TOTEM_LAG
    state.unkeyed[#state.unkeyed + 1] = {family = family, targetRef = target, untilAt = now + gap}
end

local function queueDecision(state, fam, result, reason, lag)
    if #state.decisions < MAX_OPEN * 2 then
        state.decisions[#state.decisions + 1] = {fam, result, reason, lag}
    end
end

local function anchorFits(anchorAt, cooldownAt, lag)
    return anchorAt >= cooldownAt - lag - EPSILON and anchorAt <= cooldownAt + SWING_LEAD + EPSILON
end

local function addCandidate(state, fam, cooldown)
    local lag = window(fam)
    for _, anchor in ipairs(state.anchors) do
        if anchor.targetRef and anchorFits(anchor.at, cooldown.at, lag) then
            if #state.candidates + #state.evidence >= MAX_OPEN then
                queueDecision(state, fam, "rejected", "queue_full")
            else
                local deadline = cooldown.at + lag
                local due
                -- With amounts the card waits until the strike lines (or a late extra swing) can be there.
                if state.wantLines then
                    due = math.max(deadline, anchor.at + LINE_TAIL, fam == "totem" and anchor.at + EXTRA_GAP or 0)
                end
                state.candidates[#state.candidates + 1] = {
                    family = fam, at = cooldown.at, deadline = deadline, due = due, edge = cooldown.edge,
                    spellID = cooldown.spellID, targetRef = cooldown.targetRef, revision = cooldown.revision,
                    anchor = anchor,
                }
            end
            return
        end
    end
end

-- The own lines of one kind in a time span that no card has taken; misses count as a strike
-- without an amount. A line that an own cast marked belongs to that cast.
local function freeLines(state, from, to, damage, miss, missTo)
    local list = {}
    for _, entry in ipairs(state.lines) do
        if not entry.used and not entry.cast and entry.at >= from - EPSILON then
            if entry.kind == damage and entry.at <= to + EPSILON then
                list[#list + 1] = entry
            elseif miss and entry.kind == miss and entry.at <= (missTo or to) + EPSILON then
                list[#list + 1] = entry
            end
        end
    end
    return list
end

-- The line that came right after a swing (its own white line, landed or missed).
local function swingLines(state, anchor)
    local list = {}
    for _, entry in ipairs(state.lines) do
        if not entry.used and entry.after == anchor
            and (entry.kind == "SWING_DAMAGE" or entry.kind == "SWING_MISSED") then list[#list + 1] = entry end
    end
    return list
end

-- The next main-hand swing after a root swing (a granted extra attack), if exactly one; it may
-- share the root's frame.
local function extraSwing(state, root)
    local seen, found = false, nil
    for _, anchor in ipairs(state.anchors) do
        if anchor == root then
            seen = true
        elseif seen and anchor.swing and anchor.at <= root.at + EXTRA_GAP + EPSILON then
            if found then return nil end
            found = anchor
        end
    end
    return found
end

local function lineHit(entry, family)
    entry.used = true
    local hit = {at = entry.at, line = entry.line, amountKind = "line", family = family}
    if entry.kind == "SWING_MISSED" or entry.kind == "SPELL_MISSED" then
        hit.line, hit.amountKind, hit.miss = nil, "none", true
    end
    return hit
end

-- The lines a card of this family would choose from (one selection for the wait check and attachLines).
-- A re-armed (late) card accepts damage lines up to the miss tail.
local function selectLines(state, fam, root, extra, late)
    local at = root.at
    local to = at + (late and LINE_MISS_TAIL or LINE_TAIL)
    if fam == "weapon" then
        return freeLines(state, at, to, "SPELL_DAMAGE", "SPELL_MISSED", at + LINE_MISS_TAIL)
    end
    extra = extra or extraSwing(state, root)
    if extra then return swingLines(state, extra) end
    -- A shaman's own totem: its extra attack is a spell line; the weapon took its strikes first.
    if fam == "totem" then return freeLines(state, at, to, "SPELL_DAMAGE", "SPELL_MISSED", at + LINE_MISS_TAIL) end
    return {}
end

-- Amounts for a settled card from the own lines of its swing. Ambiguity leaves the title only.
local function attachLines(state, result, root, extra, late)
    result.late = late == true or nil
    if not state.wantLines then result.note = "lines_off"; return end
    if type(root) ~= "table" or not root.swing then result.note = "no_swing_root"; return end
    local fam, picked = result.family, nil
    local list = selectLines(state, fam, root, extra, late)
    result.lineCount = #list
    if fam == "weapon" then
        -- A totem proc on the same swing writes one more spell line (a shaman's own totem).
        local most = STRIKES_MAX
        for _, candidate in ipairs(state.candidates) do
            if candidate.family == "totem" and candidate.anchor == root then most = STRIKES_MAX + 1 end
        end
        if #list >= 1 and #list <= most then
            picked = {}
            for index = 1, math.min(#list, STRIKES_MAX) do picked[#picked + 1] = list[index] end
        end
    elseif #list == 1 then
        picked = list
    end
    if not picked then result.note = #list == 0 and "none" or "many"; return end
    result.note = "ok"
    local hits = {}
    for _, entry in ipairs(picked) do hits[#hits + 1] = lineHit(entry, fam) end
    result.hits = hits
    result.complete = #hits == (fam == "weapon" and STRIKES_MAX or 1)
    result.confidence = result.confidence == "attack_target" and "line" or result.confidence
end

local function matchCandidate(state, observation)
    local match, reason
    for _, candidate in ipairs(state.candidates) do
        local lag = window(candidate.family)
        if candidate.family == observation.family and observation.at >= candidate.at - SWING_LEAD - EPSILON
            and observation.at <= candidate.deadline + EPSILON then
            local matches, unknown = 0, false
            for _, anchor in ipairs(state.anchors) do
                if anchorFits(anchor.at, candidate.at, lag) then
                    if not anchor.targetRef then
                        unknown = true
                    elseif sameTarget(anchor.targetRef, observation.targetRef) then
                        matches = matches + 1
                    end
                end
            end
            if matches > 1 or (matches == 1 and (match or unknown
                or (state.droppedAnchorAt and state.droppedAnchorAt >= candidate.at - lag - EPSILON))) then
                return nil, "ambiguous_hit"
            elseif matches == 1 then
                match = candidate
            else
                reason = "target_changed"
            end
        end
    end
    return match, reason
end

local function publish(state, result)
    if #state.finalized >= MAX_OPEN then
        queueDecision(state, result.family, "rejected", "queue_full")
        return
    end
    local fam = result.family
    state.nextID = state.nextID + 1
    result.id = state.nextID
    result.kind = fam == "extra" and "extra" or "windfury_" .. fam
    result.source = "player"
    result.status = "confirmed"
    result.hitCount = #result.hits
    state.finalized[#state.finalized + 1] = result
end

local function collectHit(result, observation)
    if observation.hit then
        local hits = result.hits
        local index = #hits + 1
        while index > 1 and hits[index - 1].at > observation.at do index = index - 1 end
        table.insert(hits, index, observation.hit)
    end
    if observation.direct then result.confidence = "direct" end
    if observation.complete then result.complete = true end
end

local function due(at, now, inclusive)
    return at < now or inclusive and at == now
end

-- A recognized own proc may display its name on an unchanged attack target.
-- Only independently attributed hits can supply numbers or a hit count.
local function fallbackTarget(state, candidate)
    local lag = window(candidate.family)
    if state.droppedAnchorAt and state.droppedAnchorAt >= candidate.at - lag - EPSILON then return nil, "card_dropped_anchor" end
    local cast = state.castAt[candidate.spellID]
    if cast and cast >= candidate.at - CAST_GUARD and cast <= candidate.deadline then return nil, "card_own_cast" end
    -- The target is the swing's own: every fitting anchor must know it, and all must agree.
    local target
    for _, anchor in ipairs(state.anchors) do
        if anchorFits(anchor.at, candidate.at, lag) then
            if not anchor.targetRef then return nil, "card_no_target" end
            if target and not sameTarget(target, anchor.targetRef) then return nil, "card_targets_differ" end
            -- Same target view as the swing, yet another target: the event does not belong to it.
            if candidate.targetRef and candidate.revision == anchor.revision
                and not sameTarget(candidate.targetRef, anchor.targetRef) then
                return nil, "card_targets_differ"
            end
            target = anchor.targetRef
        end
    end
    if not target then return nil, "card_no_target" end
    for _, observation in ipairs(state.evidence) do
        if observation.family == candidate.family and observation.direct
            and observation.at >= candidate.at - SWING_LEAD - EPSILON and observation.at <= candidate.deadline + EPSILON then
            return nil, "card_direct_evidence" -- Let explicit source and victim evidence decide where to show a card.
        end
    end
    return target
end

local function settleExtra(state, now)
    local grant = state.extraGrant
    if not grant or now < grant.deadline then return end
    state.extraGrant = nil
    if grant.revision ~= state.targetRevision then return end
    if state.droppedAnchorAt and state.droppedAnchorAt >= grant.at - EXTRA_GAP then return end

    -- Source-specific signals take precedence over the generic combat-text notification.
    local windfury = math.max(state.lastProc.weapon or -math.huge, state.lastProc.totem or -math.huge,
        state.windfuryGrantAt or -math.huge)
    if windfury >= grant.at - EXTRA_GAP and windfury <= grant.deadline then return end

    local previous, root, extra
    for _, anchor in ipairs(state.anchors) do
        if anchor.period and anchor.at >= grant.at - EXTRA_GAP and anchor.at <= grant.at + EXTRA_GAP then
            if anchor.revision ~= grant.revision or not anchor.targetRef or not sameTarget(anchor.targetRef, grant.targetRef) then
                return
            end
            if previous and previous.period >= EXTRA_MIN_PERIOD and anchor.at >= previous.at
                and anchor.at - previous.at <= EXTRA_GAP then
                if grant.paired then extra = nil else root, extra = previous, anchor end
                grant.paired = true
            end
            previous = anchor
        end
    end
    if grant.paired and not claimUnkeyed(state, "extra", grant.targetRef, grant.at) then
        local result = {family = "extra", triggerAt = grant.at, targetRef = grant.targetRef,
            spellID = grant.spellID, hits = {}, complete = false, confidence = "attack_target"}
        if extra then attachLines(state, result, root, extra) end
        publish(state, result)
    end
end

-- A due card with no line yet waits once more, up to the miss tail.
local function rearm(state, candidate)
    local anchor = candidate.anchor
    if not state.wantLines or candidate.due == nil or candidate.late or type(anchor) ~= "table" or not anchor.swing
        or anchor.at + LINE_MISS_TAIL <= candidate.due
        or #selectLines(state, candidate.family, anchor, nil, false) > 0 then return false end
    candidate.late, candidate.due = true, anchor.at + LINE_MISS_TAIL
    return true
end

local function expireRecords(state, now, inclusive)
    local ready = {}
    for _, candidate in ipairs(state.candidates) do
        if due(candidate.due or candidate.deadline, now, inclusive) then
            if not rearm(state, candidate) or due(candidate.due, now, inclusive) then ready[candidate] = true end
        end
    end
    for _, observation in ipairs(state.evidence) do
        if due(observation.deadline, now, inclusive) then
            ready[observation] = true
        end
    end
    if next(ready) == nil then return end

    local matches, groups = {}, {}
    for _, observation in ipairs(state.evidence) do
        local candidate, reason
        if observation.reason ~= "ambiguous_hit" then
            candidate, reason = matchCandidate(state, observation)
        end
        if candidate then
            matches[observation] = candidate
            local group = groups[candidate]
            if not group then
                group = {targetRef = observation.targetRef}
                groups[candidate] = group
            elseif not sameTarget(group.targetRef, observation.targetRef) then
                group.conflict = true
            end
            group.direct = group.direct or observation.direct
        elseif reason then
            observation.reason = reason
        end
    end

    local retained = {}
    for _, observation in ipairs(state.evidence) do
        local candidate = matches[observation]
        local group = groups[candidate]
        if group and group.conflict then
            observation.reason = "ambiguous_hit"
            candidate, group = nil, nil
        end
        if candidate and ready[candidate] then
            if candidate.edge or group.direct then
                if not group.hits then
                    group.family, group.triggerAt = candidate.family, candidate.at
                    group.hits, group.complete, group.confidence = {}, false, "corroborated"
                end
                collectHit(group, observation)
            else
                queueDecision(state, observation.family, "rejected", "source_unknown")
            end
        elseif not candidate and ready[observation] then
            if observation.direct then
                local result = {family = observation.family, triggerAt = observation.at, targetRef = observation.targetRef,
                    hits = {}, complete = false, confidence = "direct"}
                collectHit(result, observation)
                publish(state, result)
            else
                queueDecision(state, observation.family, "rejected", observation.reason or "source_unknown")
            end
        else
            retained[#retained + 1] = observation
        end
    end
    local pendingEvidence = retained
    retained = {}
    -- The weapon takes its strike lines before a totem on the same swing takes what is left.
    local order = {}
    for _, candidate in ipairs(state.candidates) do
        if ready[candidate] and candidate.family == "weapon" then order[#order + 1] = candidate end
    end
    for _, candidate in ipairs(state.candidates) do
        if ready[candidate] and candidate.family ~= "weapon" then order[#order + 1] = candidate end
        if not ready[candidate] then retained[#retained + 1] = candidate end
    end
    for _, candidate in ipairs(order) do
        local group = groups[candidate]
        if group and group.hits then
            group.direct = nil
            if #group.hits == 0 then attachLines(state, group, candidate.anchor, nil, candidate.late) end
            publish(state, group)
        else
            local target, why = fallbackTarget(state, candidate)
            if target then
                local claimed = claimUnkeyed(state, candidate.family, target, candidate.at)
                if claimed then
                    queueDecision(state, candidate.family, "rejected", "card_" .. claimed)
                else
                    local result = {family = candidate.family, triggerAt = candidate.at,
                        targetRef = target, hits = {}, complete = false, confidence = "attack_target"}
                    attachLines(state, result, candidate.anchor, nil, candidate.late)
                    publish(state, result)
                end
            elseif why ~= "card_direct_evidence" then
                queueDecision(state, candidate.family, "rejected", why)
            end
        end
    end
    state.candidates = retained
    state.evidence = pendingEvidence
end

-- A settled candidate that could not be returned directly. Call after every entry point until nil.
function P.Drain(state)
    local decision = table.remove(state.decisions, 1)
    if decision then return decision[1], decision[2], decision[3], decision[4] end
end

function P.DrainFinal(state)
    return table.remove(state.finalized, 1)
end

function P.Deadline(state)
    local at = state.extraGrant and state.extraGrant.deadline or math.huge
    for _, candidate in pairs(state.pending) do at = math.min(at, candidate.at + SWING_LEAD + EPSILON) end
    for _, candidate in ipairs(state.candidates) do at = math.min(at, candidate.due or candidate.deadline) end
    for _, observation in ipairs(state.evidence) do at = math.min(at, observation.deadline) end
    if at ~= math.huge then return at end
end

function P.Expire(state, now)
    for _, fam in ipairs(FAMILIES) do
        local pending = state.pending[fam]
        if pending and due(pending.at + SWING_LEAD + EPSILON, now, true) then
            state.pending[fam] = nil
            queueDecision(state, fam, "rejected", "no_swing")
        end
    end
    expireRecords(state, now, true)
    settleExtra(state, now)
end

-- The first legacy decision is returned directly; any simultaneous decision waits in Drain.
local function settle(state, now, anchored)
    local first
    for _, fam in ipairs(FAMILIES) do
        local pending = state.pending[fam]
        if pending and (not anchored or now >= pending.at) then
            state.pending[fam] = nil
            local result, reason, lag = "rejected", "no_swing", nil
            if anchored and now - pending.at <= SWING_LEAD + EPSILON then
                state.lastProc[fam] = pending.at
                addCandidate(state, fam, pending)
                result, reason, lag = "proc", nil, pending.at - now
            end
            if first == nil then
                first = {fam, result, reason, lag}
            else
                queueDecision(state, fam, result, reason, lag)
            end
        end
    end
    if first then return first[1], first[2], first[3], first[4] end
end

-- Closes every waiting candidate as "no swing" (end of a test).
function P.Settle(state)
    return settle(state, 0, false)
end

local function addAnchor(state, now, targetRef, period, swing)
    expireRecords(state, now, false)
    state.anchorAt = math.max(state.anchorAt or now, now)
    if #state.anchors >= MAX_ANCHORS then
        local dropped = table.remove(state.anchors, 1)
        state.droppedAnchorAt = math.max(state.droppedAnchorAt or dropped.at, dropped.at)
    end
    local anchor = {at = now, targetRef = targetSnapshot(targetRef), revision = state.targetRevision,
        period = period, swing = swing}
    state.anchors[#state.anchors + 1] = anchor
    -- The next own line in this frame is this swing's white line.
    state.lastSwing = swing and anchor or nil
    return settle(state, now, true)
end

function P.OnTargetChanged(state)
    state.targetRevision = state.targetRevision + 1
end

-- hand 0 = main hand. Anything else (ranged 2, off hand) is no anchor.
function P.OnSwing(state, now, hand, targetRef, period)
    if hand ~= 0 then return nil end
    return addAnchor(state, now, targetRef, finite(period) and period or nil, true)
end

function P.OnExtraAttack(state, now, family, targetRef, spellID)
    if family ~= "extra" then
        state.windfuryGrantAt = now
        return
    end
    local target = targetSnapshot(targetRef)
    if not target then return end
    settleExtra(state, now)
    local grant = state.extraGrant
    if grant and grant.revision == state.targetRevision and sameTarget(grant.targetRef, target) then
        if spellID and grant.spellID and spellID ~= grant.spellID then grant.mixed = true end
        if grant.mixed then grant.spellID = nil elseif spellID then grant.spellID = spellID end
        return
    end
    state.extraGrant = {at = now, deadline = now + EXTRA_GAP + EXTRA_GRACE, targetRef = target,
        spellID = spellID, revision = state.targetRevision}
end

-- An own combat-log line, typed by its public colour. The line itself stays opaque: it is only
-- carried to the card, never read, compared or stored.
function P.OnLogLine(state, now, kind, line)
    if not state.wantLines or not finite(now) or type(kind) ~= "string" or line == nil then return end
    local lines = state.lines
    while lines[1] and (lines[1].at < now - LINE_KEEP or #lines >= MAX_LINES) do table.remove(lines, 1) end
    local swing = state.lastSwing
    state.lastSwing = nil
    -- The next line in the frame of an own cast is that cast's line (all of them for Stormstrike).
    local mark, cast = state.castMark, nil
    if mark then
        if mark.at == now then
            cast = true
            if not mark.whole then state.castMark = nil end
        else
            state.castMark = nil
        end
    end
    lines[#lines + 1] = {at = now, kind = kind, line = line, cast = cast,
        after = swing and swing.at == now and swing or nil}
end

-- Stormstrike is an anchor like a swing; an own totem cast is remembered per ID.
-- An own cast marks its own line, which never becomes a proc's amount. The Windfury Weapon proc's
-- own IDs mark nothing.
function P.OnCast(state, now, spellID, targetRef)
    if state.wantLines and finite(now) and family[spellID] ~= "weapon" then
        state.castMark = {at = now, whole = spellID == STORMSTRIKE}
    end
    if spellID == STORMSTRIKE then
        return addAnchor(state, now, targetRef)
    elseif totemSet[spellID] then
        state.castAt[spellID] = now
        local pending = state.pending.totem
        if pending and pending.spellID == spellID and now >= pending.at and now - pending.at <= SWING_LEAD + EPSILON then
            state.pending.totem = nil
            return "totem", "rejected", "own_cast", nil
        end
    end
    return nil
end

function P.ObserveCooldownBaseline(state, spellID, active)
    if not family[spellID] or type(active) ~= "boolean" then return end
    local sample = state.cooldowns[spellID]
    if not sample then
        state.cooldowns[spellID] = {active = active, tracked = active}
    end
end

local function cooldownRejection(state, now, spellID, active, onGCD)
    if onGCD == true then return "cooldown_gcd" end
    local previous = state.cooldowns[spellID]
    if previous and previous.at and now < previous.at then return "out_of_order" end
    local tracked = (previous and previous.tracked) or (active == true and onGCD == false)
    state.cooldowns[spellID] = {at = now, active = active, tracked = tracked}
    if active == true and previous and previous.active == true then return "cooldown_active" end
    if active == false and tracked then
        return previous.active == true and "cooldown_end" or "cooldown_inactive"
    end
    return nil, active == true and onGCD == false and previous ~= nil and previous.active == false
end

function P.OnCooldown(state, now, spellID, watchWeapon, watchTotem, active, onGCD, targetRef)
    local fam = family[spellID]
    if not fam then return nil end
    local watched = fam == "weapon" and watchWeapon or fam == "totem" and watchTotem
    if not watched then return fam, "rejected", "off", nil end
    expireRecords(state, now, false)
    local cooldownReason, edge = cooldownRejection(state, now, spellID, active, onGCD)
    if cooldownReason then return fam, "rejected", cooldownReason, nil end
    -- A candidate that waited too long is closed first (returned by Drain), then this event counts.
    local pending = state.pending[fam]
    if pending then
        if now - pending.at <= SWING_LEAD + EPSILON then
            return fam, "rejected", "too_soon", nil -- the same proc, a second ID
        end
        state.pending[fam] = nil
        queueDecision(state, fam, "rejected", "no_swing")
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
    local cooldown = {at = now, spellID = spellID, edge = edge,
        targetRef = targetSnapshot(targetRef), revision = state.targetRevision}
    if lag and lag >= 0 and lag <= window(fam) then
        state.lastProc[fam] = now
        addCandidate(state, fam, cooldown)
        return fam, "proc", nil, lag
    end
    state.pending[fam] = cooldown
    return fam, "waiting", nil, nil
end

-- The caller supplies public evidence of its own proc, rather than a generic damage event.
function P.OnEvidence(state, now, evidence)
    if type(evidence) ~= "table" then return nil end
    local fam = evidence.family
    if fam ~= "weapon" and fam ~= "totem" and fam ~= "extra" then return nil end
    local spellID = evidence.spellID
    local named = family[spellID]
    if (fam == "extra" and named) or (fam ~= "extra" and spellID ~= nil and named ~= fam) then
        return fam, "rejected", "source_unknown", nil
    end
    local ref = targetSnapshot(evidence.targetRef)
    if not ref then return fam, "rejected", "target_changed", nil end

    expireRecords(state, now, false)
    local eventID = evidence.eventID
    if not ((type(eventID) == "string" and eventID ~= "") or finite(eventID)) then eventID = nil end
    local count = 0
    if eventID ~= nil then
        for id, deadline in pairs(state.seen) do
            if deadline < now then state.seen[id] = nil else count = count + 1 end
        end
        if state.seen[eventID] then return fam, "rejected", "duplicate", nil end
    end
    if #state.evidence + #state.candidates >= MAX_OPEN or count >= MAX_SEEN then
        return fam, "rejected", "queue_full", nil
    end
    if evidence.unkeyed == true then
        -- A public formatted line proves a hit or occurrence but carries no identity by which
        -- to distinguish a duplicate from a second hit. Keep one representative per binding.
        local reason = claimUnkeyed(state, fam, ref, now)
        if reason then return fam, "rejected", reason, nil end
    end
    if eventID ~= nil then state.seen[eventID] = now + WEAPON_GAP end
    local hit
    if evidence.hit ~= false then
        hit = {at = now, spellID = spellID}
        if finite(evidence.amount) then hit.amount, hit.amountKind = evidence.amount, "number"
        else hit.amountKind = "none" end
        if type(evidence.critical) == "boolean" then hit.critical = evidence.critical end
    end
    state.evidence[#state.evidence + 1] = {
        family = fam, at = now, deadline = now + SWING_LEAD + window(fam), targetRef = ref,
        hit = hit, direct = named ~= nil or fam == "extra", complete = evidence.complete == true and evidence.unkeyed ~= true,
    }
    return fam, "waiting", nil, nil
end
