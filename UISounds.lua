local _, NS = ...
local T, I = NS.Theme, NS.Locale
local function tr(value) return I.Text(value) end
-- Sound library: catalog, search, own files. The library sits in a row of the Sounds page; the
-- selection of the category, sound, mix and channel are ordinary form rows (UIPageSounds.lua).
local Sounds = {}
NS.UISounds = Sounds

-- Order of the event choice; label (English key) per category.
Sounds.Categories = {
    {"crit", "Crit"}, {"record", "Crit record"}, {"low", "Weak crit"},
    {"heal", "Heal crit"}, {"healRecord", "Heal record"}, {"healLow", "Weak heal crit"},
    {"kill", "Kill"}, {"streak", "Kill streak"}, {"proc", "Proc"},
}
local categoryLabels = {}
for _, entry in ipairs(Sounds.Categories) do categoryLabels[entry[1]] = entry[2] end
Sounds.CategoryLabels = categoryLabels

-- Library layout (inside a 608 px card).
Sounds.LibraryHeight = 520
local LIST_WIDTH, LIST_HEIGHT = 584, 240

function Sounds.DefineMethods(ctx)
    local app, api, view = ctx.app, ctx.api, ctx.view
    local kit = ctx.kit

    -- Names of the chosen sounds, and whether one of them is missing.
    function view:SoundSummary(category)
        local keys = NS.Sounds.CategoryKeys[category]
        local ids, names, missing = app.db[keys.ids] or {}, {}, false
        for i = 1, #ids do
            local name, available = NS.Sounds.Describe(app.db, ids[i], api.env)
            names[#names + 1] = available and name or (name .. " (" .. tr("missing") .. ")")
            if not available then missing = true end
        end
        return names, missing
    end

    function view:SetSoundStatus(ok, reason)
        local prefix = ok and tr("Ready") or tr("Error")
        if self.soundStatus then
            self.soundStatus:SetText(prefix .. (reason and reason ~= "" and (": " .. tr(reason)) or ""))
        end
        -- The Sound card repeats a failure, because the library may be hidden.
        self.soundFeedback = (not ok) and reason or nil
        local form = self.pages.sounds and self.pages.sounds.form
        if form and self.page == "sounds" then form:Refresh() end
    end

    local function categoryNames(categories)
        local names = {}
        for i = 1, #categories do names[#names + 1] = tr(categoryLabels[categories[i]] or categories[i]) end
        return table.concat(names, ", ")
    end

    function view:EditCustom(id)
        local item = NS.Sounds.CustomByID(app.db, id); if not item then return end
        self.editCustomID = id; self.customName:SetText(item.name); self.customFile:SetText(item.file)
        self.customName:SetFocus(); self.customSave:SetText(tr("Update"))
    end

    function view:ConfirmRemove(id)
        local item = NS.Sounds.CustomByID(app.db, id); if not item then return end
        local used = NS.Sounds.UsedBy(app.db, id)
        local suffix = #used > 0 and ("\n" .. tr("Used by") .. ": " .. categoryNames(used) .. ". " .. tr("These selections become incomplete.")) or ""
        self:Confirm({title = "Remove own sound?", text = function() return "%s", item.name .. suffix end, confirm = "Remove entry",
            onConfirm = function() app:RemoveCustomSound(id); view:RefreshSounds() end})
    end

    local function isSelected(id)
        local keys = NS.Sounds.CategoryKeys[view.soundCategory]
        for i = 1, #(app.db[keys.ids] or {}) do if app.db[keys.ids][i] == id then return true end end
        return false
    end

    -- Single mode: the sound becomes the one sound of the category. Mix: added or removed.
    function view:ToggleCatalogSound(id)
        local keys = NS.Sounds.CategoryKeys[self.soundCategory]
        local ids = app.db[keys.ids] or {}
        if app.db[keys.mode] ~= "mix" then
            app.db[keys.ids] = {id}
        else
            local kept, found = {}, false
            for i = 1, #ids do
                if ids[i] == id then found = true else kept[#kept + 1] = ids[i] end
            end
            if not found then kept[#kept + 1] = id end
            app.db[keys.ids] = kept
        end
        app:Changed()
    end

    local function catalogRow(index)
        local row = view.catalogRows[index]; if row then return row end
        local label, button = kit.label, kit.button
        row = api:Frame("Frame", nil, view.catalogContent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        row:SetSize(LIST_WIDTH - 18, 31); if T then T.StyleRow(row) end
        row.name = label(row, "", 10, -7, 190, "GameFontHighlight", "text")
        row.source = label(row, "", 205, -8, 75, "GameFontHighlightSmall", "muted")
        row.pick = button(row, "Select", 284, -2, 82, function() view:ToggleCatalogSound(row.item.id) end)
        row.test = button(row, "Test", 372, -2, 60, function()
            local ok, reason = app:PreviewSoundRef(row.item.id, view.soundCategory); view:SetSoundStatus(ok, reason)
        end)
        row.edit = button(row, "Edit", 438, -2, 55, function() view:EditCustom(row.item.id) end)
        row.remove = button(row, "×", 499, -2, 35, function() view:ConfirmRemove(row.item.id) end, "danger")
        kit.tip(row.remove, "Remove entry")
        view.catalogRows[index] = row; return row
    end

    function view:UpdateCatalog()
        if not app.db or not self.catalogContent then return end
        local query = self.soundSearch and string.lower(self.soundSearch:GetText() or "") or ""
        if self.catalogQuery ~= query or self.catalogSource ~= self.soundSource then
            self.catalogScroll:SetVerticalScroll(0)
            self.catalogQuery, self.catalogSource = query, self.soundSource
        end
        local keys = NS.Sounds.CategoryKeys[self.soundCategory]
        local mix = app.db[keys.mode] == "mix"
        local visible = {}
        for _, item in ipairs(NS.Sounds.Catalog(app.db, api.env)) do
            if (self.soundSource == "all" or item.source == self.soundSource)
                and (query == "" or string.find(string.lower(item.name), query, 1, true)) then visible[#visible + 1] = item end
        end
        for index, item in ipairs(visible) do
            local row = catalogRow(index); row.item = item
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, self.catalogStartY - (index - 1) * 34)
            row.name:SetText(item.name); row.source:SetText(tr(item.source == "builtin" and "Included" or item.source == "custom" and "Own sounds" or "SharedMedia"))
            local selected = isSelected(item.id)
            row.pick:SetText(tr(mix and (selected and "Remove" or "Add") or (selected and "Selected" or "Select")))
            row.pick:SetEnabled(mix or not selected)
            row.edit:SetShown(item.source == "custom"); row.remove:SetShown(item.source == "custom"); row:Show()
        end
        for i = #visible + 1, #self.catalogRows do self.catalogRows[i]:Hide() end
        self.catalogEmpty:SetShown(#visible == 0)
        self.catalogContent:SetHeight(#visible == 0 and 50 or #visible * 34)
        if self.catalogScroll.UpdateScrollChildRect then self.catalogScroll:UpdateScrollChildRect() end
        self.catalogScroll:RefreshScrollbar()
        for source, b in pairs(self.sourceButtons) do if T then T.SetSelected(b, source == self.soundSource) end end
    end

    -- The library only changes with the data of the chosen category.
    function view:RefreshSounds()
        if not app.db or not self.customHint then return end
        local ownCount = #(app.db.customSounds or {})
        self.customHint:SetText(ownCount == 0 and tr("No own sounds yet. Copy a file to Interface\\ZenialSounds\\, then enter its display name and relative filename below.")
            or tr("Own sounds are managed below. Files remain in Interface\\ZenialSounds\\ when an entry is removed."))
        self.customSave:SetText(tr(self.editCustomID and "Update" or "Save"))
        self:UpdateCatalog()
    end
end

-- Builds the library into `frame` (a row of the Sounds page, 608 px wide).
function Sounds.BuildLibrary(ctx, frame)
    local app, api, view = ctx.app, ctx.api, ctx.view
    local kit = ctx.kit
    local label, button, divider, styleScroll, editBox = kit.label, kit.button, kit.divider, kit.styleScroll, kit.editBox

    view.customHint = label(frame, "", 0, 0, 600, "GameFontHighlightSmall", "muted")
    view.customHint:SetHeight(34)
    label(frame, "Search", 0, -42, 100, "GameFontHighlightSmall", "muted")
    view.soundSearch = editBox(frame, 0, -58, 220, 28, false); view.soundSearch:SetMaxLetters(60)
    view.soundSearch:SetScript("OnTextChanged", function(_, userInput) if userInput then view:UpdateCatalog() end end)
    view.sourceButtons = {}
    for i, spec in ipairs({{"all", "All"}, {"builtin", "Included"}, {"custom", "Own sounds"}, {"shared", "SharedMedia"}}) do
        local source = spec[1]
        local b = button(frame, spec[2], 232 + (i - 1) * 94, -58, 90, function()
            view.soundSource = source; view:UpdateCatalog()
        end)
        if T then T.StyleTab(b) end; view.sourceButtons[source] = b
    end
    local catalogScroll = api:Frame("ScrollFrame", nil, frame)
    catalogScroll:SetPoint("TOPLEFT", 0, -96); catalogScroll:SetSize(LIST_WIDTH, LIST_HEIGHT)
    local catalogContent = api:Frame("Frame", nil, catalogScroll); catalogContent:SetSize(LIST_WIDTH - 22, 1)
    catalogScroll:SetScrollChild(catalogContent)
    styleScroll(catalogScroll, 34)
    view.catalogScroll, view.catalogContent, view.catalogStartY = catalogScroll, catalogContent, -2
    view.catalogEmpty = label(catalogContent, "No sounds match the current search or source.",
        10, -10, LIST_WIDTH - 60, "GameFontHighlightSmall", "muted")
    view.catalogEmpty:SetHeight(40); view.catalogEmpty:Hide()

    divider(frame, -348)
    label(frame, "OWN SOUND FILES", 0, -362, 240, "GameFontNormal", "gold")
    local customHelp = label(frame, "Copy files to Interface\\ZenialSounds\\ and enter the relative filename. New files can require a full WoW restart.",
        0, -386, 600, "GameFontHighlightSmall", "muted"); customHelp:SetHeight(34)
    label(frame, "Display name", 0, -426, 170, "GameFontHighlightSmall", "muted")
    label(frame, "Relative filename", 180, -426, 230, "GameFontHighlightSmall", "muted")
    view.customName = editBox(frame, 0, -442, 170, 28, false)
    view.customFile = editBox(frame, 180, -442, 230, 28, false)
    view.customName:SetMaxLetters(60); view.customFile:SetMaxLetters(160)
    view.customSave = button(frame, "Save", 420, -442, 76, function()
        local id, err = app:AddOrUpdateCustomSound(view.customName:GetText(), view.customFile:GetText(), view.editCustomID)
        if id then
            view.editCustomID = nil; view.customName:SetText(""); view.customFile:SetText("")
            view:SetSoundStatus(true, tr("Own sound saved.")); view:RefreshSounds()
        else view:SetSoundStatus(false, err) end
    end, "primary")
    view.customCancel = button(frame, "Cancel", 502, -442, 72, function()
        view.editCustomID = nil; view.customName:SetText(""); view.customFile:SetText(""); view:RefreshSounds()
    end)
    view.soundStatus = label(frame, "", 0, -482, 600, "GameFontHighlightSmall", "muted"); view.soundStatus:SetHeight(34)
end
