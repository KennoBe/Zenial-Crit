local addonName, NS = ...

local S = {}
NS.Sounds = S

local mediaRoot = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local customRoot = "Interface\\ZenialSounds\\"

local builtinFiles = {
    pop = "pop.wav", impact = "impact.wav", arcade = "arcade.wav",
    finisher = "finisher.wav", jackpot = "jackpot.wav", laser = "laser.wav",
    tada = "tada.wav", doom = "doom.wav", bonk = "bonk.wav",
    klong = "klong.wav", punch = "punch.wav", squeak = "squeak.wav",
    bruh = "bruh.wav", womp = "womp.wav", gameover = "gameover.wav",
    fall = "fall.wav", meme_bonk = "meme_bonk.mp3",
    meme_bowomp = "meme_bowomp.mp3", meme_bruh = "meme_bruh.mp3",
    meme_oof = "meme_oof.mp3",
}

local labels = {
    pop = "Pop", impact = "Impact", arcade = "Arcade", finisher = "Finisher",
    jackpot = "Jackpot", laser = "Laser", tada = "Ta-da!", doom = "Doom",
    bonk = "Bonk", klong = "Klong", punch = "Comic hit", squeak = "Squeak",
    bruh = "Bruh", womp = "Womp-womp", gameover = "Game over", fall = "Falling",
    meme_bonk = "Bonk (Meme)", meme_bowomp = "Womp (Meme)",
    meme_bruh = "Bruh (Meme)", meme_oof = "Oof (Meme)",
    critmix = "Crit mix (weighted)", killmix = "Kill mix (weighted)",
}
-- Only these display names are words; the rest are proper names/onomatopoeia.
-- Sound IDs and files never change with the locale.
local translatable = { punch = true, squeak = true, gameover = true, fall = true, critmix = true, killmix = true }
local function label(id)
    local text = labels[id]
    if text and translatable[id] and NS.Locale then return NS.Locale.Text(text) end
    return text
end

local critPool = {
    "bonk", "bonk", "bonk", "klong", "klong", "klong",
    "punch", "punch", "squeak", "meme_bonk",
}
local killPool = {
    "bruh", "bruh", "bruh", "bruh", "gameover", "gameover", "womp",
    "fall", "tada", "doom", "meme_bruh", "meme_oof", "meme_bowomp",
}

local categoryKeys = {
    crit = { mode = "critSoundMode", ids = "critSoundIDs" },
    heal = { mode = "healSoundMode", ids = "healSoundIDs" },
    kill = { mode = "killSoundMode", ids = "killSoundIDs" },
    record = { mode = "recordSoundMode", ids = "recordSoundIDs" },
    healRecord = { mode = "healRecordSoundMode", ids = "healRecordSoundIDs" },
    low = { mode = "lowSoundMode", ids = "lowSoundIDs" },
    healLow = { mode = "healLowSoundMode", ids = "healLowSoundIDs" },
}
S.CategoryKeys = categoryKeys

local function copyArray(value)
    local result = {}
    if type(value) == "table" then
        for i = 1, #value do result[#result + 1] = value[i] end
    end
    return result
end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function safeName(value)
    value = trim(value):gsub("[%c]", "")
    if #value > 60 then value = value:sub(1, 60) end
    return value
end

function S.NormalizeFile(value)
    value = trim(value):gsub("/", "\\")
    if value == "" or #value > 160 then return nil, "Filename is missing or too long." end
    if value:find(":", 1, true) or value:sub(1, 1) == "\\" or value:find("..", 1, true) then
        return nil, "Only a relative filename below Interface\\ZenialSounds is allowed."
    end
    if value:find("[%c%*%?%\"%<%>%|]") then return nil, "The filename contains invalid characters." end
    local ext = value:match("%.([^.\\]+)$")
    ext = ext and ext:lower() or ""
    if ext ~= "mp3" and ext ~= "ogg" and ext ~= "wav" then
        return nil, "MP3, OGG and WAV are supported."
    end
    return value
end

