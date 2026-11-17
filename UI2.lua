local _, NS = ...
-- Settings of Crit: the pages are described here and built from the shared Window (frame) and Form (rows). The same
-- description fills the standalone window (/zcrit) and the view embedded in the Community addon manager.
local UI = {}
NS.UI = UI
local T, K, I = NS.Theme, NS.Kit, NS.Locale
local Window, Form = NS.Window, NS.Form
local function tr(value) return I.Text(value) end

-- Order of the navigation. icon: a cell of the icon atlas. form: the module that fills the rows of the page.
UI.Pages = {
    {key = "overview", text = "Overview", icon = "today", form = "UIPageOverview"},
    {key = "events", text = "Events", icon = "bell", form = "UIPageEvents"},
    {key = "appearance", text = "Appearance", icon = "layers", form = "UIPageLook"},
    {key = "animations", text = "Animations", icon = "clock", form = "UIPageMotion"},
    {key = "sounds", text = "Sounds", icon = "note", form = "UIPageSounds"},
    {key = "procs", text = "Procs", icon = "star", form = "UIPageProcs"},
    {key = "profiles", text = "Profiles", icon = "characters", form = "UIPageProfiles", noReset = true},
    {key = "history", text = "History", icon = "history", history = true},
}

local defaults
local function defaultOf(key)
    defaults = defaults or NS.Logic.Defaults()
    return defaults[key]
end

-- The form reads and writes the settings of the active profile; every change goes through app:Changed().
local function formContext(app)
    return {
        tr = tr,
        read = function(key) return app.db and app.db[key] end,
        write = function(key, value) if app.db then app.db[key] = value end end,
        changed = function() app:Changed() end,
        -- The switch is account wide and not a profile key.
        advanced = function() return app.root ~= nil and app.root.advanced == true end,
        default = defaultOf,
    }
end

