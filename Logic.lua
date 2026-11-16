local _, NS = ...
local L = {}
NS.Logic = L

local critChoices = {"critmix", "klong", "bonk", "meme_bonk", "punch", "squeak", "impact", "laser", "jackpot", "arcade"}
local killChoices = {"killmix", "bruh", "meme_bruh", "meme_oof", "womp", "meme_bowomp", "gameover", "fall", "jackpot", "doom", "tada", "finisher"}
local fontStyles = {"standard", "comic", "epic", "heavy"}
local critChoiceSet, killChoiceSet = {}, {}
local fontStyleSet = {}
for _, preset in ipairs(critChoices) do critChoiceSet[preset] = true end
for _, preset in ipairs(killChoices) do killChoiceSet[preset] = true end
for _, style in ipairs(fontStyles) do fontStyleSet[style] = true end

local defaults = {
    schema = 17,
    critGraphics = true, critSound = true,
    healSound = true,
    killGraphics = true, killSound = true,
    critSoundMode = "single", critSoundIDs = {"klong"},
    healSoundMode = "single", healSoundIDs = {"tada"},
    killSoundMode = "single", killSoundIDs = {"bruh"},
    recordSoundMode = "single", recordSoundIDs = {"jackpot"},
    healRecordSoundMode = "single", healRecordSoundIDs = {"jackpot"},
    lowSoundMode = "single", lowSoundIDs = {"womp"},
    healLowSoundMode = "single", healLowSoundIDs = {"womp"},
    recordSoundEnabled = false, lowCritEnabled = false,
    lowCritPercent = 30, critSoundRule = "all",
    healRecordSoundEnabled = false, healLowEnabled = false,
    healLowPercent = 30, healSoundRule = "all",
    critSoundChannel = "Master", healSoundChannel = "Master", killSoundChannel = "Master",
    recordSoundChannel = "Master", healRecordSoundChannel = "Master",
    lowSoundChannel = "Master", healLowSoundChannel = "Master",
    chatEnabled = false, chatCrit = true, chatHeal = true, chatKill = true,
    chatRecord = true, chatHealRecord = true, chatLow = true, chatHealLow = true,
    customSounds = {}, customSoundNextID = 1,
    critFont = "standard", killFont = "standard",
    critColor = {.98, .8, .12}, killColor = {1, .36, .06},
    critTexts = {
        "CRIT HAPPENS!", "IN YOUR FACE!", "THAT'S GOTTA HURT!", "GET BONKED!", "BOOM!",
        "RIGHT IN THE FACE!", "CRITICAL DAMAGE!", "SMACKDOWN!", "TAKE THAT!", "FULL FORCE!",
    },
    killTexts = {
        "BACK TO ORGRIMMAR!", "GO TAKE A SHOWER!", "NIGHT NIGHT!", "SKILL ISSUE!", "BACK TO THE GRAVEYARD!",
        "GG, GET REKT!", "RESPAWN SIMULATOR!", "NO MORE LAG FOR YOU!", "LOOT PINATA!", "SIT DOWN!",
    },
    scale = 1, nameplateScale = 1, intensity = 2, soundCooldown = .25, x = 0, y = 160,
    separatePositions = false, critX = 0, critY = 160, killX = 0, killY = 160,
    displayMode = "nameplate",
    -- Schema 15
    healTexts = {"HEAL CRIT!", "BIG HEAL!", "TOPPED UP!"},
    -- Schema 16: kills in a streak at which each step (and its text and sound) begins.
    streakTexts = {"DOUBLE KILL!", "TRIPLE KILL!", "ULTRA KILL!", "MEGA KILL!", "MONSTER KILL!"},
    streakSteps = {2, 3, 4, 5, 8},
    streakSoundMode = "single", streakSoundIDs = {"announcer"},
    procSoundMode = "single", procSoundIDs = {"laser"},
    streakSoundChannel = "Master", procSoundChannel = "Master",
    enabled = true, maxEffects = 3, stackSpacing = 60, critGap = 0, combine = false,
    critMinPercent = 0, healMinPercent = 0,
    situationWorld = "all", situationDungeon = "all", situationRaid = "all", situationPvp = "all",
    streakWindow = 8, streakTargets = "all", streakEscalate = true, streakHideKill = true,
    procTriggers = {},
    -- Schema 17: Windfury of the weapon and of the totem.
    procWindfuryWeapon = true, procWindfuryTotem = true, procWindfuryFlash = true,
    procWindfuryWeaponText = "WINDFURY!", procWindfuryTotemText = "WINDFURY TOTEM!",
    windfurySoundMode = "single", windfurySoundIDs = {"thunder"}, windfurySoundChannel = "Master",
}
local bounds = {
    scale = {.6, 2.5}, nameplateScale = {.6, 4.2}, intensity = {1, 3}, soundCooldown = {0, 30},
    lowCritPercent = {1, 100}, healLowPercent = {1, 100}, customSoundNextID = {1, 1000000},
    x = {-2000, 2000}, y = {-1200, 1200},
    critX = {-2000, 2000}, critY = {-1200, 1200},
    killX = {-2000, 2000}, killY = {-1200, 1200},
    maxEffects = {1, 6, 1}, stackSpacing = {0, 120}, critGap = {0, 3, .05},
    critMinPercent = {0, 100}, healMinPercent = {0, 100}, streakWindow = {2, 30},
}

