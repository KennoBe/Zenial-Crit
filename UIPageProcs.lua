local _, NS = ...
local T, K, I = NS.Theme, NS.Kit, NS.Locale
local Form = NS.Form
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
    return truncate(Form.Upper(name), MAX_TEXT - 1) .. "!"
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

function Page.Build(view, form, page)
    local app, api = view.app, view.api
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
    local list = form:Custom({anchor = "procTriggers", keys = {"procTriggers"},
        height = function() return math.max(8, #ensure() * ROW + 4) end,
        refresh = function(frame)
            local entries = ensure()
            local seen = {}
            for index, item in ipairs(entries) do
                local rf = rowFrames[index]
                if not rf then
                    rf = api:Frame("Frame", nil, frame)
                    rf:SetHeight(ROW)
                    rf.check = api:Frame("CheckButton", nil, rf, "UICheckButtonTemplate")
                    rf.check:SetSize(24, 24); rf.check:SetPoint("TOPLEFT", 0, -5)
                    if T then T.StyleCheckbox(rf.check) end
                    rf.check:SetScript("OnClick", function(box)
                        work[rf.index].enabled = box:GetChecked() == true; commit()
                    end)
                    rf.id = Form.Edit(rf, {width = 80, maxLetters = 7, tr = tr})
                    rf.id:SetPoint("TOPLEFT", rf, "TOPLEFT", 30, -5)
                    rf.spell = K.Text(rf, "", "caption", "muted")
                    rf.spell:SetPoint("TOPLEFT", rf, "TOPLEFT", 118, -11); rf.spell:SetSize(130, 14)
                    rf.text = Form.Edit(rf, {width = 200, maxLetters = MAX_TEXT, tr = tr})
                    rf.text:SetPoint("TOPLEFT", rf, "TOPLEFT", 252, -5); rf.text:SetPoint("TOPRIGHT", rf, "TOPRIGHT", -110, -5)
                    rf.remove = T.Button(rf, tr("Remove"), 100, 26, function()
                        -- A field of the list may still hold focus: it saves first, never after the removal.
                        releaseFields()
                        if work[rf.index] then table.remove(work, rf.index); commit() end
                    end, "secondary")
                    rf.remove:SetPoint("TOPRIGHT", rf, "TOPRIGHT", 0, -4)
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
                rf:ClearAllPoints()
                rf:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(index - 1) * ROW); rf:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(index - 1) * ROW)
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
    -- Started in combat: the events are registered after the fight.
    form:Note({text = function() return spellLog.active and not spellLog.test and "Starts after the fight." or "" end})
    form:Note({text = function() return spellLog.test and #spellLog.list == 0 and "Nothing cast yet." or "" end})
    local spellRows = {}
    view.procSpellRows = spellRows
    local spellList = form:Custom({visible = function() return #spellLog.list > 0 end,
        height = function() return #spellLog.list * ROW + 4 end,
        refresh = function(frame)
            for index, entry in ipairs(spellLog.list) do
                local rf = spellRows[index]
                if not rf then
                    rf = api:Frame("Frame", nil, frame)
                    rf:SetHeight(ROW)
                    rf.name = K.Text(rf, "", "caption", "text")
                    rf.name:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, -11); rf.name:SetSize(230, 14)
                    rf.info = K.Text(rf, "", "caption", "muted")
                    rf.info:SetPoint("TOPLEFT", rf, "TOPLEFT", 240, -11); rf.info:SetSize(210, 14)
                    rf.use = T.Button(rf, tr("Use"), 140, 26, function() if rf.spellID then useSpell(rf.spellID) end end, "secondary")
                    rf.use:SetPoint("TOPRIGHT", rf, "TOPRIGHT", 0, -4)
                    spellRows[index] = rf
                end
                rf.index, rf.spellID = index, entry.id
                rf:ClearAllPoints()
                rf:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(index - 1) * ROW); rf:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(index - 1) * ROW)
                rf.name:SetText(api:SpellName(entry.id) or tr("Unknown spell"))
                -- An entry that was never cast is a possible proc: a trigger works for cast spells only.
                local cast = (entry.casts or 0) > 0
                if cast then
                    rf.info:SetText(string.format("ID %d \194\183 \195\151%d", entry.id, entry.casts))
                else
                    rf.info:SetText(string.format(tr("ID %d \194\183 \195\151%d \194\183 no cast"), entry.id, entry.cooldowns or 0))
                end
                if T then T.Tint(rf.info, "SetTextColor", "dim") end
                local taken = cast and used(entry.id)
                rf.use:SetText(taken and tr("Already a trigger") or tr("Use"))
                rf.use:SetEnabled(cast and not taken and #ensure() < MAX_TRIGGERS)
                rf.use:SetShown(cast)
                rf:Show()
            end
            for index = #spellLog.list + 1, #spellRows do spellRows[index]:Hide() end
        end})
    view.procSpellList = spellList
    form:Note({text = function()
        return #spellLog.list > 0 and "Entries without a cast are possible procs. They help to find out what can be recognized." or ""
    end})
    form:Toggle({key = "procGraphics", label = "Show text"})
    form:Toggle({key = "procSound", label = "Play sound"})

    -- Windfury: only the families the class can have are shown.
    local function available() return NS.Procs.Available(app.playerClass or api:PlayerClass()) end
    local function any() local a = available(); return a.weapon or a.totem end
    local function db() return app.db end
    form:Card("Class procs")
    form:Note({text = function() return any() and "" or "No proc of your class can be recognized yet." end})
    form:Toggle({key = "procWindfuryWeapon", label = "Windfury of the weapon", visible = function() return available().weapon end})
    form:Input({key = "procWindfuryWeaponText", label = "Text", maxLetters = MAX_TEXT, width = 260,
        visible = function() return available().weapon and db().procWindfuryWeapon == true end})
    form:Toggle({key = "procWindfuryTotem", label = "Windfury Totem", visible = function() return available().totem end})
    form:Input({key = "procWindfuryTotemText", label = "Text", maxLetters = MAX_TEXT, width = 260,
        visible = function() return available().totem and db().procWindfuryTotem == true end})
    form:Toggle({key = "procWindfuryFlash", label = "Screen flash on Windfury", visible = any})
    form:Buttons({{text = "Preview", visible = any, onClick = function()
        app:Preview(available().weapon and "windfury" or "windfuryTotem")
    end}})
    form:Note({text = function()
        return any() and "Windfury is not confirmed in the game yet. Record your spells above for a minute of fighting, stop and type /reload." or ""
    end})
    form:Note({text = function()
        local test = app.root and app.root.procTest
        local counters = type(test) == "table" and test.counters
        if not any() or type(counters) ~= "table" or type(counters.weapon) ~= "table" or type(counters.totem) ~= "table" then return "" end
        return "Last test: %d swings, weapon %d procs and %d rejected, totem %d procs and %d rejected.",
            counters.swings or 0, counters.weapon.procs or 0, app:ProcRejectedCount(counters.weapon),
            counters.totem.procs or 0, app:ProcRejectedCount(counters.totem)
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

    form:Card("Proc cards on nameplates")
    form:Toggle({key = "procPlateEnabled", label = "Show proc cards on nameplates"})
    form:Note({text = "In combat, cards require a readable log entry confirming your proc and its target. Protected entries leave the existing proc effects available."})
    form:Toggle({key = "procPlateWeapon", label = "Windfury of the weapon"})
    form:Toggle({key = "procPlateTotem", label = "Windfury Totem"})
    form:Toggle({key = "procPlateIcon", label = "Show proc icon"})
    form:Toggle({key = "procPlateName", label = "Show proc name"})
    form:Toggle({key = "procPlateAmounts", label = "Show hit damage"})
    form:Toggle({key = "procPlateSum", label = "Show total damage",
        desc = "Available when all hits and damage values are known."})
    form:Toggle({key = "procPlateGroup", label = "Show the hit count"})
    form:Toggle({key = "procPlateHighlight", label = "Highlight critical hits"})
    form:Select({key = "procPlateLayout", label = "Hit layout", options = {{"row", "Row"}, {"column", "Column"}}})
    form:Slider({key = "procPlateX", label = "Horizontal offset", min = -40, max = 100, step = 1, format = "%d"})
    form:Slider({key = "procPlateY", label = "Vertical offset", min = -100, max = 100, step = 1, format = "%d"})
    form:Slider({key = "procPlateSize", label = "Text size", min = 10, max = 22, step = 1, format = "%d"})
    form:Slider({key = "procPlateScale", label = "Card scale", min = .6, max = 2.5, step = .05, format = "%.2f"})
    form:Color({key = "procPlateColor", label = "Proc name color", cancelOnLeave = true})
    form:Select({key = "procPlateAnim", label = "Animation", options = {
        {"pop", "Pop"}, {"slam", "Slam"}, {"rise", "Rise"}, {"shake", "Shake"}, {"pulse", "Pulse"}, {"fade", "Fade"}}})
    form:Slider({key = "procPlateDuration", label = "Duration", min = .4, max = 3, step = .05, format = "%.2f s"})
    form:Slider({key = "procPlateFade", label = "Fade-out time", min = 0, max = 1.5, step = .05, format = "%.2f s"})
    form:Buttons({{text = "Preview proc card", onClick = function() app:PreviewProcPlate() end}})

    -- The status line and the spell list follow a running recording once a second, only while this page is shown.
    local ticker = api:Frame("Frame", nil, form.parent)
    local elapsedTotal = 0
    local function onUpdate(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal >= 1 then elapsedTotal = 0; page.refresh() end
    end
    local function attach()
        elapsedTotal = 0
        ticker:SetScript("OnUpdate", (running() or spellLog.active) and view:CurrentPage() == "procs" and onUpdate or nil)
    end
    page.afterRefresh = attach
    page.onHide = function() ticker:SetScript("OnUpdate", nil) end
    view.procTicker = ticker
end
