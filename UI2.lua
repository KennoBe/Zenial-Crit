local _, NS = ...
local UI, T, I = {}, NS.Theme, NS.Locale
local function tr(value) return I.Text(value) end
NS.UI = UI

local WIDTH, HEIGHT = 880, 600
local NAV_WIDTH, FOOTER_HEIGHT, FORM_WIDTH, PAGE_WIDTH = 150, 44, 640, 690

-- Order of the navigation. icon: a cell of the Crit icon atlas (standalone window only).
UI.Pages = {
    {key = "overview", text = "Overview", icon = "today", form = "UIPageOverview"},
    {key = "events", text = "Events", icon = "bell", form = "UIPageEvents"},
    {key = "appearance", text = "Appearance", icon = "layers", form = "UIPageLook"},
    {key = "animations", text = "Animations", icon = "clock", form = "UIPageMotion"},
    {key = "sounds", text = "Sounds", icon = "note", sounds = true},
    {key = "profiles", text = "Profiles", icon = "characters", form = "UIPageProfiles", noReset = true},
    {key = "history", text = "History", icon = "history", history = true},
}

-- Text (translated) of a label that may be a function returning text and format arguments.
local function resolve(value, ...)
    local args = {n = select("#", ...), ...}
    if type(value) == "function" then
        args = {value()}
        args.n = #args
        value = table.remove(args, 1)
        args.n = math.max(0, args.n - 1)
    end
    if type(value) ~= "string" then return "" end
    value = tr(value)
    if args.n > 0 then
        local ok, text = pcall(string.format, value, unpack(args, 1, args.n))
        if ok then value = text end
    end
    return value
end

