local _, NS = ...
local T, I = NS.Theme, NS.Locale
local function tr(value) return I.Text(value) end
-- Sound selection dropdown, the sound library page and its catalog.
local Sounds = {}
NS.UISounds = Sounds

-- Defines the helpers the effect and heal pages need; installs them on ctx.
function Sounds.Define(ctx)
    local app, api, view = ctx.app, ctx.api, ctx.view
    local kit = ctx.kit
    local label, button, divider, closePopups, styleScroll = kit.label, kit.button, kit.divider, kit.closePopups, kit.styleScroll
    local checkbox, editBox, dropdown, slider = kit.checkbox, kit.editBox, kit.dropdown, kit.slider

    local function selectedSummary(category)
        local keys = NS.Sounds.CategoryKeys[category]
        local ids, names, missing = app.db[keys.ids] or {}, {}, false
        for i = 1, #ids do
            local name, available = NS.Sounds.Describe(app.db, ids[i], api.env)
            names[#names + 1] = name; if not available then missing = true end
        end
        if #names == 0 then return tr("No sound selected"), true end
        local prefix = app.db[keys.mode] == "mix" and tr("Mix") .. ": " or ""
        return prefix .. table.concat(names, ", "), missing
    end

    local function soundDropdown(parentFrame, category, x, y, width)
        local main, popup, popupScroll, popupContent, rows
        local function open()
            if popup and popup:IsShown() then popup:Hide(); return end
            if not popup then
                popup = api:Frame("Frame", nil, api:Root(), BackdropTemplateMixin and "BackdropTemplate" or nil)
                popup:SetFrameStrata("TOOLTIP"); popup:SetClampedToScreen(true); if T then T.Panel(popup, "inset") end
                popupScroll = api:Frame("ScrollFrame", nil, popup)
                popupScroll:SetPoint("TOPLEFT", 6, -6); popupScroll:SetPoint("BOTTOMRIGHT", -22, 6)
                popupContent = api:Frame("Frame", nil, popupScroll); popupScroll:SetScrollChild(popupContent)
                styleScroll(popupScroll, 26)
                rows = {}; popup:Hide(); view.popups[#view.popups + 1] = popup
            end
            local catalog = NS.Sounds.Catalog(app.db, api.env)
            popup:SetSize(width, math.min(310, #catalog * 26 + 12)); popupContent:SetSize(width - 34, math.max(1, #catalog * 26))
            for index, item in ipairs(catalog) do
                local row = rows[index]
                if not row then
                    row = button(popupContent, "", 0, -(index - 1) * 26, width - 34, function() end)
                    row:SetScript("OnClick", function()
                        local selected = row.item
                        local keys = NS.Sounds.CategoryKeys[category]
                        app.db[keys.mode], app.db[keys.ids] = "single", {selected.id}
                        app:Changed(); popup:Hide()
                    end)
                    row:SetHeight(25); rows[index] = row
                end
                row.item = item; row:SetText(item.name); row:Show()
                if T then
                    local keys, selected = NS.Sounds.CategoryKeys[category], false
                    for _, id in ipairs(app.db[keys.ids] or {}) do if id == item.id then selected = true break end end
                    T.SetSelected(row, selected)
                end
            end
            for index = #catalog + 1, #rows do rows[index]:Hide() end
            closePopups(popup); popup:ClearAllPoints(); popup:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -3); popup:Show()
        end
        main = button(parentFrame, "", x, y, width, open); if T then T.StyleDropdown(main) end
        view.soundCombos = view.soundCombos or {}; view.soundCombos[category] = main
        view.controls[#view.controls + 1] = function()
            local summary, missing = selectedSummary(category)
            main:SetText(summary .. (missing and (" |cffff7040!|r") or ""))
        end
        return main
    end
    ctx.selectedSummary, ctx.soundDropdown = selectedSummary, soundDropdown
end

function Sounds.BuildPage(ctx)
    local app, api, view, frame, pageWidth, makePage = ctx.app, ctx.api, ctx.view, ctx.frame, ctx.pageWidth, ctx.makePage
    local kit = ctx.kit
    local label, button, divider, closePopups, styleScroll = kit.label, kit.button, kit.divider, kit.closePopups, kit.styleScroll
    local checkbox, editBox, dropdown, slider = kit.checkbox, kit.editBox, kit.dropdown, kit.slider
    local categoryLabels, catalogContent

    -- Sound library.
    local sounds = makePage("sounds", 720)
    local soundActionX = pageWidth - 180
    label(sounds, "SOUND LIBRARY", 16, -10, 250, "GameFontNormalLarge", "gold")
    label(sounds, "Category", 16, -42, 120, "GameFontHighlightSmall", "muted")
    categoryLabels = {
        crit="Crit", heal="Heal", kill="Kill", record="Record", healRecord="Heal record",
        low="Weak crit", healLow="Weak heal",
    }
    local categoryOptions = {
        {"crit","Crit"},{"heal","Heal"},{"kill","Kill"},{"record","Record"},
        {"healRecord","Heal record"},{"low","Weak crit"},{"healLow","Weak heal"},
    }
    view.soundCategoryDropdown = dropdown(sounds, 16, -62, 250, categoryOptions,
        function() return view.soundCategory end, function(value) view.soundCategory = value end)
    label(sounds, "Sound channel", 280, -42, 160, "GameFontHighlightSmall", "muted")
    local soundChannelKeys = {
        crit="critSoundChannel",heal="healSoundChannel",kill="killSoundChannel",
        record="recordSoundChannel",healRecord="healRecordSoundChannel",
        low="lowSoundChannel",healLow="healLowSoundChannel",
    }
    view.soundChannelDropdown = dropdown(sounds, 280, -62, 150,
        {{"Master","Master"},{"Dialog","Dialog"},{"SFX","SFX"}},
        function() return NS.Logic.SoundChannel(app.db, view.soundCategory) end,
        function(value) app.db[soundChannelKeys[view.soundCategory]] = value end)
    view.soundModeButton = button(sounds, "", soundActionX, -62, 150, function()
        local keys = NS.Sounds.CategoryKeys[view.soundCategory]
        app.db[keys.mode] = app.db[keys.mode] == "mix" and "single" or "mix"
        if app.db[keys.mode] == "single" and #app.db[keys.ids] > 1 then app.db[keys.ids] = {app.db[keys.ids][1]} end
        app:Changed()
    end)
    view.soundSelection = label(sounds, "", 16, -98, soundActionX - 28, "GameFontHighlight", "text")
    view.soundSelection:SetHeight(34)
    view.listenSelection = button(sounds, "Listen to selection", soundActionX, -100, 150, function()
        local ok, reason = app:PreviewSound(view.soundCategory); view:SetSoundStatus(ok, reason)
    end)
    view.customHint = label(sounds, "", 16, -138, pageWidth - 82, "GameFontHighlightSmall", "muted")
    view.customHint:SetHeight(34)
    divider(sounds, -178)
    label(sounds, "Search", 16, -190, 100, "GameFontHighlightSmall", "muted")
    view.soundSearch = editBox(sounds, 16, -209, 220, 28, false); view.soundSearch:SetMaxLetters(60)
    view.soundSearch:SetScript("OnTextChanged", function(_, userInput) if userInput then view:UpdateCatalog() end end)
    view.sourceButtons = {}
    local sources = {{"all","All"},{"builtin","Included"},{"custom","Own sounds"},{"shared","SharedMedia"}}
    for i, spec in ipairs(sources) do
        local source = spec[1]
        local b = button(sounds, spec[2], 250 + (i - 1) * 100, -209, 94, function()
            view.soundSource = source; view:UpdateCatalog()
        end)
        if T then T.StyleTab(b) end; view.sourceButtons[source] = b
    end
    local catalogScroll = api:Frame("ScrollFrame", nil, sounds)
    catalogScroll:SetPoint("TOPLEFT", 16, -246); catalogScroll:SetSize(pageWidth - 86, 240)
    catalogContent = api:Frame("Frame", nil, catalogScroll); catalogContent:SetSize(pageWidth - 108, 1)
    catalogScroll:SetScrollChild(catalogContent)
    styleScroll(catalogScroll, 34)
    view.catalogScroll, view.catalogContent, view.catalogStartY = catalogScroll, catalogContent, -2
    view.catalogEmpty = label(catalogContent, "No sounds match the current search or source.",
        10, -10, pageWidth - 128, "GameFontHighlightSmall", "muted")
    view.catalogEmpty:SetHeight(40); view.catalogEmpty:Hide()
    divider(sounds, -500)
    label(sounds, "OWN SOUND FILES", 16, -516, 240, "GameFontNormalLarge", "gold")
    local customHelp = label(sounds, "Copy files to Interface\\ZenialSounds\\ and enter the relative filename. New files can require a full WoW restart.",
        16, -543, pageWidth - 82, "GameFontHighlightSmall", "muted"); customHelp:SetHeight(34)
    label(sounds, "Display name", 16, -583, 190, "GameFontHighlightSmall", "muted")
    label(sounds, "Relative filename", 216, -583, 260, "GameFontHighlightSmall", "muted")
    view.customName = editBox(sounds, 16, -600, 190, 28, false)
    view.customFile = editBox(sounds, 216, -600, 260, 28, false)
    view.customName:SetMaxLetters(60); view.customFile:SetMaxLetters(160)
    view.customSave = button(sounds, "Save", 486, -600, 76, function()
        local id, err = app:AddOrUpdateCustomSound(view.customName:GetText(), view.customFile:GetText(), view.editCustomID)
        if id then
            view.editCustomID = nil; view.customName:SetText(""); view.customFile:SetText("")
            view:SetSoundStatus(true, tr("Own sound saved.")); view:RefreshSounds()
        else view:SetSoundStatus(false, err) end
    end, "primary")
    view.customCancel = button(sounds, "Cancel", 570, -600, 72, function()
        view.editCustomID = nil; view.customName:SetText(""); view.customFile:SetText(""); view:RefreshSounds()
    end)
    slider(sounds, "soundCooldown", "Sound pause", 16, -650, 300, 0, 30, .25, "%.2f s")
    view.soundStatus = label(sounds, "", 330, -648, 312, "GameFontHighlightSmall", "muted"); view.soundStatus:SetHeight(44)

    local removeConfirm = api:Frame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    removeConfirm:SetSize(410, 145); removeConfirm:SetPoint("CENTER"); removeConfirm:SetFrameStrata("TOOLTIP")
    if T then T.Panel(removeConfirm, "parchment") end
    label(removeConfirm, "Remove own sound?", 18, -15, 374, "GameFontNormalLarge", "gold"):SetJustifyH("CENTER")
    view.removeText = label(removeConfirm, "", 18, -43, 374, "GameFontHighlightSmall", "muted")
    view.removeText:SetJustifyH("CENTER"); view.removeText:SetHeight(50)
    button(removeConfirm, "Remove entry", 58, -105, 136, function()
        if view.removeSoundID then app:RemoveCustomSound(view.removeSoundID) end
        view.removeSoundID = nil; removeConfirm:Hide(); view:RefreshSounds()
    end, "danger")
    button(removeConfirm, "Cancel", 212, -105, 136, function() removeConfirm:Hide() end)
    removeConfirm:Hide(); view.removeConfirm = removeConfirm
    ctx.categoryLabels, ctx.catalogContent = categoryLabels, catalogContent
end

function Sounds.DefineMethods(ctx)
    local app, api, view, pageWidth = ctx.app, ctx.api, ctx.view, ctx.pageWidth
    local kit = ctx.kit
    local label, button, divider, closePopups, styleScroll = kit.label, kit.button, kit.divider, kit.closePopups, kit.styleScroll
    local checkbox, editBox, dropdown, slider = kit.checkbox, kit.editBox, kit.dropdown, kit.slider
    local selectedSummary, categoryLabels, catalogContent = ctx.selectedSummary, ctx.categoryLabels, ctx.catalogContent

    function view:SetSoundStatus(ok, reason)
        local prefix = ok and tr("Ready") or tr("Error")
        self.soundStatus:SetText(prefix .. (reason and reason ~= "" and (": " .. tr(reason)) or ""))
    end

    local function categoryNames(categories)
        local names = {}; for i = 1, #categories do names[#names + 1] = tr(categoryLabels[categories[i]] or categories[i]) end
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
        self.removeText:SetText(item.name .. suffix); self.removeSoundID = id; self.removeConfirm:Show()
    end

    local function isSelected(id)
        local keys = NS.Sounds.CategoryKeys[view.soundCategory]
        for i = 1, #(app.db[keys.ids] or {}) do if app.db[keys.ids][i] == id then return true end end
        return false
    end

    function view:ToggleCatalogSound(id)
        local keys = NS.Sounds.CategoryKeys[self.soundCategory]
        local ids = app.db[keys.ids] or {}
        if app.db[keys.mode] == "single" then
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
        row = api:Frame("Frame", nil, catalogContent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        row:SetSize(pageWidth - 108, 31); if T then T.StyleRow(row) end
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
        if not app.db then return end
        local query = self.soundSearch and string.lower(self.soundSearch:GetText() or "") or ""
        if self.catalogQuery ~= query or self.catalogSource ~= self.soundSource then
            self.catalogScroll:SetVerticalScroll(0)
            self.catalogQuery, self.catalogSource = query, self.soundSource
        end
        local visible = {}
        for _, item in ipairs(NS.Sounds.Catalog(app.db, api.env)) do
            if (self.soundSource == "all" or item.source == self.soundSource)
                and (query == "" or string.find(string.lower(item.name), query, 1, true)) then visible[#visible + 1] = item end
        end
        for index, item in ipairs(visible) do
            local row = catalogRow(index); row.item = item
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, self.catalogStartY - (index - 1) * 34)
            row.name:SetText(item.name); row.source:SetText(tr(item.source == "builtin" and "Included" or item.source == "custom" and "Own sounds" or "SharedMedia"))
            row.pick:SetText(tr(isSelected(item.id) and "Remove" or (app.db[NS.Sounds.CategoryKeys[self.soundCategory].mode] == "mix" and "Add" or "Select")))
            row.edit:SetShown(item.source == "custom"); row.remove:SetShown(item.source == "custom"); row:Show()
        end
        for i = #visible + 1, #self.catalogRows do self.catalogRows[i]:Hide() end
        self.catalogEmpty:SetShown(#visible == 0)
        self.catalogContent:SetHeight(#visible == 0 and 50 or #visible * 34)
        if self.catalogScroll.UpdateScrollChildRect then self.catalogScroll:UpdateScrollChildRect() end
        self.catalogScroll:RefreshScrollbar()
        for source, b in pairs(self.sourceButtons) do if T then T.SetSelected(b, source == self.soundSource) end end
    end

    function view:RefreshSounds()
        if not app.db then return end
        local keys = NS.Sounds.CategoryKeys[self.soundCategory]
        self.soundModeButton:SetText(tr(app.db[keys.mode] == "mix" and "Random mix" or "Single sound"))
        local summary, missing = selectedSummary(self.soundCategory)
        self.soundSelection:SetText(tr("Selection") .. ": " .. summary .. (missing and (" |cffff7040" .. tr("Incomplete") .. "|r") or ""))
        local ownCount = #(app.db.customSounds or {})
        self.customHint:SetText(ownCount == 0 and tr("No own sounds yet. Copy a file to Interface\\ZenialSounds\\, then enter its display name and relative filename below.")
            or tr("Own sounds are managed below. Files remain in Interface\\ZenialSounds\\ when an entry is removed."))
        self.customSave:SetText(tr(self.editCustomID and "Update" or "Save"))
        self:UpdateCatalog()
    end
end
