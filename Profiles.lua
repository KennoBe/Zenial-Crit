local _, NS = ...
-- Profile root of ZenialCritDB. Pure data, no WoW API.
local P = {}
NS.Profiles = P

local DEFAULT_NAME = "Standard"
local MAX_PROFILES, MAX_CHARS, MAX_NAME = 12, 200, 24
local SCHEMA = NS.Logic.Defaults().schema
P.DefaultName, P.MaxProfiles, P.MaxNameLength = DEFAULT_NAME, MAX_PROFILES, MAX_NAME

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

local function cleanName(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%c]", ""):match("^%s*(.-)%s*$") or ""
    return value ~= "" and value or nil
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local la, lb = a:lower(), b:lower()
        if la ~= lb then return la < lb end
        return a < b
    end)
    return keys
end

function P.Names(root)
    local names = {}
    if type(root) ~= "table" or type(root.profiles) ~= "table" then return names end
    local hasDefault = root.profiles[DEFAULT_NAME] ~= nil
    if hasDefault then names[1] = DEFAULT_NAME end
    for _, name in ipairs(sortedKeys(root.profiles)) do
        if name ~= DEFAULT_NAME then names[#names + 1] = name end
    end
    return names
end

local function fallbackName(root)
    local names = P.Names(root)
    return names[1]
end

function P.SanitizeRoot(input)
    local profiles = {}
    local source = type(input) == "table" and input or {}
    if type(source.profiles) == "table" then
        local candidates = {}
        for rawName, config in pairs(source.profiles) do
            local name = cleanName(rawName)
            if name and type(config) == "table" then
                name = truncate(name, MAX_NAME)
                local previous = candidates[name]
                -- Names that collide after cleaning: keep the one with the smaller raw key.
                if not previous or tostring(rawName) < previous.raw then
                    candidates[name] = {raw = tostring(rawName), config = config}
                end
            end
        end
        local count = 0
        local names = sortedKeys(candidates)
        if candidates[DEFAULT_NAME] then table.insert(names, 1, DEFAULT_NAME) end
        for index, name in ipairs(names) do
            if not (index > 1 and name == DEFAULT_NAME) and count < MAX_PROFILES then
                profiles[name] = NS.Logic.Sanitize(candidates[name].config)
                count = count + 1
            end
        end
    elseif next(source) ~= nil then
        -- Flat table from 1.9.1 or older.
        profiles[DEFAULT_NAME] = NS.Logic.Sanitize(source)
    end
    if next(profiles) == nil then profiles[DEFAULT_NAME] = NS.Logic.Sanitize({}) end
    local root = {schema = SCHEMA, profiles = profiles, chars = {}, advanced = source.advanced == true}
    local rawChars, count = type(source.chars) == "table" and source.chars or {}, 0
    local keys = {}
    for key, value in pairs(rawChars) do
        if type(key) == "string" and key ~= "" and type(value) == "string" and profiles[value] then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        if count >= MAX_CHARS then break end
        root.chars[key] = rawChars[key]
        count = count + 1
    end
    local last = source.last
    root.last = type(last) == "string" and profiles[last] and last or fallbackName(root)
    return root
end

-- Active profile for a character. Without an assignment the character gets "Standard"
-- (or the first profile); without a key the last used profile applies.
function P.Resolve(root, charKey)
    if type(root) ~= "table" or type(root.profiles) ~= "table" then return nil end
    local name
    if type(charKey) == "string" and charKey ~= "" then
        local assigned = type(root.chars) == "table" and root.chars[charKey] or nil
        if type(assigned) == "string" and root.profiles[assigned] then name = assigned end
        if not name then name = root.profiles[DEFAULT_NAME] and DEFAULT_NAME or fallbackName(root) end
    else
        local last = root.last
        if type(last) == "string" and root.profiles[last] then name = last
        else name = root.profiles[DEFAULT_NAME] and DEFAULT_NAME or fallbackName(root) end
    end
    if not name then return nil end
    return name, root.profiles[name]
end

function P.Assign(root, charKey, name)
    if type(root) ~= "table" or type(root.profiles) ~= "table" then return false, "Invalid profile data." end
    if type(charKey) ~= "string" or charKey == "" then return false, "Character is unknown." end
    if type(name) ~= "string" or not root.profiles[name] then return false, "Profile not found." end
    root.chars = type(root.chars) == "table" and root.chars or {}
    if root.chars[charKey] == nil then
        local count = 0
        for _ in pairs(root.chars) do count = count + 1 end
        if count >= MAX_CHARS then return false, "Too many characters are assigned." end
    end
    root.chars[charKey] = name
    return true
end

function P.Create(root, name, sourceName)
    if type(root) ~= "table" or type(root.profiles) ~= "table" then return nil, "Invalid profile data." end
    name = cleanName(name)
    if not name then return nil, "Enter a profile name." end
    if charLength(name) > MAX_NAME then return nil, "The profile name is too long (at most 24 characters)." end
    if root.profiles[name] then return nil, "A profile with this name already exists." end
    local count = 0
    for _ in pairs(root.profiles) do count = count + 1 end
    if count >= MAX_PROFILES then return nil, "At most 12 profiles are supported." end
    local source = {}
    if sourceName ~= nil then
        source = type(sourceName) == "string" and root.profiles[sourceName] or nil
        if not source then return nil, "Source profile not found." end
    end
    -- Sanitize returns a fully independent copy.
    root.profiles[name] = NS.Logic.Sanitize(source)
    return name
end

function P.Delete(root, name)
    if type(root) ~= "table" or type(root.profiles) ~= "table" then return nil, "Invalid profile data." end
    if type(name) ~= "string" or not root.profiles[name] then return nil, "Profile not found." end
    local count = 0
    for _ in pairs(root.profiles) do count = count + 1 end
    if count <= 1 then return nil, "The last profile cannot be deleted." end
    root.profiles[name] = nil
    local fallback = fallbackName(root)
    root.chars = type(root.chars) == "table" and root.chars or {}
    for key, assigned in pairs(root.chars) do
        if assigned == name then root.chars[key] = fallback end
    end
    if root.last == name or not root.profiles[root.last or ""] then root.last = fallback end
    return true, fallback
end
