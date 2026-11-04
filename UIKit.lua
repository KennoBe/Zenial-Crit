local _, NS = ...
local T, I = NS.Theme, NS.Locale
local function tr(value) return I.Text(value) end
-- Widget helpers of the Crit window: labels, buttons, dividers, scrolling, checkboxes, dropdowns, sliders.
local Kit = {}
NS.UIKit = Kit

function Kit.New(ctx)
    local app, api, view = ctx.app, ctx.api, ctx.view

    local function label(parentFrame, value, x, y, width, font, color)
        value = tr(value)
        local f = T and T.Text(parentFrame, value, font, color)
            or parentFrame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
        if not T then f:SetText(value); f:SetJustifyH("LEFT") end
        f:SetPoint("TOPLEFT", x, y); f:SetWidth(width); return f
    end
    local function button(parentFrame, value, x, y, width, action, variant)
        local b = T and T.Button(parentFrame, tr(value), width, 28, action, variant)
            or api:Frame("Button", nil, parentFrame, "UIPanelButtonTemplate")
        if not T then b:SetSize(width, 28); b:SetText(tr(value)); b:SetScript("OnClick", action) end
        b:SetPoint("TOPLEFT", x, y); return b
    end
    local function divider(parentFrame, y)
        local line = T and T.Divider(parentFrame) or parentFrame:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", 16, y); line:SetPoint("TOPRIGHT", -16, y)
        if not T then line:SetHeight(1); line:SetColorTexture(.55, .4, .16, .8) end
    end
    -- Tooltip hint for icon-only buttons; the text is translated when shown.
    local function tip(control, text)
        control.tip = text
        control:HookScript("OnEnter", function(self)
            local tooltip = api.env and api.env.GameTooltip
            if not tooltip or not tooltip.SetOwner then return end
            tooltip:SetOwner(self, "ANCHOR_RIGHT"); tooltip:SetText(tr(self.tip), 1, 1, 1)
            if tooltip.Show then tooltip:Show() end
        end)
        control:HookScript("OnLeave", function()
            local tooltip = api.env and api.env.GameTooltip
            if tooltip and tooltip.Hide then tooltip:Hide() end
        end)
        return control
    end
    -- Native close button when the template exists on this client; otherwise the themed "×" button.
    -- Both run the same handler, so ESC/UISpecialFrames handling stays with the caller's frame.
    local function closeButton(parentFrame, action, x, y, width)
        local ok, native = pcall(api.Frame, api, "Button", nil, parentFrame, "UIPanelCloseButton")
        if ok and type(native) == "table" and native.SetPoint and native.SetScript then
            native.zenialNative = true
            native:SetPoint("TOPRIGHT", -6, -6); native:SetScript("OnClick", action)
            return tip(native, "Close")
        end
        local b = button(parentFrame, "×", x, y, width, action)
        return tip(b, "Close")
    end
    local function closePopups(except)
        for _, popup in ipairs(view.popups) do if popup ~= except then popup:Hide() end end
    end

    local function styleScroll(scroll, step)
        if T then T.StyleScroll(scroll) end
        -- Keep the rail beside the viewport, outside its clipped children.
        local rail = api:Frame("Frame", nil, scroll:GetParent(), BackdropTemplateMixin and "BackdropTemplate" or nil)
        rail:SetWidth(14)
        rail:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, 0)
        rail:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
        rail:SetFrameLevel(scroll:GetFrameLevel() + 3)
        if T then T.Panel(rail, "inset") end
        local bar = api:Frame("Slider", nil, rail)
        bar:SetPoint("TOPLEFT", 1, -16); bar:SetPoint("BOTTOMRIGHT", -1, 16)
        bar:SetOrientation("VERTICAL"); bar:EnableMouse(true); bar:SetValueStep(1)
        local thumb = bar:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(1, .8, .27, 1); thumb:SetSize(10, 24); bar:SetThumbTexture(thumb)
        local up = api:Frame("Button", nil, rail)
        up:SetSize(14, 16); up:SetPoint("TOP")
        up:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
        up:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight", "ADD")
        local down = api:Frame("Button", nil, rail)
        down:SetSize(14, 16); down:SetPoint("BOTTOM")
        down:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        down:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight", "ADD")
        local updating = false
        local function refresh()
            if updating then return end
            updating = true
            local maximum = math.max(0, scroll:GetVerticalScrollRange() or 0)
            local current = scroll:GetVerticalScroll() or 0
            local value = math.max(0, math.min(maximum, current))
            if current ~= value then scroll:SetVerticalScroll(value) end
            bar:SetMinMaxValues(0, maximum); bar:SetValue(value)
            local viewport = math.max(1, scroll:GetHeight())
            local trackHeight = math.max(1, viewport - 32)
            thumb:SetHeight(math.min(trackHeight, math.max(18, trackHeight * viewport / (viewport + maximum))))
            up:SetEnabled(value > 0); down:SetEnabled(value < maximum)
            up:SetAlpha(value > 0 and 1 or .3); down:SetAlpha(value < maximum and 1 or .3)
            rail:SetShown(scroll:IsShown() and maximum > 0)
            updating = false
        end
        local function move(value)
            scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange() or 0, value)))
            refresh()
        end
        bar:SetScript("OnValueChanged", function(_, value) if not updating then move(value) end end)
        up:SetScript("OnClick", function() move((scroll:GetVerticalScroll() or 0) - step) end)
        down:SetScript("OnClick", function() move((scroll:GetVerticalScroll() or 0) + step) end)
        local function wheel(_, delta) move((scroll:GetVerticalScroll() or 0) - delta * step) end
        scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", wheel)
        bar:EnableMouseWheel(true); bar:SetScript("OnMouseWheel", wheel)
        scroll:HookScript("OnVerticalScroll", refresh)
        scroll:HookScript("OnScrollRangeChanged", refresh)
        scroll:HookScript("OnSizeChanged", refresh)
        scroll:HookScript("OnShow", refresh)
        scroll:HookScript("OnHide", function() rail:Hide() end)
        scroll.zenialScrollbar = {rail = rail, slider = bar, thumb = thumb, up = up, down = down}
        scroll.RefreshScrollbar = refresh
        refresh()
    end

    local function checkbox(parentFrame, key, title, x, y, onToggle, labelWidth)
        local c = api:Frame("CheckButton", nil, parentFrame, "UICheckButtonTemplate")
        c:SetSize(24, 24); c:SetPoint("TOPLEFT", x, y)
        if T then T.StyleCheckbox(c) end
        local text = label(parentFrame, title, x + 28, y - 3, labelWidth or 220, "GameFontHighlight", "text")
        c:SetScript("OnClick", function(self)
            local enabled = self:GetChecked() == true
            if onToggle then onToggle(enabled) else app.db[key] = enabled end
            app:Changed()
        end)
        view.controls[#view.controls + 1] = function() c:SetChecked(app.db[key] == true) end
        return c, text
    end

    local function editBox(parentFrame, x, y, width, height, multiline)
        local e = api:Frame("EditBox", nil, parentFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        e:SetPoint("TOPLEFT", x, y); e:SetSize(width, height); e:SetAutoFocus(false)
        e:SetMultiLine(multiline == true); e:SetFontObject("GameFontHighlight")
        if e.SetTextInsets then e:SetTextInsets(8, 8, 5, 5) end
        if T then T.StyleEditBox(e) end
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return e
    end

    local function dropdown(parentFrame, x, y, width, options, getValue, setValue)
        local main, popup, optionButtons
        local function open()
            if popup and popup:IsShown() then popup:Hide(); return end
            if not popup then
                popup = api:Frame("Frame", nil, api:Root(), BackdropTemplateMixin and "BackdropTemplate" or nil)
                popup:SetSize(width, #options * 26 + 10); popup:SetFrameStrata("TOOLTIP"); popup:SetClampedToScreen(true)
                if T then T.Panel(popup, "inset") end
                optionButtons = {}
                for i, option in ipairs(options) do
                    local id = option[1]
                    local b = button(popup, option[2], 5, -5 - (i - 1) * 26, width - 10, function()
                        setValue(id); popup:Hide(); app:Changed()
                    end)
                    b:SetHeight(25); optionButtons[id] = b
                end
                popup:Hide(); view.popups[#view.popups + 1] = popup
            end
            closePopups(popup); popup:ClearAllPoints(); popup:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -3); popup:Show()
        end
        main = button(parentFrame, "", x, y, width, open)
        if T then T.StyleDropdown(main) end
        view.controls[#view.controls + 1] = function()
            local value = getValue()
            for _, option in ipairs(options) do if option[1] == value then main:SetText(tr(option[2])) end end
            if optionButtons and T then
                for id, b in pairs(optionButtons) do T.SetSelected(b, id == value) end
            end
        end
        return main
    end

    local function slider(parentFrame, key, title, x, y, width, minimum, maximum, step, format)
        local function configKey() return type(key) == "function" and key() or key end
        local function upperBound() return type(maximum) == "function" and maximum() or maximum end
        label(parentFrame, title, x, y, width - 64, "GameFontHighlightSmall", "muted")
        local valueText = label(parentFrame, "", x + width - 62, y, 62, "GameFontNormal", "gold")
        valueText:SetJustifyH("RIGHT")
        local s = api:Frame("Slider", nil, parentFrame, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", x, y - 22); s:SetSize(width, 18); s:SetMinMaxValues(minimum, upperBound())
        s:SetValueStep(step); if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
        local updating = false
        s:SetScript("OnValueChanged", function(_, value)
            if updating then return end
            value = math.floor(value / step + .5) * step
            app.db[configKey()] = value; app:Changed()
        end)
        view.controls[#view.controls + 1] = function()
            local value = app.db[configKey()]
            updating = true; s:SetMinMaxValues(minimum, upperBound()); s:SetValue(value); updating = false
            valueText:SetText(string.format(format, value))
        end
        return s
    end

    return {tip = tip, closeButton = closeButton, label = label, button = button, divider = divider, closePopups = closePopups, styleScroll = styleScroll,
        checkbox = checkbox, editBox = editBox, dropdown = dropdown, slider = slider}
end