-- Footer: event choice, preview, note, "Advanced" -------------------------------------------------------
local function buildFooter(view)
    local app, footer = view.app, view.footer
    local function previewOptions()
        local options = {{"crit", tr("Crit")}, {"heal", tr("Heal crit")}, {"kill", tr("Kill")}}
        local texts = app.db and app.db.streakTexts or {}
        local steps = app.db and app.db.streakSteps or {}
        for index = 1, math.min(10, #steps, #texts) do
            options[#options + 1] = {"streak" .. index, string.format(tr("Kill streak: %s"), texts[index])}
        end
        options[#options + 1] = {"proc", tr("Proc")}
        -- Windfury only for a class that can have it: the weapon first, else the totem.
        local windfury = NS.Procs.Available(app.playerClass)
        if windfury.weapon or windfury.totem then
            options[#options + 1] = {windfury.weapon and "windfury" or "windfuryTotem", tr("Windfury")}
        end
        return options
    end
    local function normalizePreviewKey()
        for _, option in ipairs(previewOptions()) do if option[1] == view.previewKey then return end end
        view.previewKey = "crit"
    end
    view.previewSelect = Form.Dropdown(footer, {width = 240, options = previewOptions, translate = false, tr = tr, placement = "up",
        get = function() normalizePreviewKey(); return view.previewKey end,
        set = function(value) view.previewKey = value end})
    view.previewSelect:SetPoint("TOPLEFT", footer, "TOPLEFT", 12, -9)
    view.previewButton = T.Button(footer, tr("Preview"), 110, 26, function()
        local kind, tier = view.previewKey:match("^(streak)(%d+)$")
        local _, note = app:Preview(kind or view.previewKey, tonumber(tier))
        view.previewNote = note
        view:RefreshFooter()
    end, "primary")
    view.previewButton:SetPoint("LEFT", view.previewSelect, "RIGHT", 8, 0)

    -- The box shows the account-wide switch; the caption is part of the click target.
    local holder = CreateFrame("Frame", nil, footer)
    holder:SetSize(110, 28); holder:SetPoint("TOPRIGHT", footer, "TOPRIGHT", -12, -8)
    local check = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
    check:SetSize(24, 24); check:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -2)
    T.StyleCheckbox(check)
    local caption = K.Text(holder, tr("Advanced"), "body", "text")
    caption:SetPoint("TOPLEFT", holder, "TOPLEFT", 30, -7); caption:SetSize(80, 16)
    local function apply(enabled)
        if app.root then app.root.advanced = enabled end
        app:Changed()
    end
    check:SetScript("OnClick", function(box) apply(box:GetChecked() == true) end)
    local hit = CreateFrame("Button", nil, holder)
    hit:SetSize(80, 24); hit:SetPoint("TOPLEFT", holder, "TOPLEFT", 28, -2)
    hit:SetScript("OnClick", function()
        local enabled = not (check:GetChecked() == true)
        check:SetChecked(enabled); apply(enabled)
    end)
    check.zenialLabelHit = hit
    view.advanced = check

    function view:RefreshFooter()
        normalizePreviewKey()
        self.previewSelect:Refresh()
        self.advanced:SetChecked(app.root ~= nil and app.root.advanced == true)
        self:SetNote(self.previewNote == "no_target" and tr("No target: shown at the fixed position.") or "", "warning")
    end
end

-- Pages -------------------------------------------------------------------------------------------------
-- A page with a form: the rows come from the page module, a reset button follows unless the page opts out.
local function formPage(view, spec)
    return function(page)
        local app = view.app
        local form = Form.New(view.formContext, page.content, view.formWidth)
        page.form = form
        NS[spec.form].Build(view, form, page)
        if not spec.noReset then
            form:Card()
            form:Buttons({anchor = "reset", {text = "Reset this page", onClick = function()
                view:Confirm({title = "Reset this page", text = "Reset all settings on this page?", accept = "Reset", variant = "danger",
                    onAccept = function() app:ResetKeys(form:Keys()) end})
            end}})
        end
        page.refresh = function()
            if not app.db then return end
            form:Refresh()
            page.content:SetHeight(math.max(1, form:Height()))
            if page.afterRefresh then page.afterRefresh() end
        end
    end
end

function UI.New(app, parent, embedded)
    embedded = embedded == true and parent ~= nil
    local view
    local pages = {}
    for _, spec in ipairs(UI.Pages) do
        local page = {key = spec.key, title = spec.text, icon = spec.icon}
        if spec.history then
            page.fixed = true
            page.build = function(built) NS.UIHistory.Build(view, built) end
        else
            page.build = function(built) return formPage(view, spec)(built) end
        end
        pages[#pages + 1] = page
    end
    view = Window.New({
        name = "ZenialCritSettings", label = "Crit", version = function() return app.version end, tr = tr, pages = pages,
        -- The room for the footer; its content follows below. The window keeps no position of its own.
        footer = function() end,
        -- An open position marker belongs to the page it was opened from.
        onLeave = function() if view and view.CloseAnchor then view:CloseAnchor() end end,
        onHide = function(shown) if shown and shown.CloseAnchor then shown:CloseAnchor() end end,
    }, embedded and parent or nil)
    if not view then return nil end
    view.app, view.api, view.embedded = app, app.api, embedded
    view.formContext = formContext(app)
    view.kind, view.previewKey, view.historyList, view.historyKind = "crit", "crit", "top", "crit"
    view.soundCategory, view.soundSource, view.catalogRows, view.historyRows = "crit", "all", {}, {}
    NS.UISounds.DefineMethods(view)
    NS.UIAnchor.Define(view)
    NS.UIHistory.Define(view)
    buildFooter(view)

    -- The footer and the page follow every refresh.
    local refresh = view.Refresh
    function view:Refresh()
        if not app.db then return end
        refresh(self)
        self:RefreshFooter()
        self:RefreshAnchor()
    end

    app.views = app.views or {}; app.views[#app.views + 1] = view
    return view
end
