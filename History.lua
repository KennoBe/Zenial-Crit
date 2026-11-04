local _, NS = ...
local H = {}
NS.History = H

local MAX_ENTRIES = 100
local MAX_AMOUNT = 999999999999

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function text(value, limit)
    if type(value) ~= "string" then return "" end
    value = value:gsub("[%c]", ""):match("^%s*(.-)%s*$") or ""
    return value:sub(1, limit or 80)
end

local function entry(value)
    if type(value) ~= "table" or not finite(value.amount) or value.amount <= 0
        or not finite(value.at) or value.at < 1 then return nil end
    local amount = math.floor(math.min(value.amount, MAX_AMOUNT) + .5)
    local at = math.floor(value.at)
    local id = finite(value.id) and math.max(1, math.floor(value.id)) or at
    return {
        id = id, amount = amount, at = at,
        school = finite(value.school) and math.max(0, math.min(127, math.floor(value.school))) or 0,
        target = text(value.target, 80), zone = text(value.zone, 80),
        subzone = text(value.subzone, 80),
    }
end

local function newer(a, b)
    if a.at ~= b.at then return a.at > b.at end
    return a.id > b.id
end

local function higher(a, b)
    if a.amount ~= b.amount then return a.amount > b.amount end
    return newer(a, b)
end