function UI.New(app, parent, embedded)
    local api = app.api
    embedded = embedded == true
    local view = {
        app = app, api = api, embedded = embedded, controls = {}, pages = {}, nav = {}, popups = {},
        page = "overview", kind = "crit", previewKey = "crit", historyList = "top", historyKind = "crit",
        soundCategory = "crit", soundSource = "all", catalogRows = {}, historyRows = {},
    }
    local frame = api:Frame("Frame", not embedded and "ZenialCritSettings" or nil,
        parent or api:Root(), BackdropTemplateMixin and "BackdropTemplate" or nil)
    if not frame then return nil end
    view.frame = frame
    if embedded then
        -- The host sets the anchors and strata itself; every region below is anchored to this frame.
        frame:SetSize(856, 520)
        frame:SetPoint("TOPLEFT")
        if parent and parent.GetFrameLevel then frame:SetFrameLevel(parent:GetFrameLevel() + 1) end
    else
        frame:SetSize(WIDTH, HEIGHT)
        frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG"); frame:SetMovable(true); frame:SetClampedToScreen(true)
        frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        if T then T.Window(frame) end
        -- ESC closes the standalone window like other Blizzard panels; the embedded Community
        -- panel belongs to its host and is not registered.
        if type(UISpecialFrames) == "table" then
            local listed = false
            for _, name in ipairs(UISpecialFrames) do if name == "ZenialCritSettings" then listed = true end end
            if not listed then UISpecialFrames[#UISpecialFrames + 1] = "ZenialCritSettings" end
        end
    end

    local ctx = {app = app, api = api, view = view, frame = frame, embedded = embedded, pageWidth = PAGE_WIDTH}
    local kit = NS.UIKit.New(ctx)
    ctx.kit = kit
    local label, button, closePopups, styleScroll = kit.label, kit.button, kit.closePopups, kit.styleScroll
    view.kit = kit

    -- Regions ---------------------------------------------------------------------------------
    local area = api:Frame("Frame", nil, frame)
    if embedded then
        area:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -36); area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    else
        area:SetPoint("TOPLEFT", frame, "TOPLEFT", NAV_WIDTH + 24, -64); area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    end
    view.area = area
    local footer = api:Frame("Frame", nil, area, BackdropTemplateMixin and "BackdropTemplate" or nil)
    footer:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 0, 0); footer:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_HEIGHT)
    if T then T.Panel(footer, "surface") end
    view.footer = footer
    local pageHost = api:Frame("Frame", nil, area)
    pageHost:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0); pageHost:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, FOOTER_HEIGHT + 8)
    view.pageHost = pageHost

    -- Header (standalone) and navigation ------------------------------------------------------
    local function navigate(key) return function() view:SetPage(key) end end
    if not embedded then
        local icon = frame:CreateTexture(nil, "ARTWORK"); icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 20, -16); icon:SetTexture("Interface\\AddOns\\ZenialCrit\\Media\\Icon.tga")
        label(frame, "ZENIAL CRIT", 58, -18, 150, "GameFontNormalLarge", "gold")
        view.version = label(frame, "v" .. tostring(app.version or ""), 210, -22, 120, "GameFontHighlightSmall", "muted")
        view.close = kit.closeButton(frame, function() frame:Hide() end, WIDTH - 48, -14, 28)
        for index, page in ipairs(UI.Pages) do
            local entry = button(frame, page.text, 12, -64 - (index - 1) * 38, NAV_WIDTH, navigate(page.key))
            entry:SetHeight(34)
            if T then T.StyleNav(entry, page.icon); T.SetSelected(entry, false) end
            view.nav[page.key] = entry
        end
    else
        local tabRow = api:Frame("Frame", nil, frame)
        tabRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); tabRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); tabRow:SetHeight(30)
        view.tabRow = tabRow
        for _, page in ipairs(UI.Pages) do
            local tab = button(tabRow, page.text, 0, 0, 100, navigate(page.key))
            tab:SetHeight(28)
            if T then T.StyleTab(tab); T.SetSelected(tab, false) end
            view.nav[page.key] = tab
        end
    end
    -- Tabs share the width of the frame; called again whenever the host changes the size.
    function view:LayoutTabs()
        if not self.tabRow then return end
        local count = #UI.Pages
        local width = math.floor((frame:GetWidth() or 856) / count)
        for index, page in ipairs(UI.Pages) do
            local tab = self.nav[page.key]
            tab:ClearAllPoints(); tab:SetPoint("TOPLEFT", self.tabRow, "TOPLEFT", (index - 1) * width, -1)
            tab:SetSize(width, 28)
        end
    end
    view:LayoutTabs()
    frame:HookScript("OnSizeChanged", function() view:LayoutTabs() end)

    -- Pages -----------------------------------------------------------------------------------
    -- A scrolling page: viewport anchored to the page area, content of a fixed width inside it.
    local function makePage(key, height, width)
        local scroll = api:Frame("ScrollFrame", nil, pageHost)
        scroll:SetPoint("TOPLEFT", pageHost, "TOPLEFT", 0, 0); scroll:SetPoint("BOTTOMRIGHT", pageHost, "BOTTOMRIGHT", -18, 0)
        local content = api:Frame("Frame", nil, scroll, BackdropTemplateMixin and "BackdropTemplate" or nil)
        content:SetSize(width or FORM_WIDTH, height or 1); scroll:SetScrollChild(content)
        styleScroll(scroll, 40)
        scroll:Hide()
        view.pages[key] = view.pages[key] or {}
        local page = view.pages[key]
        page.scroll, page.content = scroll, content
        return content
    end
    ctx.makePage = makePage
    ctx.historyHost = api:Frame("Frame", nil, pageHost)
    ctx.historyHost:SetAllPoints(pageHost); ctx.historyHost:Hide()

    local formContext = {app = app, api = api, tr = tr,
        advanced = function() return app.root ~= nil and app.root.advanced == true end}
    for _, spec in ipairs(UI.Pages) do
        if spec.form then
            local content = makePage(spec.key, 1, FORM_WIDTH)
            local form = NS.UIForm.New(formContext, content, FORM_WIDTH)
            local page = view.pages[spec.key]
            page.form = form
            NS[spec.form].Build(view, form)
            if not spec.noReset then
                form:Card()
                form:Buttons({{text = "Reset this page", onClick = function()
                    view:Confirm({title = "Reset this page", text = "Reset all settings on this page?", confirm = "Reset",
                        onConfirm = function() app:ResetKeys(form:Keys()) end})
                end}})
            end
            page.refresh = function() form:Refresh() end
        end
    end
    NS.UISounds.Define(ctx)
    NS.UISounds.BuildPage(ctx)
    view.pages.sounds.refresh = function() view:RefreshSounds() end
    NS.UISounds.DefineMethods(ctx)
    NS.UIHistory.Build(ctx)
    view.pages.history = {frame = ctx.historyHost, refresh = function() view:RefreshHistory() end}
    NS.UIAnchor.Define(ctx)

    -- Confirmation dialog shared by every question ---------------------------------------------
    local dialog = api:Frame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    dialog:SetSize(410, 150); dialog:SetPoint("CENTER", area, "CENTER", 0, 0); dialog:SetFrameStrata("TOOLTIP")
    dialog:EnableMouse(true)
    if T then T.Shell(dialog) end
    dialog.title = label(dialog, "", 18, -18, 374, "GameFontNormalLarge", "gold"); dialog.title:SetJustifyH("CENTER")
    dialog.text = label(dialog, "", 18, -48, 374, "GameFontHighlightSmall", "muted")
    dialog.text:SetJustifyH("CENTER"); dialog.text:SetHeight(50)
    dialog.yes = button(dialog, "Delete", 58, -108, 136, function()
        local action = dialog.onConfirm
        dialog:Hide(); dialog.onConfirm = nil
        if action then action() end
    end, "danger")
    dialog.no = button(dialog, "Cancel", 216, -108, 136, function() dialog:Hide(); dialog.onConfirm = nil end)
    dialog:Hide()
    view.confirmDialog = dialog
    -- spec: title, text (key or function returning key and format arguments), confirm (key), onConfirm.
    function view:Confirm(spec)
        closePopups(); self:ClosePagePopups()
        dialog.title:SetText(resolve(spec.title)); dialog.text:SetText(resolve(spec.text))
        dialog.yes:SetText(tr(spec.confirm or "Delete")); dialog.onConfirm = spec.onConfirm
        dialog:Show()
    end

    -- Footer: event choice, preview, "Advanced" ------------------------------------------------
    local function previewOptions()
        local options = {{"crit", tr("Crit")}, {"heal", tr("Heal crit")}, {"kill", tr("Kill")}}
        local texts = app.db and app.db.streakTexts or {}
        for index = 1, math.min(5, #texts) do
            options[#options + 1] = {"streak" .. index, string.format(tr("Kill streak: %s"), texts[index])}
        end
        options[#options + 1] = {"proc", tr("Proc")}
        return options
    end
    local function normalizePreviewKey()
        for _, option in ipairs(previewOptions()) do if option[1] == view.previewKey then return end end
        view.previewKey = "crit"
    end
    view.previewSelect = kit.dropdown(footer, 12, -8, 240, previewOptions,
        function() normalizePreviewKey(); return view.previewKey end, function(value) view.previewKey = value end, "up")
    view.previewButton = button(footer, "Preview", 260, -8, 110, function()
        local kind, tier = view.previewKey:match("^(streak)(%d+)$")
        local ok, note = app:Preview(kind or view.previewKey, tonumber(tier))
        view.previewNote = note
        view:RefreshFooter()
    end, "primary")
    view.previewHint = label(footer, "", 380, -7, 170, "GameFontHighlightSmall", "warning")
    view.previewHint:SetHeight(30)
    if T then T.Font(view.previewHint, "caption", "warning") end
    local advancedHolder = api:Frame("Frame", nil, footer)
    advancedHolder:SetSize(120, 28); advancedHolder:SetPoint("TOPRIGHT", footer, "TOPRIGHT", -12, -8)
    view.advanced = kit.checkbox(advancedHolder, "advanced", "Advanced", 0, 0, function(enabled)
        if app.root then app.root.advanced = enabled end
    end, 90)
    -- The box shows the account-wide switch, not a profile key.
    view.controls[#view.controls] = function() view.advanced:SetChecked(app.root ~= nil and app.root.advanced == true) end

    function view:RefreshFooter()
        self.previewHint:SetText(self.previewNote == "no_target" and tr("No target: shown at the fixed position.") or "")
    end

    -- Navigation, refresh, scale ---------------------------------------------------------------
    function view:ClosePagePopups()
        for _, page in pairs(self.pages) do if page.form then page.form:ClosePopups() end end
        if self.historyForm then self.historyForm:ClosePopups() end
    end

    function view:SetPage(name)
        local found = false
        for _, spec in ipairs(UI.Pages) do if spec.key == name then found = true end end
        if not found then name = "overview" end
        self.page = name
        closePopups(); self:ClosePagePopups(); dialog:Hide()
        if self.anchor and self.anchor:IsShown() then self:CloseAnchor() end
        for key, page in pairs(self.pages) do
            local region = page.scroll or page.frame
            if region then region:SetShown(key == name) end
            if T and self.nav[key] then T.SetSelected(self.nav[key], key == name) end
        end
        self:Refresh()
    end

    function view:Refresh()
        if not app.db then return end
        normalizePreviewKey()
        for _, update in ipairs(self.controls) do update() end
        local page = self.pages[self.page]
        if page and page.refresh then page.refresh() end
        self:RefreshFooter()
        self:RefreshAnchor()
    end

    function view:Toggle()
        if frame:IsShown() then frame:Hide() else self:Refresh(); frame:Show() end
    end

    -- A window larger than the screen shrinks to fit.
    function view:FitScale()
        local root = api:Root()
        local height, width = root and root:GetHeight() or HEIGHT + 40, root and root:GetWidth() or WIDTH + 40
        return math.min(1, (height - 40) / HEIGHT, (width - 40) / WIDTH)
    end
    if not embedded then frame:SetScript("OnShow", function() frame:SetScale(view:FitScale()) end) end

    frame:SetScript("OnHide", function() view:CloseAnchor(); dialog:Hide(); view:ClosePagePopups() end)
    if not embedded then frame:Hide() end
    app.views = app.views or {}; app.views[#app.views + 1] = view
    view:SetPage("overview")
    return view
end