local kinds = {"crit", "heal", "kill", "streak", "proc"}
local animations = {"pop", "slam", "rise", "shake", "pulse", "fade"}
local animationSet, situationSet, targetSet = {}, {all = true, important = true, off = true}, {all = true, players = true}
for _, name in ipairs(animations) do animationSet[name] = true end
L.Kinds, L.Animations = kinds, animations

-- Per-kind style values. Keys already present above keep their schema 14 values.
local kindStyle = {
    crit = {Graphics = true, Sound = true, Font = "standard", Color = {.98, .8, .12}, Gradient = false,
        Color2 = {1, .45, .1}, Size = 1, Anim = "pop", Duration = .85, Alpha = 1, X = 0, Y = 160},
    heal = {Graphics = false, Sound = true, Font = "standard", Color = {.45, .9, .54}, Gradient = false,
        Color2 = {.8, 1, .6}, Size = 1, Anim = "rise", Duration = .85, Alpha = 1, X = 0, Y = 160},
    kill = {Graphics = true, Sound = true, Font = "standard", Color = {1, .36, .06}, Gradient = false,
        Color2 = {1, .8, .1}, Size = 1, Anim = "pop", Duration = .85, Alpha = 1, Flash = false, X = 0, Y = 160},
    streak = {Graphics = true, Sound = true, Font = "heavy", Color = {1, .18, .12}, Gradient = true,
        Color2 = {1, .75, .1}, Size = 1.35, Anim = "slam", Duration = 1.6, Alpha = 1, Flash = false, X = 0, Y = 220},
    proc = {Graphics = true, Sound = true, Font = "standard", Color = {.35, .8, 1}, Gradient = false,
        Color2 = {.9, .95, 1}, Size = 1.15, Anim = "pulse", Duration = 1.1, Alpha = 1, Flash = false, X = 0, Y = 100},
}
local colorKeys, enums, textKinds = {}, {}, {
    critTexts = "crit", healTexts = "heal", killTexts = "kill", streakTexts = "streak",
}
for _, kind in ipairs(kinds) do
    for name, value in pairs(kindStyle[kind]) do
        local key = kind .. name
        if defaults[key] == nil then defaults[key] = value end
    end
    colorKeys[kind .. "Color"], colorKeys[kind .. "Color2"] = true, true
    enums[kind .. "Anim"] = animationSet
    if not bounds[kind .. "Size"] then
        bounds[kind .. "Size"] = {.5, 2.5, .05}
        bounds[kind .. "Duration"] = {.4, 3, .05}
        bounds[kind .. "Alpha"] = {.2, 1, .05}
    end
    if not bounds[kind .. "X"] then
        bounds[kind .. "X"], bounds[kind .. "Y"] = {-2000, 2000}, {-1200, 1200}
    end
end
enums.situationWorld, enums.situationDungeon = situationSet, situationSet
enums.situationRaid, enums.situationPvp = situationSet, situationSet
enums.streakTargets = targetSet

L.FontStyles = fontStyles

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = deepCopy(item) end
    return result
end

function L.Defaults() return deepCopy(defaults) end

-- Resets the given keys to their default values (sound keys included). Unknown keys are ignored.
function L.ResetKeys(config, keys)
    if type(config) ~= "table" then return config end
    for _, key in ipairs(type(keys) == "table" and keys or {}) do
        if type(key) == "string" and defaults[key] ~= nil and key ~= "schema" then
            config[key] = deepCopy(defaults[key])
        end
    end
    return config
end