local function sanitizeList(values, sorter)
    local result = {}
    if type(values) == "table" then
        for index = 1, math.min(#values, MAX_ENTRIES) do
            local clean = entry(values[index])
            if clean then result[#result + 1] = clean end
        end
    end
    table.sort(result, sorter)
    while #result > MAX_ENTRIES do table.remove(result) end
    return result
end

local function listFields(kind)
    if kind == "heal" then return "healTop", "healRecent", "healRecords" end
    return "top", "recent", "records"
end

local function sanitizeRecords(values)
    local result = {}
    if type(values) == "table" then
        for rawSchool, amount in pairs(values) do
            local school = tonumber(rawSchool)
            if finite(school) and finite(amount) and amount > 0 then
                result[tostring(math.max(0, math.min(127, math.floor(school))))] =
                    math.floor(math.min(amount, MAX_AMOUNT) + .5)
            end
        end
    end
    return result
end

function H.Sanitize(input)
    input = type(input) == "table" and input or {}
    local result = {
        schema = 4,
        enabled = input.enabled ~= false,
        nextID = finite(input.nextID) and math.max(1, math.floor(input.nextID)) or 1,
        characters = {},
    }
    local highestID = 0
    if type(input.characters) == "table" then
        for rawKey, value in pairs(input.characters) do
            local key = text(rawKey, 128)
            if key ~= "" and type(value) == "table" then
                local bucket = {
                    name = text(value.name, 96),
                    top = sanitizeList(value.top, higher),
                    recent = sanitizeList(value.recent, newer),
                    records = sanitizeRecords(value.records),
                    healTop = sanitizeList(value.healTop, higher),
                    healRecent = sanitizeList(value.healRecent, newer),
                    healRecords = sanitizeRecords(value.healRecords),
                }
                for _, list in ipairs({bucket.top, bucket.recent, bucket.healTop, bucket.healRecent}) do
                    for _, saved in ipairs(list) do highestID = math.max(highestID, saved.id) end
                end
                -- Version 2 had no per-school comparison records. Build them from
                -- both retained lists so a pre-existing best value is never lost.
                for _, list in ipairs({bucket.top, bucket.recent}) do
                    for _, saved in ipairs(list) do
                        local school = tostring(saved.school)
                        bucket.records[school] = math.max(bucket.records[school] or 0, saved.amount)
                    end
                end
                for _, list in ipairs({bucket.healTop, bucket.healRecent}) do
                    for _, saved in ipairs(list) do
                        local school = tostring(saved.school)
                        bucket.healRecords[school] = math.max(bucket.healRecords[school] or 0, saved.amount)
                    end
                end
                result.characters[key] = bucket
            end
        end
    end
    result.nextID = math.max(result.nextID, highestID + 1)
    return result
end

function H.SetEnabled(store, enabled)
    if type(store) ~= "table" then return false end
    store.enabled = enabled == true
    return store.enabled
end

function H.Record(store, key, characterName, value, kind)
    if type(store) ~= "table" or store.enabled ~= true then return false end
    key = text(key, 128)
    local clean = entry(value)
    if key == "" or not clean then return false end
    clean.id = finite(store.nextID) and math.max(1, math.floor(store.nextID)) or 1
    store.nextID = clean.id + 1
    store.characters = type(store.characters) == "table" and store.characters or {}
    local bucket = store.characters[key]
    if type(bucket) ~= "table" then
        bucket = {name = "", top = {}, recent = {}, records = {}, healTop = {}, healRecent = {}, healRecords = {}}
        store.characters[key] = bucket
    end
    bucket.name = text(characterName, 96)
    local topField, recentField, recordsField = listFields(kind)
    bucket[topField] = type(bucket[topField]) == "table" and bucket[topField] or {}
    bucket[recentField] = type(bucket[recentField]) == "table" and bucket[recentField] or {}
    bucket[recordsField] = type(bucket[recordsField]) == "table" and bucket[recordsField] or {}

    bucket[recentField][#bucket[recentField] + 1] = entry(clean)
    table.sort(bucket[recentField], newer)
    while #bucket[recentField] > MAX_ENTRIES do table.remove(bucket[recentField]) end

    bucket[topField][#bucket[topField] + 1] = entry(clean)
    table.sort(bucket[topField], higher)
    while #bucket[topField] > MAX_ENTRIES do table.remove(bucket[topField]) end
    return true
end

function H.Compare(store, key, amount, school, persist, session, kind)
    if type(store) ~= "table" or type(key) ~= "string" or key == ""
        or not finite(amount) or amount <= 0 then return false, nil end
    school = finite(school) and math.max(0, math.min(127, math.floor(school))) or 0
    amount = math.floor(math.min(amount, MAX_AMOUNT) + .5)
    local schoolKey = tostring(school)
    store.characters = type(store.characters) == "table" and store.characters or {}
    local bucket = store.characters[key]
    local _, _, recordsField = listFields(kind)
    local saved = type(bucket) == "table" and type(bucket[recordsField]) == "table"
        and bucket[recordsField][schoolKey] or nil
    session[key] = type(session[key]) == "table" and session[key] or {}
    local sessionKind = kind == "heal" and "heal" or "crit"
    session[key][sessionKind] = type(session[key][sessionKind]) == "table" and session[key][sessionKind] or {}
    local temporary = session[key][sessionKind][schoolKey]
    local previous = math.max(tonumber(saved) or 0, tonumber(temporary) or 0)
    if previous <= 0 then previous = nil end
    local isRecord = previous ~= nil and amount > previous
    local nextValue = math.max(previous or 0, amount)
    session[key][sessionKind][schoolKey] = nextValue
    if persist == true then
        if type(bucket) ~= "table" then
            bucket = {name = "", top = {}, recent = {}, records = {}, healTop = {}, healRecent = {}, healRecords = {}}
            store.characters[key] = bucket
        end
        bucket[recordsField] = type(bucket[recordsField]) == "table" and bucket[recordsField] or {}
        bucket[recordsField][schoolKey] = math.max(tonumber(bucket[recordsField][schoolKey]) or 0, amount)
    end
    return isRecord, previous
end

function H.ResetSession(session, key)
    if type(session) == "table" then session[key] = nil end
end

function H.Get(store, key, list, kind)
    local bucket = type(store) == "table" and type(store.characters) == "table" and store.characters[key]
    if type(bucket) ~= "table" then return {} end
    local topField, recentField = listFields(kind)
    local values = list == "recent" and bucket[recentField] or bucket[topField]
    return type(values) == "table" and values or {}
end

function H.Best(store, key, kind)
    return H.Get(store, key, "top", kind)[1]
end

function H.Clear(store, key)
    if type(store) ~= "table" or type(store.characters) ~= "table" or type(key) ~= "string" then return false end
    if store.characters[key] == nil then return false end
    store.characters[key] = nil
    return true
end

H.MaxEntries = MAX_ENTRIES
