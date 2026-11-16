local _, NS = ...
local T, I = NS.Theme, NS.Locale
local function tr(value) return I.Text(value) end
-- Procs page: own spell triggers, class hint and the recording of the ZenialDevLogger.
local Page = {}
NS.UIPageProcs = Page

local ROW, MAX_TRIGGERS, MAX_ID, MAX_TEXT = 34, 10, 9999999, 40
local SUMMARY_SPELLS = 8

local function charCount(text) return #(text:gsub("[\128-\191]", "")) end

-- Keeps whole UTF-8 characters.
local function truncate(text, limit)
    if charCount(text) <= limit then return text end
    local count, last = 0, 0
    for position, char in text:gmatch("()([^\128-\191][\128-\191]*)") do
        count = count + 1
        if count > limit then break end
        last = position + #char - 1
    end
    return text:sub(1, last)
end

-- Text of a trigger taken over from the spell list: the spell name in capitals plus "!".
local function triggerText(name)
    if type(name) ~= "string" then return "PROC!" end
    name = name:gsub("%c", ""):match("^%s*(.-)%s*$")
    if name == "" then return "PROC!" end
    return truncate(NS.UIForm.Upper(name), MAX_TEXT - 1) .. "!"
end
Page.TriggerText = triggerText

-- A row of the working copy: {enabled, idText, text}. Returns the numeric id, the trimmed text.
local function parseRow(item)
    local id
    if type(item.idText) == "string" and item.idText:match("^%d+$") then
        id = tonumber(item.idText)
        if id < 1 or id > MAX_ID then id = nil end
    end
    local text = type(item.text) == "string" and item.text:gsub("%c", ""):match("^%s*(.-)%s*$") or ""
    if text == "" or charCount(text) > MAX_TEXT then text = nil end
    return id, text
end

