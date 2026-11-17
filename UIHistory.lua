local _, NS = ...
local T, K, I = NS.Theme, NS.Kit, NS.Locale
local Window, Form = NS.Window, NS.Form
local function tr(value) return I.Text(value) end
-- History page (crit and heal records): a fixed page, a segment for the kind on top, the list below.
local History = {}
NS.UIHistory = History

local ROW_HEIGHT, ROW_STEP = 46, 50
local PAD, RAIL = 16, 16

local function text(parent, role, color, x, y, width, height)
    local fs = K.Text(parent, "", role, color)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    if height then fs:SetHeight(height) end
    return fs
end

local function formatAmount(value)
    local result = tostring(math.floor(value or 0)); local separator = I.isGerman and "." or ","
    while true do
        local changed
        result, changed = result:gsub("^(%-?%d+)(%d%d%d)", "%1" .. separator .. "%2")
        if changed == 0 then break end
    end
    return result
end

local SCHOOLS = {{1, "Physical"}, {2, "Holy"}, {4, "Fire"}, {8, "Nature"}, {16, "Frost"}, {32, "Shadow"}, {64, "Arcane"}}
local function schoolLabel(value)
    local mask, names = type(value.school) == "number" and math.floor(value.school) or 0, {}
    for _, school in ipairs(SCHOOLS) do if math.floor(mask / school[1]) % 2 == 1 then names[#names + 1] = tr(school[2]) end end
    return #names > 0 and table.concat(names, "/") or tr("Unknown")
end

-- The refresh of the page; it does nothing until the page is built.
function History.Define(view)
    local app, api = view.app, view.api
    local function formatDate(value) return api:Date(value, I.isGerman and "%d.%m.%Y %H:%M" or "%Y-%m-%d %H:%M") or tr("Unknown") end
    local function entryArea(value)
        local zone = value.zone ~= "" and value.zone or tr("Unknown")
        return value.subzone ~= "" and value.subzone ~= value.zone and (zone .. " - " .. value.subzone) or zone
    end
    History.FormatDate, History.EntryArea = formatDate, entryArea

    local function historyRow(self, index)
        local row = self.historyRows[index]; if row then return row end
        local content = self.historyContent
        row = CreateFrame("Button", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_STEP)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW_STEP)
        T.StyleRow(row)
        row.rank = text(row, "heading", "muted", 10, -9, 30)
        row.amount = text(row, "title", "gold", 42, -8, 112)
        row.target = text(row, "body", "text", 160, -7)
        row.target:SetPoint("TOPRIGHT", row, "TOPRIGHT", -165, -7)
        row.area = text(row, "caption", "muted", 160, -25)
        row.area:SetPoint("TOPRIGHT", row, "TOPRIGHT", -165, -25)
        row.when = text(row, "caption", "muted", 0, -14, 145)
        row.when:ClearAllPoints(); row.when:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -14); row.when:SetJustifyH("RIGHT")
        row:HookScript("OnEnter", function(owner)
            local tip = GameTooltip
            if not owner.entry or not tip or not tip.SetOwner then return end
            tip:SetOwner(owner, "ANCHOR_RIGHT"); tip:SetText(formatAmount(owner.entry.amount), 1, .8, .27)
            if tip.AddLine then
                tip:AddLine(tr("Target") .. ": " .. (owner.entry.target ~= "" and owner.entry.target or tr("Unknown")), 1, 1, 1)
                tip:AddLine(tr("Time") .. ": " .. formatDate(owner.entry.at), .85, .82, .72)
                tip:AddLine(tr("Area") .. ": " .. entryArea(owner.entry), .85, .82, .72)
                tip:AddLine(tr(owner.kind == "heal" and "Healing school" or "Damage type") .. ": " .. schoolLabel(owner.entry), .70, .64, .54)
                tip:AddLine(tr("Skill") .. ": " .. tr(owner.kind == "heal" and
                    "Healing spell or triggered healing effect; exact name is not supplied" or
                    "Normal auto hit or client-unassigned bonus damage"), .70, .64, .54)
            end
            if tip.Show then tip:Show() end
        end)
        row:HookScript("OnLeave", function()
            local tip = GameTooltip
            if tip and tip.Hide then tip:Hide() end
        end)
        self.historyRows[index] = row; return row
    end

    function view:RefreshHistory()
        if not app.history or not self.historyForm then return end
        self.historyForm:Refresh()
        local kind = self.historyKind == "heal" and "heal" or "crit"
        local key = app:EnsureCharacter()
        local values = key and NS.History.Get(app.history, key, self.historyList, kind) or {}
        local best = key and NS.History.Best(app.history, key, kind)
        self.historyWarning:SetText(tr(kind == "heal" and
            "Observed critical heals on your target or yourself can come from other players. Forever does not provide the healer or spell." or
            "Observed target crits can also come from other players. The Forever client does not provide the attacker or skill."))
        self.historyBestTitle:SetText(tr(kind == "heal" and "Highest observed critical heal" or "Highest observed crit"))
        self.historyRecording:SetText(tr("Recording") .. ": " .. tr(app.history.enabled and "On" or "Off"))
        self.historyCharacter:SetText(tr("Current character") .. ": " .. (app.characterName or tr("Unknown")))
        if best then
            self.historyBestAmount:SetText(formatAmount(best.amount))
            self.historyBestMeta:SetText((best.target ~= "" and best.target or tr("Unknown")) .. "\n" .. formatDate(best.at) .. " - " .. entryArea(best))
        else
            self.historyBestAmount:SetText("-")
            self.historyBestMeta:SetText(tr(kind == "heal" and "No critical heals recorded yet." or "No crits recorded yet."))
        end
        T.SetSelected(self.topHistoryTab, self.historyList == "top")
        T.SetSelected(self.recentHistoryTab, self.historyList == "recent")
        self.historyEmpty:SetShown(#values == 0)
        self.historyEmpty:SetText(tr(kind == "heal" and "No critical heals recorded yet." or "No crits recorded yet.") .. "\n" ..
            tr("Recording starts with activation; earlier hits cannot be restored."))
        for index, value in ipairs(values) do
            local row = historyRow(self, index)
            row.entry, row.kind = value, kind
            row.rank:SetText(self.historyList == "top" and (index .. ".") or "")
            row.amount:SetText(formatAmount(value.amount))
            row.target:SetText(value.target ~= "" and value.target or tr("Unknown"))
            row.area:SetText(entryArea(value))
            row.when:SetText(formatDate(value.at))
            row:Show()
        end
        for index = #values + 1, #self.historyRows do self.historyRows[index]:Hide() end
        self.historyContent:SetHeight(math.max(1, #values * ROW_STEP))
        if self.historyScroll.UpdateScrollChildRect then self.historyScroll:UpdateScrollChildRect() end
        if self.historyScroll.RefreshScrollbar then self.historyScroll:RefreshScrollbar() end
    end
end

function History.Build(view, page)
    local app = view.app
    local host = page.frame
    local formContext = {tr = tr, changed = function() view:RefreshHistory() end}
    local segmentHost = CreateFrame("Frame", nil, host)
    segmentHost:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    local historyForm = Form.New(formContext, segmentHost, view.formWidth)
    historyForm:Card()
    historyForm:Segment({full = true, options = {{"crit", "Crits"}, {"heal", "Heal crits"}},
        get = function() return view.historyKind end, set = function(value) view.historyKind = value end})
    view.historyForm = historyForm
    page.form = historyForm

    local panel = CreateFrame("Frame", nil, host, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -76); panel:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -Window.metrics.formGap, 0)
    T.Panel(panel, "surface")
    view.historyPage = panel

    view.historyWarning = text(panel, "caption", "muted", PAD, -11)
    view.historyWarning:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(PAD + 154), -11)
    view.historyWarning:SetHeight(38); view.historyWarning:SetWordWrap(true)
    view.historyRecording = T.Button(panel, "", 138, 26, function() app:SetHistoryEnabled(not app.history.enabled) end, "secondary")
    view.historyRecording:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -9)

    local recordCard = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
    recordCard:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -51); recordCard:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -51)
    recordCard:SetHeight(62)
    T.Panel(recordCard, "parchment")
    view.historyBestTitle = text(recordCard, "caption", "muted", 14, -9, 180)
    view.historyBestAmount = text(recordCard, "title", "gold", 14, -26, 160)
    view.historyCharacter = text(recordCard, "caption", "muted", 190, -8)
    view.historyCharacter:SetPoint("TOPRIGHT", recordCard, "TOPRIGHT", -14, -8)
    view.historyBestMeta = text(recordCard, "body", "text", 190, -25)
    view.historyBestMeta:SetPoint("TOPRIGHT", recordCard, "TOPRIGHT", -14, -25); view.historyBestMeta:SetHeight(30)

    view.topHistoryTab = T.Button(panel, tr("Top 100"), 132, 26, function() view.historyList = "top"; view:RefreshHistory() end, "secondary")
    view.topHistoryTab:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -124)
    view.recentHistoryTab = T.Button(panel, tr("Latest 100"), 132, 26, function() view.historyList = "recent"; view:RefreshHistory() end, "secondary")
    view.recentHistoryTab:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 140, -124)
    T.StyleTab(view.topHistoryTab); T.StyleTab(view.recentHistoryTab)
    view.clearHistory = T.Button(panel, tr("Clear history"), 138, 26, function()
        view:Confirm({title = "Delete history?", text = "Only the crit/heal history and comparison records of the current character will be deleted.",
            accept = "Delete", variant = "danger", onAccept = function() app:ClearHistory() end})
    end, "danger")
    view.clearHistory:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -124)

    -- The list takes the width of the panel; the rail sits inside the strip right of it.
    local function listWidth() return math.max(100, (panel:GetWidth() or view.formWidth) - 2 * PAD - RAIL - 2) end
    local scroll, content = Window.ScrollArea(panel, view.formWidth - 2 * PAD - RAIL - 2)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -160); scroll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD)
    panel:HookScript("OnSizeChanged", function() scroll:SetContentWidth(listWidth()) end)
    view.historyScroll, view.historyContent = scroll, content
    view.historyEmpty = text(content, "body", "muted", 12, -16)
    view.historyEmpty:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, -16)
    view.historyEmpty:SetHeight(52); view.historyEmpty:SetWordWrap(true)

    page.refresh = function() view:RefreshHistory() end
end
