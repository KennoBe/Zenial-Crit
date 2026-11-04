local _, NS = ...
local T, I = NS.Theme, NS.Locale
local function tr(value) return I.Text(value) end
-- Crit/Kill effect pages plus the Heal and Chat settings pages.
local Effects = {}
NS.UIEffects = Effects

function Effects.Build(ctx)
    local app, api, view, pageWidth, makePage = ctx.app, ctx.api, ctx.view, ctx.pageWidth, ctx.makePage
    local kit = ctx.kit
    local label, button, divider, closePopups, styleScroll = kit.label, kit.button, kit.divider, kit.closePopups, kit.styleScroll
    local checkbox, editBox, dropdown, slider = kit.checkbox, kit.editBox, kit.dropdown, kit.slider
    local soundDropdown = ctx.soundDropdown

    local function chooseColor(key)
        local picker = api.env and api.env.ColorPickerFrame
        if not picker then return end
        local original = {app.db[key][1], app.db[key][2], app.db[key][3]}
        local function apply(r, g, b)
            if type(r) ~= "number" and type(picker.GetColorRGB) == "function" then
                local ok; ok, r, g, b = pcall(picker.GetColorRGB, picker); if not ok then return end
            end
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                app.db[key] = {r, g, b}; app:Changed()
            end
        end
        local info = {r=original[1], g=original[2], b=original[3], hasOpacity=false,
            swatchFunc=function() apply() end,
            cancelFunc=function() app.db[key] = original; app:Changed() end}
        if type(picker.SetupColorPickerAndShow) == "function" and pcall(picker.SetupColorPickerAndShow, picker, info) then return end
        picker.func, picker.swatchFunc, picker.cancelFunc = info.swatchFunc, info.swatchFunc, info.cancelFunc
        if picker.SetColorRGB then pcall(picker.SetColorRGB, picker, unpack(original)) end
        if picker.Hide then picker:Hide() end; if picker.Show then picker:Show() end
    end

    local fontOptions = {{"standard","Standard"},{"comic","Comic"},{"epic","Epic"},{"heavy","Heavy"}}

    local function effectPage(kind)
        local compact = pageWidth < 740
        local content = makePage(kind, compact and (kind == "crit" and 740 or 580) or (kind == "crit" and 600 or 430))
        local graphicsKey, soundKey = kind .. "Graphics", kind .. "Sound"
        local fontKey, colorKey, textsKey = kind .. "Font", kind .. "Color", kind .. "Texts"
        label(content, kind == "crit" and "CRIT" or "LAST HIT", 16, -10, 230, "GameFontNormalLarge", "gold")
        local rightX = compact and 16 or 335
        local rightY = compact and -275 or -48
        checkbox(content, graphicsKey, "Show graphic", 16, -46)
        checkbox(content, soundKey, "Play sound", 16, -78)
        local colorControl = button(content, "Color", 16, -112, 130, function() chooseColor(colorKey) end)
        view.colorButtons = view.colorButtons or {}; view.colorButtons[kind] = colorControl
        label(content, kind == "crit" and "Effect & damage font" or "Font style", 158, -108, 150, "GameFontHighlightSmall", "muted")
        local fontChoice = dropdown(content, 158, -128, 152, fontOptions, function() return app.db[fontKey] end,
            function(value) app.db[fontKey] = value end)
        if kind == "crit" then
            fontChoice:HookScript("OnEnter",function(self)
                local tip=api.env and api.env.GameTooltip; if not tip or not tip.SetOwner then return end
                tip:SetOwner(self,"ANCHOR_RIGHT")
                tip:SetText(tr("Normal damage numbers use this font too. Log out to character selection and log back in to apply a change."),1,1,1,true)
                if tip.Show then tip:Show()end
            end)
            fontChoice:HookScript("OnLeave",function()local tip=api.env and api.env.GameTooltip;if tip and tip.Hide then tip:Hide()end end)
        end
        local preview = api:Frame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
        preview:SetPoint("TOPLEFT", 16, -168); preview:SetSize(294, 92); if T then T.Panel(preview, "parchment") end
        local previewText = label(preview, kind == "crit" and "CRIT!" or "KILL!", 8, -16, 278, "GameFontNormalLarge", "gold")
        previewText:SetHeight(60); previewText:SetJustifyH("CENTER"); previewText:SetJustifyV("MIDDLE")
        view.controls[#view.controls + 1] = function()
            local font, size, flags = api:FontStyle(app.db[fontKey])
            pcall(previewText.SetFont, previewText, font, math.min(size, 28), flags)
            previewText:SetTextColor(NS.Logic.Color(app.db, kind))
            previewText:SetText((app.db[textsKey] and app.db[textsKey][1]) or (kind == "crit" and "CRIT!" or "KILL!"))
        end
        label(content, "Selected sound", rightX, rightY, 285, "GameFontHighlightSmall", "muted")
        soundDropdown(content, kind, rightX, rightY - 21, 284)
        button(content, "Sound library", rightX, rightY - 57, 142, function()
            view.soundCategory = kind; view:SetSettingsPage("sounds")
        end)
        button(content, "Listen", rightX + 152, rightY - 57, 132, function()
            local ok, reason = app:PreviewSound(kind); view:SetSoundStatus(ok, reason)
        end)
        button(content, "Show effect", rightX, rightY - 92, 284,
            function() app:Trigger(kind, true, kind) end, "primary")
        local textY = compact and -430 or -286
        divider(content, textY + 17); label(content, "RANDOM TEXTS", 16, textY, 200, "GameFontNormalLarge", "gold")
        label(content, "One line per text. A variant is randomly selected for each effect.", 16, textY - 27, 610, "GameFontHighlightSmall", "muted")
        local e = editBox(content, 16, textY - 51, pageWidth - 82, 76, true); e:SetMaxLetters(820)
        view[textsKey] = e
        e:SetScript("OnTextChanged", function(self, userInput) if userInput then app:TextsChanged(textsKey, self:GetText(), view) end end)
        view.controls[#view.controls + 1] = function() if not e:HasFocus() then e:SetText(NS.Logic.JoinTexts(app.db[textsKey])) end end
        if kind == "crit" then
            local ruleY = compact and -580 or -430
            divider(content, ruleY + 15); label(content, "RECORD RULES", 16, ruleY, 220, "GameFontNormalLarge", "gold")
            label(content, "Crit sound mode", 16, ruleY - 31, 160, "GameFontHighlightSmall", "muted")
            dropdown(content, 16, ruleY - 51, 180, {{"all","All crits"},{"records","Records only"}},
                function() return app.db.critSoundRule end, function(value) app.db.critSoundRule = value end)
            view.recordToggle, view.recordToggleLabel = checkbox(content, "recordSoundEnabled", "Own record sound", 220, ruleY - 45, nil, 190)
            view.lowToggle, view.lowToggleLabel = checkbox(content, "lowCritEnabled", "Weak crit sound", 220, ruleY - 79, nil, 190)
            view.recordSoundButton = button(content, "Record sound", 455, ruleY - 47, 175, function() view.soundCategory="record"; view:SetSettingsPage("sounds") end)
            view.lowSoundButton = button(content, "Weak sound choice", 455, ruleY - 81, 175, function() view.soundCategory="low"; view:SetSettingsPage("sounds") end)
            slider(content, "lowCritPercent", "Weak up to percent of record", 16, ruleY - 104, 400, 1, 100, 1, "%d %%")
        end
        return content
    end
    effectPage("crit"); effectPage("kill")

    local heal = makePage("heal", 520)
    label(heal, "HEAL", 16, -10, 230, "GameFontNormalLarge", "gold")
    local healInfo = label(heal, "Observed critical heals on your target or yourself are recorded. Forever does not identify the healer or spell.",
        16, -42, pageWidth - 82, "GameFontHighlightSmall", "muted"); healInfo:SetHeight(36)
    checkbox(heal, "healSound", "Play heal sound", 16, -84)
    label(heal, "Selected sound", 16, -120, 285, "GameFontHighlightSmall", "muted")
    soundDropdown(heal, "heal", 16, -141, 300)
    button(heal, "Sound library", 330, -141, 142, function()
        view.soundCategory = "heal"; view:SetSettingsPage("sounds")
    end)
    button(heal, "Listen", 482, -141, 142, function()
        local ok, reason = app:PreviewSound("heal"); view:SetSoundStatus(ok, reason)
    end)
    divider(heal, -188); label(heal, "HEAL RECORD RULES", 16, -204, 260, "GameFontNormalLarge", "gold")
    label(heal, "Heal sound mode", 16, -238, 180, "GameFontHighlightSmall", "muted")
    dropdown(heal, 16, -258, 200, {{"all","All heals"},{"records","Records only"}},
        function() return app.db.healSoundRule end, function(value) app.db.healSoundRule = value end)
    view.healRecordToggle, view.healRecordToggleLabel = checkbox(heal, "healRecordSoundEnabled", "Own heal record sound", 236, -252, nil, 190)
    view.healLowToggle, view.healLowToggleLabel = checkbox(heal, "healLowEnabled", "Weak heal sound", 236, -286, nil, 190)
    view.healRecordSoundButton = button(heal, "Heal record sound", 455, -254, 175, function()
        view.soundCategory="healRecord"; view:SetSettingsPage("sounds")
    end)
    view.healLowSoundButton = button(heal, "Weak heal choice", 455, -288, 175, function()
        view.soundCategory="healLow"; view:SetSettingsPage("sounds")
    end)
    slider(heal, "healLowPercent", "Weak up to percent of heal record", 16, -326, 400, 1, 100, 1, "%d %%")

    local chat = makePage("chat", 430)
    label(chat, "LOCAL CHAT MESSAGES", 16, -10, 300, "GameFontNormalLarge", "gold")
    local chatInfo = label(chat, "Messages are only written to your own chat window and are never sent to other players.",
        16, -40, pageWidth - 82, "GameFontHighlightSmall", "muted"); chatInfo:SetHeight(34)
    checkbox(chat, "chatEnabled", "Enable local chat messages", 16, -78)
    divider(chat, -116)
    label(chat, "DAMAGE", 16, -132, 180, "GameFontNormal", "gold")
    checkbox(chat, "chatCrit", "Normal crits", 16, -160)
    checkbox(chat, "chatRecord", "Crit records", 16, -194)
    checkbox(chat, "chatLow", "Weak crits", 16, -228)
    label(chat, "HEALING", 330, -132, 180, "GameFontNormal", "gold")
    checkbox(chat, "chatHeal", "Normal heal crits", 330, -160)
    checkbox(chat, "chatHealRecord", "Heal records", 330, -194)
    checkbox(chat, "chatHealLow", "Weak heal crits", 330, -228)
    divider(chat, -274)
    label(chat, "KILLS", 16, -290, 180, "GameFontNormal", "gold")
    checkbox(chat, "chatKill", "Own and pet kills", 16, -318)
end