local function signature(list)
    local parts = {}
    for _, item in ipairs(list) do parts[#parts + 1] = tostring(item.id) .. "|" .. tostring(item.text) .. "|" .. tostring(item.enabled ~= false) end
    return table.concat(parts, ";")
end

function Page.Build(view, form)
    local app, api = view.app, view.api
    local page = view.pages.procs
    local work, workProfile          -- working copy: unfinished rows live only here
    local rowFrames = {}
    view.procRowFrames = rowFrames

    -- Entries of the working copy that may be saved (valid, first use of an id).
    local function validList()
        local list, seen = {}, {}
        for _, item in ipairs(work) do
            local id, text = parseRow(item)
            if id and text and not seen[id] and #list < MAX_TRIGGERS then
                seen[id] = true
                list[#list + 1] = {id = id, text = text, enabled = item.enabled ~= false}
            end
        end
        return list
    end
    local function loadFromDb()
        work, workProfile = {}, app.profile
        for _, item in ipairs(app.db.procTriggers or {}) do
            work[#work + 1] = {enabled = item.enabled ~= false, idText = tostring(item.id), text = item.text}
        end
    end
    -- Drafts survive refreshes; any other change of the stored list (profile, preset, reset) replaces the copy.
    local function ensure()
        if not work or workProfile ~= app.profile or signature(validList()) ~= signature(app.db.procTriggers or {}) then loadFromDb() end
        return work
    end
    local function commit()
        app.db.procTriggers = validList()
        app:Changed()
    end
    local function releaseFields()
        for _, rf in ipairs(rowFrames) do
            for _, edit in ipairs({rf.id, rf.text}) do
                if edit:HasFocus() then edit:ClearFocus() end
            end
        end
    end

    local function logger()
        local l = api.env.ZenialDevLogger
        if type(l) == "table" and type(l.StartProc) == "function" and type(l.Stop) == "function" and type(l.ProcSummary) == "function" then return l end
    end
    local function running()
        local l = logger()
        return l ~= nil and l.running == true and l.mode == "proc"
    end
    local function summary()
        local l = logger()
        if not l or running() then return nil end
        local ok, result = pcall(l.ProcSummary)
        if ok and type(result) == "table" and type(result.swings) == "number" then return result end
    end

    form:Card("Own triggers")
    form:Note({text = "Shows a text when you cast the spell with this ID."})
    local list = form:Custom({keys = {"procTriggers"},
        height = function() return math.max(8, #ensure() * ROW + 4) end,
        refresh = function(frame)
            local entries = ensure()
            local kit = view.kit
            local seen = {}
            for index, item in ipairs(entries) do
                local rf = rowFrames[index]
                if not rf then
                    rf = api:Frame("Frame", nil, frame)
                    rf:SetSize(608, ROW)
                    rf.check = api:Frame("CheckButton", nil, rf, "UICheckButtonTemplate")
                    rf.check:SetSize(24, 24); rf.check:SetPoint("TOPLEFT", 0, -5)
                    if T then T.StyleCheckbox(rf.check) end
                    rf.check:SetScript("OnClick", function(box)
                        work[rf.index].enabled = box:GetChecked() == true; commit()
                    end)
                    rf.id = kit.editBox(rf, 30, -5, 80, 24, false); rf.id:SetMaxLetters(7)
                    rf.spell = kit.label(rf, "", 118, -10, 130, "GameFontHighlightSmall", "muted")
                    rf.spell:SetHeight(14)
                    rf.text = kit.editBox(rf, 252, -5, 200, 24, false); rf.text:SetMaxLetters(MAX_TEXT)
                    rf.remove = kit.button(rf, "Remove", 462, -4, 100, function()
                        -- A field of the list may still hold focus: it saves first, never after the removal.
                        releaseFields()
                        if work[rf.index] then table.remove(work, rf.index); commit() end
                    end)
                    rf.remove:SetHeight(26)
                    for _, edit in ipairs({rf.id, rf.text}) do
                        edit:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
                        edit:SetScript("OnEditFocusLost", function()
                            local item = work and work[rf.index]
                            if not item then return end
                            item.idText, item.text = rf.id:GetText(), rf.text:GetText()
                            commit()
                        end)
                    end
                    rowFrames[index] = rf
                end
                rf.index = index
                rf:ClearAllPoints(); rf:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(index - 1) * ROW)
                rf.check:SetChecked(item.enabled ~= false)
                if not rf.id:HasFocus() then rf.id:SetText(item.idText or "") end
                if not rf.text:HasFocus() then rf.text:SetText(item.text or "") end
                local id = parseRow(item)
                local name, key = "", "dim"
                if id then
                    if seen[id] then name, key = tr("This ID is already used."), "warning"
                    else name = api:SpellName(id) or tr("Unknown spell") end
                    seen[id] = true
                end
                rf.spell:SetText(name)
                if T then T.Tint(rf.spell, "SetTextColor", key) end
                rf:Show()
            end
            for index = #entries + 1, #rowFrames do rowFrames[index]:Hide() end
        end})
    view.procList = list
    form:Buttons({{text = "Add trigger", visible = function() return #ensure() < MAX_TRIGGERS end, onClick = function()
        local entries = ensure()
        entries[#entries + 1] = {enabled = true, idText = "", text = "PROC!"}
        page.refresh()
    end}})
    local spellLog = app.spellLog
    local function used(id)
        for _, item in ipairs(ensure()) do
            if parseRow(item) == id then return true end
        end
        return false
    end
    local function useSpell(id)
        local entries = ensure()
        if used(id) or #entries >= MAX_TRIGGERS then return end
        entries[#entries + 1] = {enabled = true, idText = tostring(id), text = triggerText(api:SpellName(id))}
        commit()
    end
    form:Buttons({{text = function() return spellLog.active and "Stop recording my spells" or "Record my spells" end,
        onClick = function()
            if spellLog.active then app:SetSpellCapture(false)
            else app:ClearSpellLog(); app:SetSpellCapture(true) end
        end}})
    form:Note({text = "Turn this on, fight for a moment and pick the spell below. You need no ID."})
    form:Note({text = function() return spellLog.active and #spellLog.list == 0 and "Nothing cast yet." or "" end})
    local spellRows = {}
    view.procSpellRows = spellRows
    local spellList = form:Custom({visible = function() return #spellLog.list > 0 end,
        height = function() return #spellLog.list * ROW + 4 end,
        refresh = function(frame)
            local kit = view.kit
            for index, entry in ipairs(spellLog.list) do
                local rf = spellRows[index]
                if not rf then
                    rf = api:Frame("Frame", nil, frame)
                    rf:SetSize(608, ROW)
                    rf.name = kit.label(rf, "", 0, -10, 230, "GameFontHighlightSmall")
                    rf.name:SetHeight(14)
                    rf.info = kit.label(rf, "", 240, -10, 210, "GameFontHighlightSmall", "muted")
                    rf.info:SetHeight(14)
                    rf.use = kit.button(rf, "Use", 462, -4, 140, function() if rf.spellID then useSpell(rf.spellID) end end)
                    rf.use:SetHeight(26)
                    spellRows[index] = rf
                end
                rf.index, rf.spellID = index, entry.id
                rf:ClearAllPoints(); rf:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(index - 1) * ROW)
                rf.name:SetText(api:SpellName(entry.id) or tr("Unknown spell"))
                rf.info:SetText(string.format("ID %d \194\183 \195\151%d", entry.id, entry.count))
                if T then T.Tint(rf.info, "SetTextColor", "dim") end
                local taken = used(entry.id)
                rf.use:SetText(taken and tr("Already a trigger") or tr("Use"))
                rf.use:SetEnabled(not taken and #ensure() < MAX_TRIGGERS)
                rf:Show()
            end
            for index = #spellLog.list + 1, #spellRows do spellRows[index]:Hide() end
        end})
    view.procSpellList = spellList
    form:Note({text = function()
        return #spellLog.list > 0 and "A proc that shows up here as its own entry can be used as a trigger." or ""
    end})
    form:Toggle({key = "procGraphics", label = "Show text"})
    form:Toggle({key = "procSound", label = "Play sound"})

    form:Card("Class procs")
    form:Note({text = function()
        if api:PlayerClass() == "SHAMAN" then
            return "Windfury cannot be recognized reliably yet. Record your spells above while you fight with Windfury: if it shows up as its own entry, it can be used."
        end
        return "No proc of your class can be recognized reliably yet."
    end})

    form:Card("Recording")
    form:Note({advanced = true, text = "Records what happens while you fight, so a proc can be identified afterwards."})
    form:Note({advanced = true, tone = "warning", text = function() return logger() and "" or "Needs the addon ZenialDevLogger." end})
    local controls = form:Buttons({
        {text = "Start (3 minutes)", visible = function() return logger() ~= nil and not running() end, onClick = function()
            local l = logger(); if l then pcall(l.StartProc, 180) end
            page.refresh()
        end},
        {text = "Stop", visible = running, onClick = function()
            local l = logger(); if l then pcall(l.Stop) end
            page.refresh()
        end},
    })
    controls.spec.advanced = true
    form:Note({advanced = true, text = function() return running() and "Recording is running." or "" end})
    form:Note({advanced = true, text = function()
        local s = summary()
        if not s then return "" end
        return "%d melee swings, %d of them with several hits", s.swings, tonumber(s.candidates) or 0
    end})
    form:Note({advanced = true, text = function()
        local s = summary()
        if not s or type(s.spells) ~= "table" or #s.spells == 0 then return "" end
        local parts = {}
        for index = 1, math.min(SUMMARY_SPELLS, #s.spells) do
            local spell = s.spells[index]
            parts[#parts + 1] = string.format("%s (%s) \195\151%s", tostring(spell.name or "?"), tostring(spell.id or "?"), tostring(spell.count or 0))
        end
        return "Spells you cast: %s", table.concat(parts, ", ")
    end})
    form:Note({advanced = true, text = function() return summary() and "Type /reload so the recording is saved." or "" end})

    -- The status line and the spell list follow a running recording once a second, only while this page is shown.
    local ticker = api:Frame("Frame", nil, form.parent)
    local elapsedTotal = 0
    local function onUpdate(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal >= 1 then elapsedTotal = 0; page.refresh() end
    end
    local function attach()
        elapsedTotal = 0
        ticker:SetScript("OnUpdate", (running() or spellLog.active) and view.page == "procs" and onUpdate or nil)
    end
    page.afterRefresh = attach
    page.onHide = function() ticker:SetScript("OnUpdate", nil) end
    view.procTicker = ticker
end
