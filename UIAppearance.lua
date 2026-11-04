local _, NS = ...
local T, I = NS.Theme, NS.Locale
local function tr(value) return I.Text(value) end
-- Appearance settings page and the draggable fixed-position anchor.
local Appearance = {}
NS.UIAppearance = Appearance

function Appearance.Build(ctx)
    local app, api, view, pageWidth, makePage = ctx.app, ctx.api, ctx.view, ctx.pageWidth, ctx.makePage
    local kit = ctx.kit
    local label, button, divider, closePopups, styleScroll = kit.label, kit.button, kit.divider, kit.closePopups, kit.styleScroll
    local checkbox, editBox, dropdown, slider = kit.checkbox, kit.editBox, kit.dropdown, kit.slider

    -- Appearance.
    local appearance = makePage("appearance", 430)
    label(appearance, "APPEARANCE", 16, -10, 240, "GameFontNormalLarge", "gold")
    label(appearance, "Display mode", 16, -52, 140, "GameFontHighlight", "text")
    view.displayMode = dropdown(appearance, 160, -44, 280,
        {{"nameplate", "Above nameplate"}, {"fixed", "Fixed positions"}},
        function() return app.db.displayMode end, function(value)
            if view.anchor and view.anchor:IsShown() then view:CloseAnchor() end
            app.db.displayMode = value
        end)
    view.sizeSlider = slider(appearance,
        function() return app.db.displayMode == "nameplate" and "nameplateScale" or "scale" end,
        "Size", 16, -104, 280, .6,
        function() return app.db.displayMode == "nameplate" and 4.2 or 2.5 end, .1, "%.1f")
    slider(appearance, "intensity", "Movement", 334, -104, 280, 1, 3, 1, "%.0f")
    divider(appearance, -168)
    -- Keep the checkbox AND its separate label inside the hidden positions group.
    view.fixedPositions = api:Frame("Frame", nil, appearance)
    view.fixedPositions:SetPoint("TOPLEFT", 16, -190); view.fixedPositions:SetSize(610, 74)
    view.positionMode, view.positionModeLabel = checkbox(view.fixedPositions, "separatePositions", "Separate positions", 0, 0, function(enabled)
        if view.anchor and view.anchor:IsShown() then view:CloseAnchor() end
        app.db.separatePositions = enabled
        if not enabled then app.db.x, app.db.y = app.db.critX, app.db.critY end
    end)
    view.sharedPosition = button(view.fixedPositions, "Shared position", 0, -38, 180, function() view:Anchor("shared") end)
    view.critPosition = button(view.fixedPositions, "Crit position", 0, -38, 180, function() view:Anchor("crit") end)
    view.killPosition = button(view.fixedPositions, "Last-hit position", 190, -38, 180, function() view:Anchor("kill") end)
    view.nameplateHint = label(appearance, "Requires a visible nameplate. Without one, only sound is played.",
        16, -190, pageWidth - 82, "GameFontHighlightSmall", "muted")
    view.nameplateHint:SetHeight(54)
    button(appearance, "Crit preview", 16, -276, 180, function() app:Trigger("crit", true, "crit") end, "primary")
    button(appearance, "Kill preview", 206, -276, 180, function() app:Trigger("kill", true, "kill") end, "primary")
    view.controls[#view.controls + 1] = function()
        local fixed = app.db.displayMode == "fixed"
        view.fixedPositions:SetShown(fixed); view.nameplateHint:SetShown(not fixed)
        if not fixed and view.anchor and view.anchor:IsShown() then view:CloseAnchor() end
        view.sharedPosition:SetShown(not app.db.separatePositions)
        view.critPosition:SetShown(app.db.separatePositions); view.killPosition:SetShown(app.db.separatePositions)
    end
    view.automation = label(appearance, "", 16, -326, pageWidth - 82, "GameFontHighlightSmall", "muted")
    view.controls[#view.controls + 1] = function()
        local crit = tr(app.critRegistered and "Target crits on current target" or "UNIT_COMBAT unavailable")
        local kills = tr(app.killRegistered and "own and pet kills" or "PARTY_KILL unavailable")
        view.automation:SetText(tr("Automation") .. ": " .. crit .. " · " .. kills)
    end
end

function Appearance.DefineAnchor(ctx)
    local app, api, view = ctx.app, ctx.api, ctx.view
    local label, closePopups = ctx.kit.label, ctx.kit.closePopups
    function view:Anchor(kind)
        if app.db.displayMode ~= "fixed" then return end
        kind=app.db.separatePositions and kind or "shared"; if kind~="crit" and kind~="kill" then kind="shared" end
        if self.anchor and self.anchor:IsShown() and self.anchorKind==kind then self.anchor:Hide();return end
        if not self.anchor then
            local a=api:Frame("Frame",nil,api:Root(),BackdropTemplateMixin and "BackdropTemplate" or nil);if not a then return end
            self.anchor=a
            a:SetSize(250,72);a:SetClampedToScreen(true);a:SetFrameStrata("TOOLTIP");a:SetMovable(true)
            a:EnableMouse(true);a:RegisterForDrag("LeftButton")
            if T then T.Panel(a,"parchment") end
            self.anchorTitle=label(a,"",16,-22,220,"GameFontNormal");self.anchorTitle:SetJustifyH("CENTER")
            a:SetScript("OnDragStart",function(self)self:StartMoving()end)
            a:SetScript("OnDragStop",function(self)
                self:StopMovingOrSizing()
                local x,y=api:Position(self)
                if x then
                    if view.anchorKind=="crit" then app.db.critX,app.db.critY=x,y
                    elseif view.anchorKind=="kill" then app.db.killX,app.db.killY=x,y
                    else app.db.x,app.db.y=x,y end
                    app:Changed()
                end
            end)
            a:SetScript("OnMouseUp",function(self,mouse)if mouse=="RightButton"then self:Hide()end end)
        end
        self.anchorKind=kind;self.anchor:Show();self:Refresh()
    end
    function view:CloseAnchor()
        closePopups()
        if self.anchor and self.anchor:IsShown() then
            local x,y=api:Position(self.anchor)
            if x then
                if self.anchorKind=="crit" then app.db.critX,app.db.critY=x,y
                elseif self.anchorKind=="kill" then app.db.killX,app.db.killY=x,y
                else app.db.x,app.db.y=x,y end
            end
            self.anchor:Hide()
        end
        if app.db then app.db=NS.Logic.Sanitize(app.db);ZenialCritDB=app.db end
    end
end