function S.SanitizeCustom(value, nextID)
    local result, seen = {}, {}
    local highest = tonumber(nextID) or 1
    if type(value) == "table" then
        for i = 1, math.min(#value, 50) do
            local item = value[i]
            if type(item) == "table" then
                local id = type(item.id) == "string" and item.id or ""
                local numeric = tonumber(id:match("^custom:(%d+)$"))
                local name = safeName(item.name)
                local file = S.NormalizeFile(item.file)
                if numeric and name ~= "" and file and not seen[id] then
                    result[#result + 1] = { id = id, name = name, file = file }
                    seen[id] = true
                    if numeric >= highest then highest = numeric + 1 end
                end
            end
        end
    end
    return result, math.max(1, math.floor(highest))
end

function S.CustomByID(config, id)
    local entries = config and config.customSounds
    if type(entries) ~= "table" then return nil end
    for i = 1, #entries do
        if entries[i].id == id then return entries[i], i end
    end
    return nil
end

local function getSharedMedia(env)
    if type(env) ~= "table" or (type(env.LibStub) ~= "function" and type(env.LibStub) ~= "table") then return nil end
    local ok, media = pcall(env.LibStub, "LibSharedMedia-3.0", true)
    if ok and type(media) == "table" then return media end
    return nil
end

local function sharedPath(env, name)
    local media = getSharedMedia(env)
    if not media or type(media.Fetch) ~= "function" then return nil end
    local ok, path = pcall(media.Fetch, media, "sound", name, true)
    if ok and type(path) == "string" and path ~= "" then return path end
    return nil
end

function S.IsKnownRef(config, id, env, keepMissing)
    if builtinFiles[id] or id == "critmix" or id == "killmix" then return true end
    if type(id) ~= "string" then return false end
    if id:match("^custom:") then return S.CustomByID(config, id) ~= nil end
    if id:match("^shared:") then return keepMissing or sharedPath(env, id:sub(8)) ~= nil end
    return false
end

function S.SanitizeIDs(value, fallback, config)
    local result, seen = {}, {}
    if type(value) == "string" then value = { value } end
    if type(value) == "table" then
        for i = 1, math.min(#value, 30) do
            local id = value[i]
            if type(id) == "string" and not seen[id]
                and S.IsKnownRef(config, id, nil, true) then
                result[#result + 1] = id
                seen[id] = true
            end
        end
    end
    if #result == 0 and fallback then result[1] = fallback end
    return result
end

function S.Catalog(config, env)
    local result = {}
    local ordered = {
        "pop", "impact", "arcade", "finisher", "jackpot", "laser", "tada", "doom",
        "bonk", "klong", "punch", "squeak", "bruh", "womp", "gameover", "fall",
        "meme_bonk", "meme_bowomp", "meme_bruh", "meme_oof", "critmix", "killmix",
    }
    for i = 1, #ordered do
        local id = ordered[i]
        result[#result + 1] = { id = id, name = label(id), source = "builtin", available = true }
    end
    local custom = config and config.customSounds or {}
    for i = 1, #custom do
        result[#result + 1] = {
            id = custom[i].id, name = custom[i].name, source = "custom",
            file = custom[i].file, available = true,
        }
    end
    local media = getSharedMedia(env)
    if media and type(media.List) == "function" then
        local ok, list = pcall(media.List, media, "sound")
        if ok and type(list) == "table" then
            for i = 1, #list do
                local name = list[i]
                if type(name) == "string" and name ~= "" then
                    result[#result + 1] = {
                        id = "shared:" .. name, name = name, source = "shared", available = true,
                    }
                end
            end
        end
    end
    return result
end

function S.Describe(config, id, env)
    if labels[id] then return label(id), true, "builtin" end
    local custom = S.CustomByID(config, id)
    if custom then return custom.name, true, "custom" end
    if type(id) == "string" and id:match("^shared:") then
        local name = id:sub(8)
        return name, sharedPath(env, name) ~= nil, "shared"
    end
    return tostring(id or "?"), false, "missing"
end

local function randomIndex(random, maximum)
    if maximum <= 1 then return 1 end
    local ok, value = pcall(random or math.random, 1, maximum)
    if ok and type(value) == "number" then return math.max(1, math.min(maximum, math.floor(value))) end
    return 1
end

function S.ResolveRef(config, id, env, random)
    if id == "critmix" or id == "killmix" then
        local pool = id == "critmix" and critPool or killPool
        local picked = pool[randomIndex(random, #pool)]
        return mediaRoot .. builtinFiles[picked], picked
    end
    if builtinFiles[id] then return mediaRoot .. builtinFiles[id], id end
    local custom = S.CustomByID(config, id)
    if custom then return customRoot .. custom.file, id end
    if type(id) == "string" and id:match("^shared:") then return sharedPath(env, id:sub(8)), id end
    return nil, id
end

function S.Candidates(config, category, env, random, lastID, failed)
    local keys = categoryKeys[category]
    if not keys then return {} end
    local ids = copyArray(config[keys.ids])
    if config[keys.mode] ~= "mix" and #ids > 1 then ids = { ids[1] } end
    if #ids > 1 then
        for i = #ids, 2, -1 do
            local j = randomIndex(random, i)
            ids[i], ids[j] = ids[j], ids[i]
        end
        if ids[1] == lastID then ids[1], ids[#ids] = ids[#ids], ids[1] end
    end
    local result = {}
    for i = 1, #ids do
        local id = ids[i]
        if not failed or not failed[id] then
            local path, playedID = S.ResolveRef(config, id, env, random)
            if path then result[#result + 1] = { id = id, playedID = playedID, path = path } end
        end
    end
    return result
end

function S.AddOrUpdate(config, name, file, editID)
    name = safeName(name)
    if name == "" then return nil, "Display name is missing." end
    local normalized, err = S.NormalizeFile(file)
    if not normalized then return nil, err end
    local existing, index = editID and S.CustomByID(config, editID) or nil
    if existing then
        config.customSounds[index] = { id = existing.id, name = name, file = normalized }
        return existing.id
    end
    if #config.customSounds >= 50 then return nil, "At most 50 own sounds are supported." end
    local id = "custom:" .. tostring(config.customSoundNextID or 1)
    config.customSoundNextID = (config.customSoundNextID or 1) + 1
    config.customSounds[#config.customSounds + 1] = { id = id, name = name, file = normalized }
    return id
end

function S.UsedBy(config, id)
    local result = {}
    for category, keys in pairs(categoryKeys) do
        local ids = config[keys.ids] or {}
        for i = 1, #ids do
            if ids[i] == id then result[#result + 1] = category break end
        end
    end
    table.sort(result)
    return result
end

function S.Remove(config, id)
    local _, index = S.CustomByID(config, id)
    if not index then return false end
    table.remove(config.customSounds, index)
    for _, keys in pairs(categoryKeys) do
        local ids, kept = config[keys.ids] or {}, {}
        for i = 1, #ids do if ids[i] ~= id then kept[#kept + 1] = ids[i] end end
        config[keys.ids] = kept
    end
    return true
end
