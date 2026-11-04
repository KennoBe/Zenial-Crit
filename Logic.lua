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
    schema = 14,
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
    critTexts = {"BAM!", "POW!", "CRIT!"},
    killTexts = {"KILL!"},
    scale = 1, nameplateScale = 1, intensity = 2, soundCooldown = .25, x = 0, y = 160,
    separatePositions = false, critX = 0, critY = 160, killX = 0, killY = 160,
    displayMode = "nameplate",
}
local bounds = {
    scale = {.6, 2.5}, nameplateScale = {.6, 4.2}, intensity = {1, 3}, soundCooldown = {0, 30},
    lowCritPercent = {1, 100}, healLowPercent = {1, 100}, customSoundNextID = {1, 1000000},
    x = {-2000, 2000}, y = {-1200, 1200},
    critX = {-2000, 2000}, critY = {-1200, 1200},
    killX = {-2000, 2000}, killY = {-1200, 1200},
}

L.FontStyles = fontStyles

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

function L.SanitizeTexts(input, kind)
    local fallback = kind == "kill" and defaults.killTexts or defaults.critTexts
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
                result[#result + 1] = value:sub(1, 40)
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
        if type(value) ~= "string" or value == "" or #value > 40 or value:find("[%c]")
            or value:find("^%s") or value:find("%s$") then return false end
    end
    return true
end

function L.PickText(config, kind, random)
    local values = kind == "kill" and config.killTexts or config.critTexts
    if not sanitizedTexts(values) then values = L.SanitizeTexts(values, kind) end
    local index = type(random) == "function" and random(#values) or math.random(#values)
    if type(index) ~= "number" or index < 1 or index > #values then index = 1 end
    return values[math.floor(index)] or values[1]
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
            if key == "critTexts" or key == "killTexts" then
                result[key] = L.SanitizeTexts(input[key], key == "killTexts" and "kill" or "crit")
            elseif key == "critColor" or key == "killColor" then
                result[key] = sanitizeColor(input[key], default)
            elseif bounds[key] then
                local value = input[key]
                if value == nil and (key == "critX" or key == "killX") then value = input.x end
                if value == nil and (key == "critY" or key == "killY") then value = input.y end
                if type(value) ~= "number" or value ~= value then value = default end
                result[key] = math.max(bounds[key][1], math.min(bounds[key][2], value))
                if key == "intensity" then result[key] = math.floor(result[key]) end
            elseif key == "critGraphics" or key == "critSound" then
                local legacy
                if key == "critGraphics" then legacy = input.graphics else legacy = input.sound end
                if type(input[key]) == "boolean" then result[key] = input[key]
                elseif type(legacy) == "boolean" then result[key] = legacy
                else result[key] = default end
            elseif key == "displayMode" then
                result[key] = (input[key] == "nameplate" or input[key] == "fixed") and input[key] or default
            elseif key == "critFont" or key == "killFont" then
                result[key] = fontStyleSet[input[key]] and input[key] or default
            elseif key == "critSoundRule" or key == "healSoundRule" then
                result[key] = input[key] == "records" and "records" or "all"
            elseif key:match("SoundChannel$") then
                local channel = input[key]
                result[key] = (channel == "Dialog" or channel == "SFX") and channel or "Master"
            elseif type(default) == "boolean" then
                if type(input[key]) == "boolean" then result[key] = input[key] else result[key] = default end
            else
                result[key] = default
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
    }
    for category, keys in pairs(NS.Sounds.CategoryKeys) do
        local mode = input[keys.mode]
        result[keys.mode] = mode == "mix" and "mix" or "single"
        local fallback = input[keys.ids] == nil and soundFallbacks[category] or nil
        result[keys.ids] = NS.Sounds.SanitizeIDs(input[keys.ids], fallback, result)
    end
    return result
end

function L.FontStyle(config, kind)
    local style = kind == "kill" and config.killFont or config.critFont
    return fontStyleSet[style] and style or "standard"
end

function L.EffectScale(config)
    if config.displayMode == "nameplate" then return (config.nameplateScale or 1) * .6 end
    return config.scale
end

function L.Color(config, kind)
    local value = kind == "kill" and config.killColor or config.critColor
    local fallback = kind == "kill" and defaults.killColor or defaults.critColor
    value = sanitizeColor(value, fallback)
    return value[1], value[2], value[3]
end

function L.Position(config, kind)
    if config.separatePositions == true then
        if kind == "kill" then return config.killX, config.killY end
        return config.critX, config.critY
    end
    return config.x, config.y
end

function L.NewState()
    return {recentKills = {}}
end

function L.Output(config, kind)
    if kind == "crit" then
        return config.critGraphics, config.critSound
    elseif kind == "kill" then
        return config.killGraphics, config.killSound
    elseif kind == "heal" then
        return false, config.healSound
    end
    return false, false, nil
end

function L.SoundCategory(config, classification, kind)
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
    if kind ~= "crit" and kind ~= "kill" and kind ~= "heal" then return false end
    if preview then return true end
    local graphics, sound = L.Output(config, kind)
    if kind == "crit" then sound = sound or config.recordSoundEnabled or config.lowCritEnabled end
    if kind == "heal" then sound = sound or config.healRecordSoundEnabled or config.healLowEnabled end
    if not graphics and not sound then return false end
    if kind == "crit" or kind == "heal" then return true end
    return kind == "kill"
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

function L.Animation(age, intensity)
    local duration = .85
    local p = math.max(0, math.min(1, age / duration))
    local pop = 1 + (intensity * .12) * math.sin(math.min(1, p * 3) * math.pi)
    return pop, 1 - p * p, p * (18 + intensity * 12), p >= 1
end