local function copyTexts(values)
    local result = {}
    for _, value in ipairs(values) do result[#result + 1] = value end
    return result
end

local function copyArray(values)
    local result = {}
    if type(values) == "table" then
        for i = 1, #values do result[#result + 1] = values[i] end
    end
    return result
end

local function sanitizeColor(value, fallback)
    local result = {}
    for index = 1, 3 do
        local channel = type(value) == "table" and value[index] or nil
        if type(channel) ~= "number" or channel ~= channel then channel = fallback[index] end
        result[index] = math.max(0, math.min(1, channel))
    end
    return result
end

local TEXT_LIMIT = 40

local function charLength(text)
    return #(text:gsub("[\128-\191]", ""))
end

-- Keeps whole UTF-8 characters.
local function truncate(text, limit)
    if charLength(text) <= limit then return text end
    local count, last = 0, 0
    for position, char in text:gmatch("()([^\128-\191][\128-\191]*)") do
        count = count + 1
        if count > limit then break end
        last = position + #char - 1
    end
    return text:sub(1, last)
end

function L.SanitizeTexts(input, kind)
    local fallback = kind == "kill" and defaults.killTexts or kind == "heal" and defaults.healTexts
        or kind == "streak" and defaults.streakTexts or defaults.critTexts
    local values = {}
    if type(input) == "string" then
        input = input:gsub("\r\n", "\n"):gsub("\r", "\n")
        for line in (input .. "\n"):gmatch("(.-)\n") do values[#values + 1] = line end
    elseif type(input) == "table" then
        for index = 1, math.min(#input, 20) do values[#values + 1] = input[index] end
    end
    local result = {}
    for _, value in ipairs(values) do
        if type(value) == "string" then
            value = value:gsub("[%c]", ""):match("^%s*(.-)%s*$") or ""
            if value ~= "" then
                result[#result + 1] = truncate(value, TEXT_LIMIT):match("^(.-)%s*$")
                if #result >= 20 then break end
            end
        end
    end
    return #result > 0 and result or copyTexts(fallback)
end

function L.JoinTexts(values)
    return table.concat(type(values) == "table" and values or {}, "\n")
end

-- True when SanitizeTexts would return the same list unchanged. Saved texts
-- are sanitized on load and on every edit, so picks need no new copy.
local function sanitizedTexts(values)
    if type(values) ~= "table" or #values < 1 or #values > 20 then return false end
    for index = 1, #values do
        local value = values[index]
        if type(value) ~= "string" or value == "" or charLength(value) > TEXT_LIMIT or value:find("[%c]")
            or value:find("^%s") or value:find("%s$") then return false end
    end
    return true
end

function L.PickText(config, kind, random)
    local values = kind == "kill" and config.killTexts or kind == "heal" and config.healTexts or config.critTexts
    if not sanitizedTexts(values) then values = L.SanitizeTexts(values, kind) end
    local index = type(random) == "function" and random(#values) or math.random(#values)
    if type(index) ~= "number" or index < 1 or index > #values then index = 1 end
    return values[math.floor(index)] or values[1]
end

local function snapToStep(value, step)
    value = math.floor(value / step + .5) * step
    return math.floor(value * 1000000 + .5) / 1000000
end

local function cleanLine(value, limit)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%c]", ""):match("^%s*(.-)%s*$") or ""
    value = truncate(value, limit):match("^%s*(.-)%s*$") or ""
    return value ~= "" and value or nil
end

local function sanitizeFont(value, fallback)
    if fontStyleSet[value] then return value end
    if type(value) == "string" and value:sub(1, 7) == "shared:" then
        local name = value:sub(8)
        if #name >= 1 and #name <= 80 and not name:find("[%c]") then return value end
    end
    return fallback
end

local function sanitizeProcTriggers(value)
    local result, seen = {}, {}
    if type(value) ~= "table" then return result end
    for index = 1, math.min(#value, 100) do
        local item = value[index]
        if type(item) == "table" then
            local id, text = item.id, cleanLine(item.text, 40)
            if type(id) == "number" and id == id and id >= 1 and id <= 9999999 and id == math.floor(id)
                and text and not seen[id] then
                seen[id] = true
                result[#result + 1] = {id = id, text = text, enabled = item.enabled ~= false}
                if #result >= 10 then break end
            end
        end
    end
    return result
end

local STEP_MIN, STEP_MAX, STEP_COUNT = 2, 99, 10

-- Ascending whole numbers from 2 to 99, at most 10. Invalid entries and duplicates drop out;
-- nothing left means the default.
local function sanitizeSteps(value)
    local result, seen = {}, {}
    if type(value) == "table" then
        for index = 1, #value do
            local item = value[index]
            if type(item) == "number" and item == item and item >= STEP_MIN and item <= STEP_MAX
                and item == math.floor(item) and not seen[item] then
                seen[item] = true
                result[#result + 1] = item
            end
        end
    end
    table.sort(result)
    while #result > STEP_COUNT do result[#result] = nil end
    if #result == 0 then return copyArray(defaults.streakSteps) end
    return result
end

function L.StreakStepsText(config)
    local steps = sanitizeSteps(type(config) == "table" and config.streakSteps or nil)
    local parts = {}
    for index = 1, #steps do parts[index] = tostring(steps[index]) end
    return table.concat(parts, ", ")
end

-- Numbers separated by comma, semicolon or space. Returns the list or nil when nothing valid was typed.
function L.ParseStreakSteps(text)
    if type(text) ~= "string" then return nil end
    local values = {}
    for token in text:gmatch("[^,;%s]+") do
        local number = token:match("^%d+$") and tonumber(token) or nil
        if not number then return nil end
        values[#values + 1] = number
    end
    if #values == 0 then return nil end
    for _, number in ipairs(values) do
        if number < STEP_MIN or number > STEP_MAX then return nil end
    end
    return sanitizeSteps(values)
end

local oldStreakTexts = {"DOUBLE KILL!", "TRIPLE KILL!", "MULTI KILL!", "MEGA KILL!", "UNSTOPPABLE!"}
local function isOldStreakDefault(value)
    if type(value) ~= "table" or #value ~= #oldStreakTexts then return false end
    for index = 1, #oldStreakTexts do
        if value[index] ~= oldStreakTexts[index] then return false end
    end
    return true
end

function L.Sanitize(input)
    input = type(input) == "table" and input or {}
    local result = {schema = defaults.schema}
    result.customSounds, result.customSoundNextID = NS.Sounds.SanitizeCustom(
        input.customSounds, input.customSoundNextID
    )
    for key, default in pairs(defaults) do
        if key ~= "schema" and key ~= "customSounds" and key ~= "customSoundNextID"
            and not key:match("SoundIDs$") and not key:match("SoundMode$") then
            if key == "streakSteps" then
                result[key] = sanitizeSteps(input[key])
            elseif textKinds[key] then
                local texts = input[key]
                if key == "streakTexts" and input.schema == 15 and isOldStreakDefault(texts) then texts = nil end
                result[key] = L.SanitizeTexts(texts, textKinds[key])
            elseif key == "procTriggers" then
                result[key] = sanitizeProcTriggers(input[key])
            elseif key == "procWindfuryWeaponText" or key == "procWindfuryTotemText" then
                result[key] = cleanLine(input[key], TEXT_LIMIT) or default
            elseif colorKeys[key] then
                result[key] = sanitizeColor(input[key], default)
            elseif key:match("Font$") then
                result[key] = sanitizeFont(input[key], default)
            elseif bounds[key] then
                local value = input[key]
                if value == nil and (key == "critX" or key == "killX") then value = input.x end
                if value == nil and (key == "critY" or key == "killY") then value = input.y end
                if type(value) ~= "number" or value ~= value then value = default end
                result[key] = math.max(bounds[key][1], math.min(bounds[key][2], value))
                if bounds[key][3] then
                    result[key] = math.max(bounds[key][1], math.min(bounds[key][2], snapToStep(result[key], bounds[key][3])))
                end
                if key == "intensity" then result[key] = math.floor(result[key]) end
            elseif key == "critGraphics" or key == "critSound" then
                local legacy
                if key == "critGraphics" then legacy = input.graphics else legacy = input.sound end
                if type(input[key]) == "boolean" then result[key] = input[key]
                elseif type(legacy) == "boolean" then result[key] = legacy
                else result[key] = default end
            elseif key == "displayMode" then
                result[key] = (input[key] == "nameplate" or input[key] == "fixed") and input[key] or default
            elseif key == "critSoundRule" or key == "healSoundRule" then
                result[key] = input[key] == "records" and "records" or "all"
            elseif key:match("SoundChannel$") then
                local channel = input[key]
                result[key] = (channel == "Dialog" or channel == "SFX") and channel or "Master"
            elseif enums[key] then
                result[key] = enums[key][input[key]] and input[key] or default
            elseif type(default) == "boolean" then
                if type(input[key]) == "boolean" then result[key] = input[key] else result[key] = default end
            else
                result[key] = deepCopy(default)
            end
        end
    end
    -- Normalize the beta's common size without changing the visible nameplate text.
    -- Stored fixed-position size remains available when switching back to that mode.
    if input.schema == 13 and input.displayMode == "nameplate" and input.nameplateScale == nil then
        result.nameplateScale = math.max(bounds.nameplateScale[1], math.min(bounds.nameplateScale[2], result.scale / .6))
    end
    local legacyCrit, legacyKill = input.critSoundPreset, input.killSoundPreset
    local critLegacy = {pop="bonk", finisher="punch", tada="punch", doom="impact"}
    local killLegacy = {pop="bruh", impact="doom", arcade="gameover", laser="fall"}
    if not critChoiceSet[legacyCrit] then legacyCrit = critLegacy[legacyCrit] end
    if not killChoiceSet[legacyKill] then legacyKill = killLegacy[legacyKill] end
    if not critChoiceSet[legacyCrit] then legacyCrit = "klong" end
    if not killChoiceSet[legacyKill] then legacyKill = "bruh" end
    local soundFallbacks = {
        crit = legacyCrit, heal = "tada", kill = legacyKill,
        record = "jackpot", healRecord = "jackpot", low = "womp", healLow = "womp",
        streak = "announcer", proc = "laser", windfury = "thunder",
    }
    for category, keys in pairs(NS.Sounds.CategoryKeys) do
        local mode = input[keys.mode]
        result[keys.mode] = mode == "mix" and "mix" or "single"
        local fallback = input[keys.ids] == nil and soundFallbacks[category] or nil
        result[keys.ids] = NS.Sounds.SanitizeIDs(input[keys.ids], fallback, result)
    end
    return result
end

local kindSet = {}
for _, kind in ipairs(kinds) do kindSet[kind] = true end

local function styleKind(kind) return kindSet[kind] and kind or "crit" end

function L.FontStyle(config, kind)
    kind = styleKind(kind)
    return sanitizeFont(config[kind .. "Font"], "standard")
end

-- anchored == nil: decided by the display mode (1.9.1 behavior). true/false force the
-- nameplate size or the fixed-position size.
function L.EffectScale(config, anchored)
    if anchored == nil then anchored = config.displayMode == "nameplate" end
    if anchored then return (config.nameplateScale or 1) * .6 end
    return config.scale
end

function L.Color(config, kind)
    kind = styleKind(kind)
    local value = sanitizeColor(config[kind .. "Color"], defaults[kind .. "Color"])
    return value[1], value[2], value[3]
end

function L.Color2(config, kind)
    kind = styleKind(kind)
    local value = sanitizeColor(config[kind .. "Color2"], defaults[kind .. "Color2"])
    return value[1], value[2], value[3]
end

function L.Position(config, kind)
    if config.separatePositions ~= true then return config.x, config.y end
    kind = styleKind(kind)
    local x, y = config[kind .. "X"], config[kind .. "Y"]
    if x == nil then x = defaults[kind .. "X"] end
    if y == nil then y = defaults[kind .. "Y"] end
    return x, y
end

function L.NewState()
    return {recentKills = {}, streakCount = 0, streakLast = nil}
end

function L.Output(config, kind)
    if kind == "crit" then
        return config.critGraphics, config.critSound
    elseif kind == "kill" then
        return config.killGraphics, config.killSound
    elseif kind == "heal" then
        return config.healGraphics, config.healSound
    elseif kind == "streak" then
        return config.streakGraphics, config.streakSound
    elseif kind == "proc" then
        return config.procGraphics, config.procSound
    end
    return false, false, nil
end

function L.SoundCategory(config, classification, kind)
    if kind == "streak" then return config.streakSound and "streak" or nil end
    if kind == "proc" then return config.procSound and "proc" or nil end
    if kind == "heal" then
        if config.healSoundRule == "records" then
            if classification == "record" and config.healRecordSoundEnabled then return "healRecord" end
            return nil
        end
        if classification == "record" and config.healRecordSoundEnabled then return "healRecord" end
        if classification == "low" and config.healLowEnabled then return "healLow" end
        return config.healSound and "heal" or nil
    end
    if config.critSoundRule == "records" then
        if classification == "record" and config.recordSoundEnabled then return "record" end
        return nil
    end
    if classification == "record" and config.recordSoundEnabled then return "record" end
    if classification == "low" and config.lowCritEnabled then return "low" end
    return config.critSound and "crit" or nil
end

function L.ClassifyCrit(amount, previous, config, kind)
    if type(previous) ~= "number" then return "baseline" end
    if amount > previous then return "record" end
    local lowEnabled = kind == "heal" and config.healLowEnabled or config.lowCritEnabled
    local lowPercent = kind == "heal" and config.healLowPercent or config.lowCritPercent
    if lowEnabled and amount <= previous * (lowPercent / 100) then return "low" end
    return "normal"
end

local channelKeys = {
    crit="critSoundChannel", heal="healSoundChannel", kill="killSoundChannel",
    record="recordSoundChannel", healRecord="healRecordSoundChannel",
    low="lowSoundChannel", healLow="healLowSoundChannel",
    streak="streakSoundChannel", proc="procSoundChannel", windfury="windfurySoundChannel",
}
function L.SoundChannel(config, category)
    local value = config[channelKeys[category] or "critSoundChannel"]
    return (value == "Dialog" or value == "SFX") and value or "Master"
end

function L.ChatCategory(classification, kind)
    if kind == "kill" then return "kill" end
    if kind == "heal" then
        if classification == "record" then return "healRecord" end
        if classification == "low" then return "healLow" end
        return "heal"
    end
    if classification == "record" then return "record" end
    if classification == "low" then return "low" end
    return "crit"
end

local chatKeys = {
    crit="chatCrit", heal="chatHeal", kill="chatKill", record="chatRecord",
    healRecord="chatHealRecord", low="chatLow", healLow="chatHealLow",
}
function L.ChatAllowed(config, category)
    return config.chatEnabled == true and config[chatKeys[category] or ""] == true
end

function L.Allow(state, config, kind, now, active, preview)
    if type(now) ~= "number" or now ~= now then return false end
    if not kindSet[kind] then return false end
    if preview then return true end
    local graphics, sound = L.Output(config, kind)
    if kind == "crit" then sound = sound or config.recordSoundEnabled or config.lowCritEnabled end
    if kind == "heal" then sound = sound or config.healRecordSoundEnabled or config.healLowEnabled end
    if not graphics and not sound then return false end
    return true
end

function L.AllowKill(state, victimGUID, now)
    if type(victimGUID) ~= "string" or victimGUID == "" or type(now) ~= "number" then return false end
    local recent, count, oldestGUID, oldestTime = state.recentKills, 0, nil, math.huge
    for guid, seenAt in pairs(recent) do
        if now - seenAt > 10 then
            recent[guid] = nil
        else
            count = count + 1
            if seenAt < oldestTime then oldestGUID, oldestTime = guid, seenAt end
        end
    end
    if recent[victimGUID] then return false end
    if count >= 20 and oldestGUID then recent[oldestGUID] = nil end
    recent[victimGUID] = now
    return true
end

-- Animation curves. Returns scale, alpha, dx, dy, done. No tables, no randomness;
-- shaking uses math.sin of the time. "pop" with duration .85 is the 1.9.1 curve.
function L.Animation(anim, age, duration, intensity)
    if type(duration) ~= "number" or duration ~= duration or duration <= 0 then duration = .85 end
    if type(age) ~= "number" or age ~= age then age = 0 end
    if type(intensity) ~= "number" or intensity ~= intensity then intensity = 2 end
    local p = math.max(0, math.min(1, age / duration))
    local done = age >= duration
    if anim == "slam" then
        local inv = 1 - math.min(1, p / .15)
        local wobble = 0
        if p > .15 then wobble = math.max(0, 1 - (p - .15) / .25) end
        local tail = p > .6 and math.min(1, (p - .6) / .4) or 0
        return 1 + inv * inv * (.45 + intensity * .15), 1 - tail * tail,
            math.sin(age * 55) * intensity * 2.5 * wobble, inv * inv * (12 + intensity * 6), done
    elseif anim == "rise" then
        local tail = p > .6 and math.min(1, (p - .6) / .4) or 0
        return 1 + intensity * .04 * math.sin(math.min(1, p * 4) * math.pi), 1 - tail * tail,
            0, p * (30 + intensity * 20), done
    elseif anim == "shake" then
        local settle = (1 - p) * (1 - p)
        return 1 + (intensity * .12) * math.sin(math.min(1, p * 3) * math.pi), 1 - p * p,
            math.sin(age * 50) * intensity * 5 * settle, p * (8 + intensity * 4), done
    elseif anim == "pulse" then
        local tail = p > .7 and math.min(1, (p - .7) / .3) or 0
        return 1 + (.06 + intensity * .06) * math.abs(math.sin(p * 2 * math.pi)), 1 - tail * tail, 0, 0, done
    elseif anim == "fade" then
        local alpha = 1
        if p < .15 then alpha = p / .15
        elseif p > .65 then alpha = 1 - math.min(1, (p - .65) / .35) ^ 2 end
        return 1, math.max(0, math.min(1, alpha)), 0, 0, done
    end
    local pop = 1 + (intensity * .12) * math.sin(math.min(1, p * 3) * math.pi)
    return pop, 1 - p * p, 0, p * (18 + intensity * 12), done
end

-- Kill streak: returns count, tier. A kill within `window` seconds of the previous one
-- continues the streak; every kill starts the window anew. tier is the number of entries
-- in `steps` that are at most count (0 for the first kill).
function L.StreakStep(state, now, window, steps)
    if type(state) ~= "table" or type(now) ~= "number" or now ~= now then return 0, 0 end
    if type(window) ~= "number" or window ~= window then window = defaults.streakWindow end
    local last = state.streakLast
    if type(last) == "number" and now >= last and now - last <= window then
        state.streakCount = (state.streakCount or 0) + 1
    else
        state.streakCount = 1
    end
    state.streakLast = now
    return state.streakCount, L.StreakTier(state.streakCount, steps)
end

function L.StreakTier(count, steps)
    if type(count) ~= "number" or count ~= count then return 0 end
    if type(steps) ~= "table" then steps = defaults.streakSteps end
    local tier = 0
    for index = 1, #steps do
        local step = steps[index]
        if type(step) == "number" and step <= count then tier = tier + 1 end
    end
    return tier
end

function L.StreakText(config, tier)
    if type(tier) ~= "number" or tier ~= tier or tier < 1 then return nil end
    local values = config.streakTexts
    if not sanitizedTexts(values) then values = L.SanitizeTexts(values, "streak") end
    return values[math.min(math.floor(tier), #values)]
end

local situations = {
    dungeon = "dungeon", party = "dungeon", scenario = "dungeon", raid = "raid", pvp = "pvp", arena = "pvp",
}
function L.Situation(instanceType)
    return type(instanceType) == "string" and situations[instanceType] or "world"
end

local situationKeys = {
    world = "situationWorld", dungeon = "situationDungeon", raid = "situationRaid", pvp = "situationPvp",
}
function L.SituationAllows(config, situation, kind, classification)
    local mode = config[situationKeys[situation] or "situationWorld"]
    if mode == "off" then return false end
    if mode ~= "important" then return true end
    if kind == "kill" or kind == "streak" or kind == "proc" then return true end
    return classification == "record"
end

-- Minimum share of the own record for crit and heal output. Unknown or secret
-- values and a missing record pass.
function L.PassesThreshold(config, kind, amount, previous)
    local percent
    if kind == "crit" then percent = config.critMinPercent
    elseif kind == "heal" then percent = config.healMinPercent
    else return true end
    if type(percent) ~= "number" or percent <= 0 then return true end
    if type(previous) ~= "number" or previous ~= previous or previous <= 0 then return true end
    if type(amount) ~= "number" or amount ~= amount then return true end
    return amount >= previous * (percent / 100)
end

-- Colors each visible character from color 1 to color 2. UTF-8 characters stay whole,
-- spaces carry no color code and "|" is escaped.
function L.GradientText(text, r1, g1, b1, r2, g2, b2)
    if type(text) ~= "string" or text == "" then return "" end
    local first = sanitizeColor({r1, g1, b1}, {1, 1, 1})
    local second = sanitizeColor({r2, g2, b2}, {1, 1, 1})
    local chars, visible = {}, 0
    for char in text:gmatch("[^\128-\191][\128-\191]*") do
        chars[#chars + 1] = char
        if not char:find("^%s$") then visible = visible + 1 end
    end
    local parts, index = {}, 0
    for _, char in ipairs(chars) do
        if char:find("^%s$") then
            parts[#parts + 1] = char
        else
            local t = visible > 1 and index / (visible - 1) or 0
            index = index + 1
            parts[#parts + 1] = string.format("|cff%02x%02x%02x%s|r",
                math.floor((first[1] + (second[1] - first[1]) * t) * 255 + .5),
                math.floor((first[2] + (second[2] - first[2]) * t) * 255 + .5),
                math.floor((first[3] + (second[3] - first[3]) * t) * 255 + .5),
                char == "|" and "||" or char)
        end
    end
    return table.concat(parts)
end

function L.ProcMatch(config, spellID)
    local list = config.procTriggers
    if type(list) ~= "table" or type(spellID) ~= "number" then return nil end
    for index = 1, #list do
        local item = list[index]
        if type(item) == "table" and item.enabled ~= false and item.id == spellID then return item end
    end
    return nil
end

function L.HasProcTriggers(config)
    local list = config.procTriggers
    if type(list) ~= "table" then return false end
    for index = 1, #list do
        local item = list[index]
        if type(item) == "table" and item.enabled ~= false and type(item.id) == "number" then return true end
    end
    return false
end

-- Presets: only style and behavior keys. Texts, positions, sound choices and files stay.
local presetKeys = {
    "intensity", "maxEffects", "stackSpacing", "combine", "critGap", "streakEscalate", "recordSoundEnabled",
}
for _, kind in ipairs(kinds) do
    for _, name in ipairs({"Anim", "Duration", "Size", "Gradient", "Sound"}) do
        presetKeys[#presetKeys + 1] = kind .. name
    end
    if kind == "kill" or kind == "streak" or kind == "proc" then presetKeys[#presetKeys + 1] = kind .. "Flash" end
end
L.PresetKeys = presetKeys

local function buildPreset(spec)
    local values = {}
    for _, key in ipairs(presetKeys) do values[key] = deepCopy(defaults[key]) end
    for key, value in pairs(spec) do values[key] = value end
    return values
end

local minimal = {intensity = 1, maxEffects = 1, combine = true, critGap = .5, streakEscalate = false,
    recordSoundEnabled = false}
local action = {intensity = 3, maxEffects = 4, recordSoundEnabled = true,
    critAnim = "shake", killAnim = "slam", streakAnim = "slam", procAnim = "pulse", healAnim = "rise",
    critSize = 1.15, killSize = 1.25, streakSize = 1.6, procSize = 1.3, streakDuration = 1.9,
    killFlash = true, streakFlash = true, procFlash = true,
    killGradient = true, streakGradient = true, procGradient = true}
for _, kind in ipairs(kinds) do
    minimal[kind .. "Anim"], minimal[kind .. "Sound"] = "fade", false
    minimal[kind .. "Size"] = kind == "streak" and 1 or .8
    minimal[kind .. "Duration"] = kind == "streak" and 1 or .7
    minimal[kind .. "Gradient"] = false
    if kind == "kill" or kind == "streak" or kind == "proc" then minimal[kind .. "Flash"] = false end
    action[kind .. "Sound"] = true
end
L.Presets = {minimal = buildPreset(minimal), standard = buildPreset({}), action = buildPreset(action)}
local presetOrder = {"minimal", "standard", "action"}

function L.ApplyPreset(config, name)
    local preset = L.Presets[name]
    if type(config) ~= "table" or not preset then return nil end
    for key, value in pairs(preset) do config[key] = deepCopy(value) end
    return config
end

local function sameValue(a, b)
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-9 end
    return a == b
end

function L.PresetOf(config)
    if type(config) ~= "table" then return "custom" end
    for _, name in ipairs(presetOrder) do
        local matches = true
        for key, value in pairs(L.Presets[name]) do
            if not sameValue(config[key], value) then matches = false break end
        end
        if matches then return name end
    end
    return "custom"
end

-- Which events the current configuration needs. historyEnabled keeps UNIT_COMBAT alive
-- for the history even when every output is off.
-- cooldown/swing carry the built-in procs (Windfury) and the test of the spell recording; spellcast also
-- carries Stormstrike (anchor of the weapon) and the own totem casts (guard of the totem).
function L.Needs(config, historyEnabled, capture, class)
    local history = historyEnabled == true
    local capturing = capture == true
    if config.enabled == false then
        return {unitCombat = history, partyKill = false, spellcast = capturing, cooldown = capturing, swing = capturing}
    end
    local watchWeapon, watchTotem = NS.Procs.Watches(class, config)
    local watching = watchWeapon or watchTotem
    local chat = config.chatEnabled == true
    local unitCombat = history or config.critGraphics == true or config.critSound == true
        or config.recordSoundEnabled == true or config.lowCritEnabled == true
        or config.healGraphics == true or config.healSound == true
        or config.healRecordSoundEnabled == true or config.healLowEnabled == true
        or (chat and (config.chatCrit == true or config.chatRecord == true or config.chatLow == true
            or config.chatHeal == true or config.chatHealRecord == true or config.chatHealLow == true))
    local partyKill = config.killGraphics == true or config.killSound == true
        or config.streakGraphics == true or config.streakSound == true
        or (chat and config.chatKill == true)
    local spellcast = capturing or watching
        or (L.HasProcTriggers(config) and (config.procGraphics == true or config.procSound == true))
    return {unitCombat = unitCombat, partyKill = partyKill, spellcast = spellcast,
        cooldown = capturing or watching, swing = capturing or watching}
end
