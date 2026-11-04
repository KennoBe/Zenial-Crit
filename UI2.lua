local _, NS = ...
local UI, T, I = {}, NS.Theme, NS.Locale
local function tr(value) return I.Text(value) end
NS.UI = UI

function UI.New(app, parent, embedded)
    local api = app.api
    local view = {
        controls = {}, pages = {}, subTabs = {}, popups = {}, embedded = embedded == true,
        settingsPage = "crit", historyList = "top", historyKind = "crit", soundCategory = "crit",
        soundSource = "all", catalogRows = {}, historyRows = {},
    }
    local frame = api:Frame("Frame", not embedded and "ZenialCritSettings" or nil,
        parent or api:Root(), BackdropTemplateMixin and "BackdropTemplate" or nil)
    if not frame then return nil end
    view.frame = frame
    frame:SetSize(embedded and 816 or 720, embedded and 350 or 520)
    frame:SetClampedToScreen(true)
    if embedded then
        frame:SetPoint("TOPLEFT")
        if parent and parent.GetFrameLevel then frame:SetFrameLevel(parent:GetFrameLevel() + 1) end
        if T then T.Panel(frame, "inset") end
    else
        frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG"); frame:SetMovable(true)
        frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        if T then T.Shell(frame) end
        -- ESC closes the standalone window like other Blizzard panels; the
        -- embedded Community panel belongs to its host and is not registered.
        if type(UISpecialFrames) == "table" then
            local listed = false
            for _, name in ipairs(UISpecialFrames) do if name == "ZenialCritSettings" then listed = true end end
            if not listed then UISpecialFrames[#UISpecialFrames + 1] = "ZenialCritSettings" end
        end
    end
    local ctx = {app = app, api = api, view = view, frame = frame, embedded = embedded}
    local kit = NS.UIKit.New(ctx)
    local label, button, closePopups, styleScroll = kit.label, kit.button, kit.closePopups, kit.styleScroll

    local headerHeight = embedded and 46 or 86
    local pageWidth = embedded and 792 or 696
    if not embedded then
        local icon = frame:CreateTexture(nil, "ARTWORK"); icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 20, -16); icon:SetTexture("Interface\\AddOns\\ZenialCrit\\Media\\Icon.tga")
        label(frame, "ZENIAL CRIT", 58, -18, 440, "GameFontNormalLarge", "gold")
        view.close = kit.closeButton(frame, function() frame:Hide() end, 672, -14, 28)
    end
    local tabY = embedded and -8 or -50
    view.historyTab = button(frame, "Crit history", 16, tabY, 150, function() view:SetPage("history") end)
    view.healHistoryTab = button(frame, "Heal history", 174, tabY, 150, function() view:SetPage("healHistory") end)
    view.settingsTab = button(frame, "Settings", 332, tabY, 150, function() view:SetPage("settings") end)
    if T then
        T.StyleTab(view.historyTab, T.assets.icons.history); T.StyleTab(view.healHistoryTab, T.assets.icons.history)
        T.StyleTab(view.settingsTab, T.assets.icons.addons)
    end

    -- Settings shell: navigation never scrolls, every subpage owns its scroll position.
    local settingsHost = api:Frame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    settingsHost:SetPoint("TOPLEFT", 12, -headerHeight); settingsHost:SetPoint("BOTTOMRIGHT", -12, 12)
    if T then T.Panel(settingsHost, "inset") end
    view.settingsHost = settingsHost
    local subNames = {
        {"crit", "Crit"}, {"heal", "Heal"}, {"kill", "Kill"},
        {"sounds", "Sounds"}, {"chat", "Chat"}, {"appearance", "Appearance"},
    }
    -- Divide the available row by every tab, including Heal and Chat.
    local subWidth = math.floor((pageWidth - 32) / #subNames)
    for index, spec in ipairs(subNames) do
        local key = spec[1]
        local b = button(settingsHost, spec[2], 8 + (index - 1) * subWidth, -8, subWidth - 5,
            function() view:SetSettingsPage(key) end)
        if T then T.StyleTab(b) end
        view.subTabs[key] = b
    end

    local function makePage(key, height)
        local scroll = api:Frame("ScrollFrame", nil, settingsHost)
        scroll:SetPoint("TOPLEFT", 10, -44); scroll:SetPoint("BOTTOMRIGHT", -22, 10)
        local content = api:Frame("Frame", nil, scroll, BackdropTemplateMixin and "BackdropTemplate" or nil)
        content:SetSize(pageWidth - 48, height); scroll:SetScrollChild(content)
        styleScroll(scroll, 40)
        view.pages[key] = {scroll = scroll, content = content}
        return content
    end
    ctx.kit, ctx.pageWidth, ctx.headerHeight, ctx.makePage = kit, pageWidth, headerHeight, makePage

    -- Page construction order is the creation order of the frames.
    NS.UISounds.Define(ctx)
    NS.UIEffects.Build(ctx)
    NS.UISounds.BuildPage(ctx)
    NS.UIAppearance.Build(ctx)
    NS.UISounds.DefineMethods(ctx)
    NS.UIHistory.Build(ctx)

    function view:SetSettingsPage(page)
        if not self.pages[page] then page="crit" end; self.settingsPage=page; closePopups()
        for key,data in pairs(self.pages) do data.scroll:SetShown(key==page); if T then T.SetSelected(self.subTabs[key],key==page) end end
        if page=="sounds" then self:RefreshSounds() end
    end
    function view:SetPage(page)
        if page=="settings" then self.page="settings"
        elseif page=="healHistory" then self.page="healHistory"; self.historyKind="heal"
        else self.page="history"; self.historyKind="crit" end
        closePopups(); self.removeConfirm:Hide()
        if self.page~="settings" and self.anchor and self.anchor:IsShown() then self:CloseAnchor() end
        self.settingsHost:SetShown(self.page=="settings"); self.historyPage:SetShown(self.page~="settings")
        if T then
            T.SetSelected(self.historyTab,self.page=="history"); T.SetSelected(self.healHistoryTab,self.page=="healHistory")
            T.SetSelected(self.settingsTab,self.page=="settings")
        end
        if self.page~="settings" then self:RefreshHistory() else self:SetSettingsPage(self.settingsPage) end
    end
    function view:Refresh()
        for _,update in ipairs(self.controls) do update() end
        self:RefreshHistory(); self:RefreshSounds()
        if self.anchor and self.anchor:IsShown() then
            local x,y;if self.anchorKind=="shared" then x,y=app.db.x,app.db.y else x,y=NS.Logic.Position(app.db,self.anchorKind) end
            self.anchor:ClearAllPoints();self.anchor:SetPoint("CENTER",api:Root(),"CENTER",x,y)
            local titles={shared="Shared effect position - Drag to move",crit="Crit position - Drag to move",kill="Last-hit position - Drag to move"}
            self.anchorTitle:SetText(tr(titles[self.anchorKind] or titles.shared))
        end
    end
    NS.UIAppearance.DefineAnchor(ctx)
    function view:Toggle() if frame:IsShown()then frame:Hide()else self:Refresh();frame:Show()end end
    frame:SetScript("OnHide",function()view:CloseAnchor();view.historyConfirm:Hide();view.removeConfirm:Hide()end)
    if not embedded then frame:Hide() end
    app.views=app.views or {};app.views[#app.views+1]=view;view:SetSettingsPage("crit");view:SetPage("history");view:Refresh();return view
end
