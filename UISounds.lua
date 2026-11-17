local _, NS = ...
local T, K, I = NS.Theme, NS.Kit, NS.Locale
local Window, Form = NS.Window, NS.Form
local function tr(value) return I.Text(value) end
-- Sound library: catalog, search, own files. The library sits in a row of the Sounds page; the
-- selection of the category, sound, mix and channel are ordinary form rows (UIPageSounds.lua).
local Sounds = {}
NS.UISounds = Sounds

-- Order of the event choice; label (English key) per category.
Sounds.Categories = {
    {"crit", "Crit"}, {"record", "Crit record"}, {"low", "Weak crit"},
    {"heal", "Heal crit"}, {"healRecord", "Heal record"}, {"healLow", "Weak heal crit"},
    {"kill", "Kill"}, {"streak", "Kill streak"}, {"proc", "Proc"}, {"windfury", "Windfury"},
}
local categoryLabels = {}
for _, entry in ipairs(Sounds.Categories) do categoryLabels[entry[1]] = entry[2] end
Sounds.CategoryLabels = categoryLabels

-- Library layout (inside a card; the list takes the width of the row less the rail).
Sounds.LibraryHeight = 520
local LIST_HEIGHT, RAIL = 240, 16

local function text(parent, role, color, x, y, width, height)
    local fs = K.Text(parent, "", role, color)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    if height then fs:SetHeight(height) end
    return fs
end

local function button(parent, value, width, action, variant)
    return T.Button(parent, tr(value), width, 26, action, variant or "secondary")
end

function Sounds.DefineMethods(view)
    local app, api = view.app, view.api

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
        local page = self:Page("sounds")
        if page and page.form and self:CurrentPage() == "sounds" then page.form:Refresh() end
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
        self:Confirm({title = "Remove own sound?", text = item.name .. suffix, accept = "Remove entry", variant = "danger",
            onAccept = function() app:RemoveCustomSound(id); view:RefreshSounds() end})
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
        local content = view.catalogContent
        row = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
        row:SetHeight(31); T.StyleRow(row)
        row.name = text(row, "body", "text", 10, -7, 190)
        row.source = text(row, "caption", "muted", 205, -8, 75)
        row.remove = button(row, "×", 35, function() view:ConfirmRemove(row.item.id) end, "danger")
        row.remove:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)
        Form.Tooltip(row.remove, tr("Remove entry"), "")
        row.edit = button(row, "Edit", 55, function() view:EditCustom(row.item.id) end)
        row.edit:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
        row.test = button(row, "Test", 60, function()
            local ok, reason = app:PreviewSoundRef(row.item.id, view.soundCategory); view:SetSoundStatus(ok, reason)
        end)
        row.test:SetPoint("RIGHT", row.edit, "LEFT", -6, 0)
        row.pick = button(row, "Select", 82, function() view:ToggleCatalogSound(row.item.id) end)
        row.pick:SetPoint("RIGHT", row.test, "LEFT", -6, 0)
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
            local top = self.catalogStartY - (index - 1) * 34
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.catalogContent, "TOPLEFT", 0, top)
            row:SetPoint("TOPRIGHT", self.catalogContent, "TOPRIGHT", 0, top)
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
        for source, b in pairs(self.sourceButtons) do T.SetSelected(b, source == self.soundSource) end
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

-- Builds the library into `frame`, a row of the Sounds page that is `width` wide.
function Sounds.BuildLibrary(view, frame, width)
    local app = view.app
    -- A text that spans the row and wraps.
    local function across(fs, y, height)
        fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, y)
        fs:SetHeight(height); fs:SetWordWrap(true)
    end

    view.customHint = text(frame, "caption", "muted", 0, 0)
    across(view.customHint, 0, 34)
    text(frame, "caption", "muted", 0, -42, 100):SetText(tr("Search"))
    view.soundSearch = Form.Edit(frame, {width = 220, maxLetters = 60, live = true, tr = tr,
        set = function() view:UpdateCatalog() end})
    view.soundSearch:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -60)
    view.sourceButtons = {}
    for i, spec in ipairs({{"all", "All"}, {"builtin", "Included"}, {"custom", "Own sounds"}, {"shared", "SharedMedia"}}) do
        local source = spec[1]
        local b = button(frame, spec[2], 90, function()
            view.soundSource = source; view:UpdateCatalog()
        end)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 232 + (i - 1) * 94, -58)
        T.StyleTab(b); view.sourceButtons[source] = b
    end
    local catalogScroll, catalogContent = Window.ScrollArea(frame, math.max(100, width - RAIL - 2))
    catalogScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -96); catalogScroll:SetHeight(LIST_HEIGHT)
    view.catalogScroll, view.catalogContent, view.catalogStartY = catalogScroll, catalogContent, -2
    view.catalogEmpty = text(catalogContent, "caption", "muted", 10, -10)
    view.catalogEmpty:SetText(tr("No sounds match the current search or source."))
    view.catalogEmpty:SetPoint("TOPRIGHT", catalogContent, "TOPRIGHT", -10, -10)
    view.catalogEmpty:SetHeight(40); view.catalogEmpty:SetWordWrap(true); view.catalogEmpty:Hide()

    local line = T.Divider(frame)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -348); line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -348)
    text(frame, "overline", "goldDim", 0, -362, 240):SetText(tr("OWN SOUND FILES"))
    local customHelp = text(frame, "caption", "muted", 0, -382)
    customHelp:SetText(tr("Copy files to Interface\\ZenialSounds\\ and enter the relative filename. New files can require a full WoW restart."))
    across(customHelp, -382, 34)
    text(frame, "caption", "muted", 0, -426, 170):SetText(tr("Display name"))
    text(frame, "caption", "muted", 180, -426, 230):SetText(tr("Relative filename"))
    view.customName = Form.Edit(frame, {width = 170, maxLetters = 60, tr = tr})
    view.customName:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -444)
    view.customFile = Form.Edit(frame, {width = 230, maxLetters = 160, tr = tr})
    view.customFile:SetPoint("TOPLEFT", frame, "TOPLEFT", 180, -444)
    view.customSave = button(frame, "Save", 76, function()
        local id, err = app:AddOrUpdateCustomSound(view.customName:GetText(), view.customFile:GetText(), view.editCustomID)
        if id then
            view.editCustomID = nil; view.customName:SetText(""); view.customFile:SetText("")
            view:SetSoundStatus(true, tr("Own sound saved.")); view:RefreshSounds()
        else view:SetSoundStatus(false, err) end
    end, "primary")
    view.customSave:SetPoint("TOPLEFT", frame, "TOPLEFT", 420, -443)
    view.customCancel = button(frame, "Cancel", 72, function()
        view.editCustomID = nil; view.customName:SetText(""); view.customFile:SetText(""); view:RefreshSounds()
    end)
    view.customCancel:SetPoint("TOPLEFT", frame, "TOPLEFT", 502, -443)
    view.soundStatus = text(frame, "caption", "muted", 0, -482)
    across(view.soundStatus, -482, 34)
end

-- The list follows the width of its row.
function Sounds.FitLibrary(view, width)
    if view.catalogScroll and view.catalogScroll.SetContentWidth then
        view.catalogScroll:SetContentWidth(math.max(100, width - RAIL - 2))
    end
end
