local _, NS = ...
local T, I = NS.Theme, NS.Locale
local function tr(value) return I.Text(value) end
-- History page (crit and heal records).
local History = {}
NS.UIHistory = History

function History.Build(ctx)
    local app, api, view, frame, pageWidth, headerHeight = ctx.app, ctx.api, ctx.view, ctx.frame, ctx.pageWidth, ctx.headerHeight
    local kit = ctx.kit
    local label, button, divider, closePopups, styleScroll = kit.label, kit.button, kit.divider, kit.closePopups, kit.styleScroll
    local checkbox, editBox, dropdown, slider = kit.checkbox, kit.editBox, kit.dropdown, kit.slider

    -- History page.
    local historyPage = api:Frame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    historyPage:SetPoint("TOPLEFT", 12, -headerHeight); historyPage:SetPoint("BOTTOMRIGHT", -12, 12)
    if T then T.Panel(historyPage, "inset") end; view.historyPage = historyPage
    view.historyWarning = label(historyPage, "Observed target crits can also come from other players. The Forever client does not provide the attacker or skill.",
        16, -11, pageWidth - 190, "GameFontHighlightSmall", "muted"); view.historyWarning:SetHeight(38)
    view.historyRecording = button(historyPage, "", pageWidth - 154, -9, 138, function() app:SetHistoryEnabled(not app.history.enabled) end)
    local recordCard = api:Frame("Frame", nil, historyPage, BackdropTemplateMixin and "BackdropTemplate" or nil)
    recordCard:SetPoint("TOPLEFT", 16, -51); recordCard:SetPoint("TOPRIGHT", -16, -51); recordCard:SetHeight(62)
    if T then T.Panel(recordCard, "parchment") end
    view.historyBestTitle = label(recordCard, "Highest observed crit", 14, -9, 180, "GameFontHighlightSmall", "muted")
    view.historyBestAmount = label(recordCard, "-", 14, -26, 160, "GameFontNormalLarge", "gold")
    view.historyCharacter = label(recordCard, "", 190, -8, pageWidth - 230, "GameFontHighlightSmall", "muted")
    view.historyBestMeta = label(recordCard, "", 190, -25, pageWidth - 230, "GameFontHighlight", "text"); view.historyBestMeta:SetHeight(30)
    view.topHistoryTab = button(historyPage, "Top 100", 16, -124, 132, function() view.historyList="top"; view:RefreshHistory() end)
    view.recentHistoryTab = button(historyPage, "Latest 100", 156, -124, 132, function() view.historyList="recent"; view:RefreshHistory() end)
    view.clearHistory = button(historyPage, "Clear history", pageWidth - 154, -124, 138, function() view.historyConfirm:Show() end, "danger")
    if T then T.StyleTab(view.topHistoryTab); T.StyleTab(view.recentHistoryTab) end
    local historyScroll = api:Frame("ScrollFrame", nil, historyPage)
    historyScroll:SetPoint("TOPLEFT", 16, -160); historyScroll:SetPoint("BOTTOMRIGHT", -28, 16)
    local historyContent = api:Frame("Frame", nil, historyScroll); historyContent:SetSize(pageWidth - 58, 1); historyScroll:SetScrollChild(historyContent)
    styleScroll(historyScroll, 48)
    view.historyScroll, view.historyContent = historyScroll, historyContent
    view.historyEmpty = label(historyContent, "", 12, -16, pageWidth - 88, "GameFontHighlight", "muted"); view.historyEmpty:SetHeight(52)
    local confirm = api:Frame("Frame", nil, historyPage, BackdropTemplateMixin and "BackdropTemplate" or nil)
    confirm:SetSize(360, 126); confirm:SetPoint("CENTER"); confirm:SetFrameStrata("TOOLTIP")
    if T then T.Panel(confirm, "parchment") end
    local ct = label(confirm, "Delete history?", 18, -15, 324, "GameFontNormalLarge", "gold"); ct:SetJustifyH("CENTER")
    local cx = label(confirm, "Only the crit/heal history and comparison records of the current character will be deleted.", 18, -43, 324, "GameFontHighlightSmall", "muted")
    cx:SetJustifyH("CENTER"); cx:SetHeight(34)
    view.historyConfirmButton = button(confirm, "Delete", 47, -84, 126, function() app:ClearHistory(); confirm:Hide() end, "danger")
    view.historyCancelButton = button(confirm, "Cancel", 187, -84, 126, function() confirm:Hide() end); confirm:Hide(); view.historyConfirm=confirm

    local function formatAmount(value)
        local result=tostring(math.floor(value or 0)); local separator=I.isGerman and "." or ","
        while true do local changed; result,changed=result:gsub("^(%-?%d+)(%d%d%d)","%1"..separator.."%2"); if changed==0 then break end end
        return result
    end
    local function formatDate(value) return api:Date(value,I.isGerman and "%d.%m.%Y %H:%M" or "%Y-%m-%d %H:%M") or tr("Unknown") end
    local function entryArea(value)
        local zone=value.zone~="" and value.zone or tr("Unknown")
        return value.subzone~="" and value.subzone~=value.zone and (zone.." - "..value.subzone) or zone
    end
    local schools={{1,"Physical"},{2,"Holy"},{4,"Fire"},{8,"Nature"},{16,"Frost"},{32,"Shadow"},{64,"Arcane"}}
    local function schoolLabel(value)
        local mask,names=type(value.school)=="number" and math.floor(value.school) or 0,{}
        for _,s in ipairs(schools) do if math.floor(mask/s[1])%2==1 then names[#names+1]=tr(s[2]) end end
        return #names>0 and table.concat(names,"/") or tr("Unknown")
    end
    local function historyRow(index)
        local row=view.historyRows[index]; if row then return row end
        row=api:Frame("Button",nil,historyContent,BackdropTemplateMixin and "BackdropTemplate" or nil)
        row:SetSize(pageWidth-58,46); row:SetPoint("TOPLEFT",0,-(index-1)*50); if T then T.StyleRow(row) end
        row.rank=label(row,"",10,-9,30,"GameFontNormal","muted"); row.amount=label(row,"",42,-8,112,"GameFontNormalLarge","gold")
        row.target=label(row,"",160,-7,pageWidth-385,"GameFontHighlight","text"); row.area=label(row,"",160,-25,pageWidth-385,"GameFontHighlightSmall","muted")
        row.when=label(row,"",pageWidth-210,-14,145,"GameFontHighlightSmall","muted"); row.when:SetJustifyH("RIGHT")
        row:HookScript("OnEnter",function(self)
            local tip=api.env and api.env.GameTooltip; if not self.entry or not tip or not tip.SetOwner then return end
            tip:SetOwner(self,"ANCHOR_RIGHT"); tip:SetText(formatAmount(self.entry.amount),1,.8,.27)
            if tip.AddLine then
                tip:AddLine(tr("Target")..": "..(self.entry.target~="" and self.entry.target or tr("Unknown")),1,1,1)
                tip:AddLine(tr("Time")..": "..formatDate(self.entry.at),.85,.82,.72)
                tip:AddLine(tr("Area")..": "..entryArea(self.entry),.85,.82,.72)
                tip:AddLine(tr(self.kind=="heal" and "Healing school" or "Damage type")..": "..schoolLabel(self.entry),.70,.64,.54)
                tip:AddLine(tr("Skill")..": "..tr(self.kind=="heal" and
                    "Healing spell or triggered healing effect; exact name is not supplied" or
                    "Normal auto hit or client-unassigned bonus damage"),.70,.64,.54)
            end
            if tip.Show then tip:Show() end
        end)
        row:HookScript("OnLeave",function()
            local tip=api.env and api.env.GameTooltip
            if tip and tip.Hide then tip:Hide() end
        end)
        view.historyRows[index]=row; return row
    end

    function view:RefreshHistory()
        if not app.history then return end
        local kind=self.historyKind=="heal" and "heal" or "crit"
        local key=app:EnsureCharacter()
        local values=key and NS.History.Get(app.history,key,self.historyList,kind) or {}
        local best=key and NS.History.Best(app.history,key,kind)
        self.historyWarning:SetText(tr(kind=="heal" and
            "Observed critical heals on your target or yourself can come from other players. Forever does not provide the healer or spell." or
            "Observed target crits can also come from other players. The Forever client does not provide the attacker or skill."))
        self.historyBestTitle:SetText(tr(kind=="heal" and "Highest observed critical heal" or "Highest observed crit"))
        self.historyRecording:SetText(tr("Recording")..": "..tr(app.history.enabled and "On" or "Off"))
        self.historyCharacter:SetText(tr("Current character")..": "..(app.characterName or tr("Unknown")))
        if best then
            self.historyBestAmount:SetText(formatAmount(best.amount))
            self.historyBestMeta:SetText((best.target~="" and best.target or tr("Unknown")).."\n"..formatDate(best.at).." - "..entryArea(best))
        else
            self.historyBestAmount:SetText("-")
            self.historyBestMeta:SetText(tr(kind=="heal" and "No critical heals recorded yet." or "No crits recorded yet."))
        end
        if T then
            T.SetSelected(self.topHistoryTab,self.historyList=="top")
            T.SetSelected(self.recentHistoryTab,self.historyList=="recent")
        end
        self.historyEmpty:SetShown(#values==0)
        self.historyEmpty:SetText(tr(kind=="heal" and "No critical heals recorded yet." or "No crits recorded yet.").."\n"..
            tr("Recording starts with activation; earlier hits cannot be restored."))
        for index,value in ipairs(values) do
            local row=historyRow(index)
            row.entry=value; row.kind=kind
            row.rank:SetText(self.historyList=="top" and (index..".") or "")
            row.amount:SetText(formatAmount(value.amount))
            row.target:SetText(value.target~="" and value.target or tr("Unknown"))
            row.area:SetText(entryArea(value))
            row.when:SetText(formatDate(value.at))
            row:Show()
        end
        for index=#values+1,#self.historyRows do self.historyRows[index]:Hide() end
        historyContent:SetHeight(math.max(1,#values*50))
        if historyScroll.UpdateScrollChildRect then historyScroll:UpdateScrollChildRect() end
    end

end
