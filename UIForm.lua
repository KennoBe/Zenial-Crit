local _, NS = ...
-- Row layout for the settings pages: cards with rows that are stacked instead of placed by coordinates.
-- Rows can be hidden (visible / advanced) and the rest moves up. Uses the Crit theme (tokens and skin), the
-- translation function of the caller and the plain frame API; it does not depend on the UIKit module.
local Form = {}
NS.UIForm = Form
Form.__index = Form

local CARD_PAD, CARD_GAP, TITLE_GAP = 16, 12, 8
local ROW, ROW_DESC = 34, 50
local GAP = 16                         -- between a label and its control
local SELECT_W, SELECT_H = 260, 26
local SLIDER_W, SLIDER_H, VALUE_W = 200, 16, 52
local SEGMENT_W, SEGMENT_H = 300, 26
local SWATCH_W, SWATCH_H = 40, 22
local INPUT_W, INPUT_H = 260, 24
local TEXTS_MIN, TEXTS_PAD = 60, 8   -- multi-line fields size themselves by their content
local BUTTON_H, BUTTON_GAP, BUTTON_MIN = 26, 8, 120
local POPUP_ROW, POPUP_MAX = 22, 10

local active -- the form that currently shows a popup (only one popup is open at a time)

local function theme() return NS.Theme end

local function pack(...) return { n = select("#", ...), ... } end

local UMLAUTS = { ["\195\164"] = "\195\132", ["\195\182"] = "\195\150", ["\195\188"] = "\195\156" }
local function upper(value)
    return (string.upper(value):gsub("\195[\164\182\188]", UMLAUTS))
end

local function round(value, step, minimum)
    local snapped = minimum + math.floor((value - minimum) / step + .5) * step
    return tonumber(string.format("%.8g", snapped))
end

-- Text of a label, description or button: string or function (text, format arguments...), translated first,
-- placeholders filled in afterwards.
local function resolve(self, value, ...)
    local args = pack(...)
    if type(value) == "function" then
        args = pack(value())
        value = table.remove(args, 1)
        args.n = math.max(0, args.n - 1)
    end
    if type(value) ~= "string" then return "" end
    value = self.tr(value)
    if args.n > 0 then
        local ok, text = pcall(string.format, value, unpack(args, 1, args.n))
        if ok then value = text end
    end
    return value
end

local function tint(region, method, key, alpha) return theme().Tint(region, method, key, alpha) end

local function newText(parent, role, colorKey, width, height, wrap)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    if width then fs:SetWidth(width) end
    if height then fs:SetHeight(height) end
    fs:SetWordWrap(wrap == true)
    theme().Font(fs, role, colorKey)
    return fs
end

local function keyOf(spec)
    if type(spec.key) == "function" then return spec.key() end
    return spec.key
end

function Form.New(ctx, parent, width)
    local self = setmetatable({}, Form)
    self.ctx, self.parent = ctx, parent
    self.width = width or 640
    self.inner = self.width - 2 * CARD_PAD
    self.tr = ctx.tr or function(value) return value end
    self.cards, self.height = {}, 0
    self.measure = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.measure:Hide()
    if parent.HookScript then parent:HookScript("OnHide", function() self:ClosePopups() end) end
    return self
end

-- ---------------------------------------------------------------------------------------------
-- Values
-- ---------------------------------------------------------------------------------------------
function Form:Read(row, heldKey)
    local spec = row.spec
    if spec.get then return spec.get() end
    local key = heldKey or keyOf(spec)
    if key == nil then return nil end
    return self.ctx.app.db[key]
end

-- Writes a value (and only then calls onChange and the change notification). Nothing is written while the
-- form refreshes: client widgets report a change when they are set from code. A key kept earlier by the
-- caller wins over the row key, which can change (event kind) while a field or the colour picker is open.
function Form:Commit(row, value, key)
    if self.refreshing then return end
    local spec = row.spec
    if spec.set then spec.set(value) else self.ctx.app.db[key or keyOf(spec)] = value end
    if spec.onChange then spec.onChange(value) end
    if self.ctx.changed then self.ctx.changed() else self.ctx.app:Changed() end
    self:Update(row)
end

function Form:Update(row)
    if not row.update then return end
    local previous = self.refreshing
    self.refreshing = true
    local ok, err = pcall(row.update)
    self.refreshing = previous
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------------------------
-- Cards and rows
-- ---------------------------------------------------------------------------------------------
function Form:Card(title)
    local T = theme()
    local frame = CreateFrame("Frame", nil, self.parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetWidth(self.width)
    T.Panel(frame, "surface")
    local card = { frame = frame, rows = {}, title = title }
    if title then
        card.titleText = newText(frame, "overline", "goldDim", self.inner, T.type.overline.size + 2, false)
        card.titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PAD, -CARD_PAD)
        card.titleText:SetText(upper(self.tr(title)))
        card.top = CARD_PAD + T.type.overline.size + 2 + TITLE_GAP
    else
        card.top = CARD_PAD
    end
    frame:Hide()
    self.cards[#self.cards + 1] = card
    self.current = card
    return card
end

local function addRow(self, kind, spec, frameType)
    spec = spec or {}
    local card = self.current or self:Card()
    local frame = CreateFrame(frameType or "Frame", nil, card.frame)
    frame:SetWidth(self.inner)
    local row = { kind = kind, spec = spec, frame = frame, card = card }
    card.rows[#card.rows + 1] = row
    return row
end

-- label (left) and optional description below it
local function addLabels(self, row, labelX, labelWidth)
    local frame = row.frame
    row.label = newText(frame, "body", "text", labelWidth, 16, false)
    row.label:SetPoint("TOPLEFT", frame, "TOPLEFT", labelX, -10)
    row.desc = newText(frame, "caption", "dim", labelWidth, 24, true)
    row.desc:SetPoint("TOPLEFT", frame, "TOPLEFT", labelX, -27)
    if row.desc.SetMaxLines then row.desc:SetMaxLines(2) end
    row.desc:Hide()
end

local function refreshLabels(self, row)
    local spec = row.spec
    if row.label then row.label:SetText(resolve(self, spec.label)) end
    local description = spec.desc ~= nil and resolve(self, spec.desc) or ""
    row.hasDesc = description ~= ""
    if row.desc then
        row.desc:SetText(description)
        row.desc:SetShown(row.hasDesc)
    end
end

local function plainHeight(row) return row.hasDesc and ROW_DESC or ROW end

-- Toggle -------------------------------------------------------------------------------------
function Form:Toggle(spec)
    local T = theme()
    local row = addRow(self, "Toggle", spec, "Button")
    addLabels(self, row, 28, self.inner - 28)
    local check = CreateFrame("CheckButton", nil, row.frame, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, -5)
    T.StyleCheckbox(check)
    check:SetScript("OnClick", function(box) self:Commit(row, box:GetChecked() == true) end)
    -- The whole row is a click target, not only the box.
    row.frame:SetScript("OnClick", function()
        if self.refreshing then return end
        local value = not (self:Read(row) == true)
        check:SetChecked(value)
        self:Commit(row, value)
    end)
    row.control = check
    row.update = function()
        refreshLabels(self, row)
        check:SetChecked(self:Read(row) == true)
    end
    row.height = function() return plainHeight(row) end
    return row
end

-- Slider -------------------------------------------------------------------------------------
function Form:Slider(spec)
    local T = theme()
    local row = addRow(self, "Slider", spec)
    addLabels(self, row, 0, self.inner - SLIDER_W - VALUE_W - 8 - GAP)
    local slider = CreateFrame("Slider", nil, row.frame)
    slider:SetSize(SLIDER_W, SLIDER_H)
    slider:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", -(VALUE_W + 8), -9)
    slider:SetOrientation("HORIZONTAL")
    -- Without a template a slider is not mouse-active; the wheel belongs to the scrolling page.
    slider:EnableMouse(true)
    slider:EnableMouseWheel(false)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0); track:SetPoint("RIGHT", slider, "RIGHT", 0, 0); track:SetHeight(4)
    tint(track, "SetColorTexture", "lineSoft")
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", slider, "LEFT", 0, 0); fill:SetHeight(4)
    tint(fill, "SetColorTexture", "goldDim")
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    tint(thumb, "SetColorTexture", "gold")
    slider:SetThumbTexture(thumb)
    local valueText = newText(row.frame, "body", "goldText", VALUE_W, 16, false)
    valueText:SetJustifyH("RIGHT")
    valueText:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", 0, -10)
    row.control, row.fill, row.thumb, row.valueText = slider, fill, thumb, valueText

    local function bounds()
        local low = type(spec.min) == "function" and spec.min() or spec.min or 0
        local high = type(spec.max) == "function" and spec.max() or spec.max or 1
        if high < low then high = low end
        return low, high, spec.step or 1
    end
    local function paint(value)
        local low, high = bounds()
        local fraction = high > low and (value - low) / (high - low) or 0
        fill:SetWidth(math.max(1, fraction * (SLIDER_W - 10) + 5))
        valueText:SetText(string.format(spec.format or "%g", value))
    end
    -- While the thumb moves only the fill and the value text follow; the value is saved when it is released.
    slider:SetScript("OnValueChanged", function(_, raw)
        if self.refreshing or row.syncing then return end
        local low, high, step = bounds()
        local value = round(math.max(low, math.min(high, raw)), step, low)
        value = math.max(low, math.min(high, value))
        if value ~= raw then
            row.syncing = true; slider:SetValue(value); row.syncing = false
        end
        paint(value)
        row.pending = value
    end)
    row.finishDrag = function()
        local value = row.pending
        row.dragging, row.pending = false, nil
        if value ~= nil and value ~= self:Read(row) then self:Commit(row, value) end
    end
    slider:SetScript("OnMouseDown", function() row.dragging, row.pending = true, nil end)
    slider:SetScript("OnMouseUp", function() row.finishDrag() end)
    row.update = function()
        refreshLabels(self, row)
        -- A refresh from outside never resets the value that is being dragged.
        if row.dragging then return end
        local low, high, step = bounds()
        local value = tonumber(self:Read(row)) or low
        value = math.max(low, math.min(high, value))
        row.syncing = true
        slider:SetMinMaxValues(low, high); slider:SetValueStep(step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        slider:SetValue(value)
        row.syncing = false
        paint(value)
    end
    row.height = function() return plainHeight(row) end
    return row
end

-- Select (dropdown with a flat popup list) ----------------------------------------------------
local function optionList(row)
    local options = row.spec.options
    if type(options) == "function" then options = options() end
    return options or {}
end

function Form:ClosePopups()
    local popup = self.popup
    if popup then
        popup.state = nil
        popup:Hide()
        popup.blocker:Hide()
    end
    if active == self then active = nil end
end

local function renderPopup(self)
    local T = theme()
    local popup = self.popup
    local state = popup and popup.state
    if not state then return end
    local count = #state.options
    local visible = math.min(POPUP_MAX, count)
    local maximum = math.max(0, count - visible)
    state.offset = math.max(0, math.min(maximum, state.offset))
    popup:SetSize(state.width, math.max(1, visible) * POPUP_ROW + 8)
    local current = self:Read(state.row)
    for i = 1, POPUP_MAX do
        local button = popup.rows[i]
        local option = state.options[state.offset + i]
        if option and i <= visible then
            button.optionId = option[1]
            local label = option[2]
            if state.row.spec.translate ~= false then label = self.tr(label) end
            button:SetText(tostring(label))
            button:SetWidth(state.width - (maximum > 0 and 26 or 8))
            T.SetSelected(button, option[1] == current)
            button:Show()
        else
            button:Hide()
        end
    end
    if popup.bar then T.UpdateScrollBar(popup.bar, maximum, state.offset, math.max(1, visible) * POPUP_ROW + 8, math.max(1, count) * POPUP_ROW + 8) end
end

local function ensurePopup(self)
    if self.popup then return self.popup end
    local T = theme()
    local root = UIParent or self.parent
    -- A transparent catcher below the popup: a click anywhere else closes the list.
    local blocker = CreateFrame("Frame", nil, root)
    blocker:SetAllPoints(root); blocker:SetFrameStrata("TOOLTIP"); blocker:EnableMouse(true)
    blocker:SetScript("OnMouseDown", function() self:ClosePopups() end)
    blocker:Hide()
    local popup = CreateFrame("Frame", nil, blocker, BackdropTemplateMixin and "BackdropTemplate" or nil)
    popup:SetFrameStrata("TOOLTIP"); popup:SetFrameLevel(blocker:GetFrameLevel() + 5)
    popup:SetClampedToScreen(true); popup:EnableMouse(true); popup:EnableMouseWheel(true)
    T.StylePopup(popup)
    popup.blocker, popup.rows = blocker, {}
    for i = 1, POPUP_MAX do
        local button = T.Button(popup, "", SELECT_W - 8, POPUP_ROW, function(entry)
            local state = popup.state
            if not state then return end
            local row, id = state.row, entry.optionId
            self:ClosePopups()
            self:Commit(row, id)
        end, "ghost")
        button:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4 - (i - 1) * POPUP_ROW)
        T.AlignButtonText(button, 8)
        popup.rows[i] = button
    end
    popup.bar = T.CreateScrollBar(popup, function(value)
        if popup.state then popup.state.offset = math.floor(value + .5); renderPopup(self) end
    end)
    popup.bar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
    popup:SetScript("OnMouseWheel", function(_, delta)
        if popup.state then popup.state.offset = popup.state.offset - delta; renderPopup(self) end
    end)
    popup:Hide()
    self.popup = popup
    return popup
end

local function openPopup(self, row)
    local popup = ensurePopup(self)
    if popup.state and popup.state.row == row and popup:IsShown() then self:ClosePopups(); return end
    if active and active ~= self then active:ClosePopups() end
    active = self
    popup.state = { row = row, options = optionList(row), offset = 0, width = row.control:GetWidth() }
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", row.control, "BOTTOMLEFT", 0, -2)
    popup.blocker:Show(); popup:Show()
    renderPopup(self)
end

function Form:Select(spec)
    local T = theme()
    local row = addRow(self, "Select", spec)
    addLabels(self, row, 0, self.inner - SELECT_W - GAP)
    local button = T.Button(row.frame, "", SELECT_W, SELECT_H, function() openPopup(self, row) end, "secondary")
    T.StyleDropdown(button)
    T.AlignButtonText(button, 10, 28)
    button:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", 0, -4)
    row.control = button
    row.update = function()
        refreshLabels(self, row)
        local options, value = optionList(row), self:Read(row)
        local text = ""
        for _, option in ipairs(options) do
            if option[1] == value then
                text = spec.translate == false and tostring(option[2]) or self.tr(option[2])
                break
            end
        end
        button:SetText(text)
        local popup = self.popup
        if popup and popup.state and popup.state.row == row then
            popup.state.options = options
            renderPopup(self)
        end
    end
    row.height = function() return plainHeight(row) end
    return row
end

-- Segment (two to five options side by side) -------------------------------------------------
local function paintSegment(button, active, hover)
    local T = theme()
    tint(button.fill, "SetColorTexture", active and "panelRaised" or hover and "highlight" or "inset")
    T.TintEdges(button.edges, active and "highlight" or "fieldEdge")
    button.underline:SetShown(active)
    T.Font(button.text, "body", active and "goldBright" or hover and "text" or "textSoft")
end

function Form:Segment(spec)
    local T = theme()
    local row = addRow(self, "Segment", spec)
    local full = spec.full == true
    local total = full and self.inner or SEGMENT_W
    if not full then addLabels(self, row, 0, self.inner - SEGMENT_W - GAP) end
    local container = CreateFrame("Frame", nil, row.frame)
    container:SetSize(total, SEGMENT_H)
    if full then container:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, -4)
    else container:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", 0, -4) end
    row.control, row.buttons = container, {}
    local function build(count)
        for i = #row.buttons + 1, count do
            local button = CreateFrame("Button", nil, container)
            button.fill = button:CreateTexture(nil, "BACKGROUND")
            button.fill:SetPoint("TOPLEFT", 1, -1); button.fill:SetPoint("BOTTOMRIGHT", -1, 1)
            button.edges = T.Edges(button, "BORDER")
            button.underline = button:CreateTexture(nil, "OVERLAY")
            button.underline:SetPoint("BOTTOMLEFT", 1, 1); button.underline:SetPoint("BOTTOMRIGHT", -1, 1); button.underline:SetHeight(2)
            tint(button.underline, "SetColorTexture", "gold")
            button.text = newText(button, "body", "textSoft", nil, nil, false)
            button.text:SetPoint("LEFT", 6, 0); button.text:SetPoint("RIGHT", -6, 0); button.text:SetJustifyH("CENTER"); button.text:SetJustifyV("MIDDLE")
            button:SetScript("OnClick", function(entry)
                if not self.refreshing and entry.optionId ~= nil then self:Commit(row, entry.optionId) end
            end)
            button:SetScript("OnEnter", function(entry) entry.hover = true; paintSegment(entry, entry.selected, true) end)
            button:SetScript("OnLeave", function(entry) entry.hover = false; paintSegment(entry, entry.selected, false) end)
            row.buttons[i] = button
        end
    end
    row.update = function()
        refreshLabels(self, row)
        local options, value = optionList(row), self:Read(row)
        local count = math.min(5, #options)
        build(count)
        local each = total / math.max(1, count)
        for i, button in ipairs(row.buttons) do
            local option = options[i]
            if option and i <= count then
                button.optionId, button.selected = option[1], option[1] == value
                button:SetSize(each, SEGMENT_H)
                button:ClearAllPoints(); button:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * each, 0)
                button.text:SetText(spec.translate == false and tostring(option[2]) or self.tr(option[2]))
                paintSegment(button, button.selected, button.hover)
                button:Show()
            else
                button.optionId = nil
                button:Hide()
            end
        end
    end
    row.height = function() return (not full and row.hasDesc) and ROW_DESC or ROW end
    return row
end

-- Color --------------------------------------------------------------------------------------
local function chooseColor(self, row)
    local api = self.ctx.api
    local picker = (api and api.env and api.env.ColorPickerFrame) or ColorPickerFrame
    if not picker then return end
    local current = self:Read(row)
    local original = type(current) == "table" and { current[1] or 1, current[2] or 1, current[3] or 1 } or { 1, 1, 1 }
    -- The key of this session is fixed now: the row key can change while the picker is open.
    local key = keyOf(row.spec)
    if self.colorSession then self.colorSession.closed = true end
    local session = { picker = picker, closed = false }
    self.colorSession = session
    local function apply(r, g, b)
        if session.closed then return end
        if type(r) ~= "number" and type(picker.GetColorRGB) == "function" then
            local ok; ok, r, g, b = pcall(picker.GetColorRGB, picker)
            if not ok then return end
        end
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then self:Commit(row, { r, g, b }, key) end
    end
    local info = { r = original[1], g = original[2], b = original[3], hasOpacity = false,
        swatchFunc = function() apply() end,
        cancelFunc = function()
            if not session.closed then self:Commit(row, { original[1], original[2], original[3] }, key) end
        end }
    session.swatchFunc = info.swatchFunc
    if type(picker.SetupColorPickerAndShow) == "function" and pcall(picker.SetupColorPickerAndShow, picker, info) then return end
    -- Clients without SetupColorPickerAndShow: the older fields of the picker frame.
    picker.func, picker.swatchFunc, picker.cancelFunc = info.swatchFunc, info.swatchFunc, info.cancelFunc
    if picker.SetColorRGB then pcall(picker.SetColorRGB, picker, original[1], original[2], original[3]) end
    if picker.Hide then picker:Hide() end
    if picker.Show then picker:Show() end
end

function Form:Color(spec)
    local T = theme()
    local row = addRow(self, "Color", spec)
    addLabels(self, row, 0, self.inner - SWATCH_W - GAP)
    local swatch = CreateFrame("Button", nil, row.frame)
    swatch:SetSize(SWATCH_W, SWATCH_H)
    swatch:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", 0, -6)
    swatch.edges = T.Edges(swatch, "BORDER"); T.TintEdges(swatch.edges, "fieldEdge")
    swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
    swatch.fill:SetPoint("TOPLEFT", 1, -1); swatch.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    swatch:SetScript("OnEnter", function(button) T.TintEdges(button.edges, "goldDim") end)
    swatch:SetScript("OnLeave", function(button) T.TintEdges(button.edges, "fieldEdge") end)
    swatch:SetScript("OnClick", function() chooseColor(self, row) end)
    row.control = swatch
    row.update = function()
        refreshLabels(self, row)
        local value = self:Read(row)
        if type(value) == "table" then swatch.fill:SetColorTexture(value[1] or 1, value[2] or 1, value[3] or 1, 1)
        else tint(swatch.fill, "SetColorTexture", "muted") end
    end
    row.height = function() return plainHeight(row) end
    return row
end

-- Texts (multi-line list) and Input (single line) ---------------------------------------------
local function splitLines(text, maxLines, maxChars)
    local lines = {}
    for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            if maxChars then
                local count, cut = 0, #line
                for position in line:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
                    count = count + 1
                    if count > maxChars then cut = position - 1; break end
                end
                line = line:sub(1, cut):match("^(.-)%s*$")
            end
            lines[#lines + 1] = line
            if maxLines and #lines >= maxLines then break end
        end
    end
    return lines
end

local function newEdit(row, multiline, width, height)
    local T = theme()
    local edit = CreateFrame("EditBox", nil, row.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    edit:SetAutoFocus(false); edit:SetMultiLine(multiline == true); edit:SetFontObject("GameFontHighlightSmall")
    edit:SetSize(width, height)
    T.StyleEditBox(edit)
    edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    return edit
end

function Form:Texts(spec)
    local row = addRow(self, "Texts", spec)
    addLabels(self, row, 0, self.inner)
    local edit = newEdit(row, true, self.inner, TEXTS_MIN)
    if spec.maxChars and edit.SetMaxLetters then edit:SetMaxLetters(spec.maxChars * (spec.maxLines or 1) + (spec.maxLines or 1)) end
    row.control = edit
    local function offset() return row.hasDesc and 52 or 30 end
    local function fieldHeight()
        local height = edit.GetHeight and edit:GetHeight()
        return math.max(TEXTS_MIN, type(height) == "number" and height or 0)
    end
    row.layoutEdit = function() edit:ClearAllPoints(); edit:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, -offset()) end
    -- The client changes the field height while the user types: stack the page again, never touching the text.
    local function reflow()
        if self.refreshing then return end
        if row.fieldHeight ~= fieldHeight() and row.frame:IsShown() then self:Refresh() end
    end
    edit:HookScript("OnSizeChanged", reflow)
    edit:HookScript("OnTextChanged", function(_, userInput) if userInput then reflow() end end)
    -- The key is kept when the field gets focus: the row key can change while the user types.
    edit:SetScript("OnEditFocusGained", function() row.heldKey = keyOf(row.spec) end)
    edit:SetScript("OnEditFocusLost", function(box)
        if self.refreshing then return end
        local key = row.heldKey
        row.heldKey = nil
        local text = box:GetText()
        local app = self.ctx.app
        local spec = row.spec
        if not spec.get and not spec.set and app.TextsChanged then
            app:TextsChanged(key or keyOf(spec), text)
            if spec.onChange then spec.onChange(self:Read(row)) end
            if self.ctx.changed then self.ctx.changed() end
            return
        end
        self:Commit(row, splitLines(text, spec.maxLines, spec.maxChars), key)
    end)
    row.update = function()
        refreshLabels(self, row)
        row.layoutEdit()
        if edit:HasFocus() then return end
        local value = self:Read(row)
        edit:SetText(type(value) == "table" and table.concat(value, "\n") or tostring(value or ""))
    end
    row.height = function()
        row.fieldHeight = fieldHeight()
        return offset() + row.fieldHeight + TEXTS_PAD
    end
    return row
end

function Form:Input(spec)
    local row = addRow(self, "Input", spec)
    local width = spec.width or INPUT_W
    addLabels(self, row, 0, self.inner - width - GAP)
    local edit = newEdit(row, false, width, INPUT_H)
    edit:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", 0, -5)
    if spec.maxLetters and edit.SetMaxLetters then edit:SetMaxLetters(spec.maxLetters) end
    row.control = edit
    local function commit(box)
        if self.refreshing then return end
        local key = row.heldKey
        row.heldKey = nil
        local text = box:GetText()
        local value = text
        if spec.numeric then value = tonumber(text) end
        if value ~= self:Read(row, key) then self:Commit(row, value, key) end
    end
    -- The key is kept when the field gets focus (see Texts).
    edit:SetScript("OnEditFocusGained", function() row.heldKey = keyOf(spec) end)
    edit:SetScript("OnEnterPressed", function(box) commit(box); box:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", commit)
    row.update = function()
        refreshLabels(self, row)
        if edit:HasFocus() then return end
        local value = self:Read(row)
        edit:SetText(value == nil and "" or tostring(value))
    end
    row.height = function() return plainHeight(row) end
    return row
end

-- Buttons ------------------------------------------------------------------------------------
function Form:Buttons(list)
    local T = theme()
    local row = addRow(self, "Buttons", {})
    row.entries = {}
    for index, entry in ipairs(list or {}) do
        local variant = (entry.variant == "primary" or entry.variant == "danger") and entry.variant or "secondary"
        local button = T.Button(row.frame, "", BUTTON_MIN, BUTTON_H, function(widget)
            if entry.onClick then entry.onClick(widget) end
        end, variant)
        row.entries[index] = { spec = entry, button = button }
    end
    row.control = row.frame
    row.anyVisible = function()
        for _, item in ipairs(row.entries) do
            if not item.spec.visible or item.spec.visible() then return true end
        end
        return false
    end
    row.update = function()
        local x = 0
        for _, item in ipairs(row.entries) do
            local entry, button = item.spec, item.button
            if entry.visible and not entry.visible() then
                button:Hide()
            else
                local text = resolve(self, entry.text)
                self.measure:SetText(text)
                local width = math.max(BUTTON_MIN, math.ceil((self.measure:GetStringWidth() or 0) + 28))
                button:SetText(text); button:SetWidth(width)
                button:ClearAllPoints(); button:SetPoint("TOPLEFT", row.frame, "TOPLEFT", x, -4)
                button:SetEnabled(not entry.enabled or entry.enabled() == true)
                button:Show()
                x = x + width + BUTTON_GAP
            end
        end
    end
    row.height = function() return ROW end
    return row
end

-- Note ---------------------------------------------------------------------------------------
function Form:Note(spec)
    local row = addRow(self, "Note", spec)
    local tone = spec.tone == "warning" and "warning" or spec.tone == "success" and "success" or "dim"
    row.text = newText(row.frame, "body", tone, self.inner, nil, true)
    row.text:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, -6)
    row.content = function() return resolve(self, spec.text) end
    row.update = function()
        row.text:SetText(row.content())
    end
    row.height = function()
        local measured = row.text.GetStringHeight and row.text:GetStringHeight() or 14
        return math.max(24, math.ceil(measured) + 12)
    end
    return row
end

-- Custom -------------------------------------------------------------------------------------
function Form:Custom(spec)
    local row = addRow(self, "Custom", spec)
    row.control = row.frame
    if spec.build then spec.build(row.frame, self) end
    row.update = function()
        if spec.refresh then spec.refresh(row.frame) end
    end
    row.height = function()
        local value = type(spec.height) == "function" and spec.height() or spec.height
        return tonumber(value) or ROW
    end
    return row
end

-- ---------------------------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------------------------
local function rowVisible(self, row)
    local spec = row.spec
    if spec.advanced and not (self.ctx.advanced and self.ctx.advanced()) then return false end
    if spec.visible and not spec.visible() then return false end
    if row.kind == "Note" and resolve(self, spec.text) == "" then return false end
    -- A row of buttons without a visible button takes no space.
    if row.kind == "Buttons" and row.anyVisible and not row.anyVisible() then return false end
    return true
end

function Form:Refresh()
    local previous = self.refreshing
    self.refreshing = true
    local ok, err = pcall(function()
        local y, shown = 0, 0
        for _, card in ipairs(self.cards) do
            local visibleRows = {}
            for _, row in ipairs(card.rows) do
                if rowVisible(self, row) then
                    visibleRows[#visibleRows + 1] = row
                    row.update()
                else
                    row.frame:Hide()
                end
            end
            if #visibleRows == 0 then
                card.frame:Hide()
                card.height = 0
            else
                local cy = card.top
                for _, row in ipairs(visibleRows) do
                    local height = row.height()
                    row.frame:ClearAllPoints()
                    row.frame:SetPoint("TOPLEFT", card.frame, "TOPLEFT", CARD_PAD, -cy)
                    row.frame:SetSize(self.inner, height)
                    row.frame:Show()
                    row.y, row.rowHeight = cy, height
                    cy = cy + height
                end
                card.height = cy + CARD_PAD
                card.frame:ClearAllPoints()
                card.frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, -y)
                card.frame:SetSize(self.width, card.height)
                card.frame:Show()
                y = y + card.height + CARD_GAP
                shown = shown + 1
            end
        end
        self.height = shown > 0 and (y - CARD_GAP) or 0
        self.parent:SetSize(self.width, self.height)
    end)
    self.refreshing = previous
    if not ok then error(err, 0) end
    local popup = self.popup
    if popup and popup.state and not popup.state.row.frame:IsShown() then self:ClosePopups() end
end

function Form:Height() return self.height end

-- Takes the focus from every input field (the field saves under the key it kept), finishes a slider drag
-- and closes a colour picker opened by this form; the last chosen colour stays.
function Form:ReleaseInput()
    for _, card in ipairs(self.cards) do
        for _, row in ipairs(card.rows) do
            local control = row.control
            if (row.kind == "Texts" or row.kind == "Input") and control and control.HasFocus and control:HasFocus() then
                control:ClearFocus()
            elseif row.kind == "Slider" and row.dragging and row.finishDrag then
                row.finishDrag()
            end
        end
    end
    local session = self.colorSession
    self.colorSession = nil
    if session and not session.closed then
        session.closed = true
        local picker = session.picker
        local shown = type(picker.IsShown) ~= "function" or picker:IsShown()
        if shown and (picker.swatchFunc == nil or picker.swatchFunc == session.swatchFunc) and type(picker.Hide) == "function" then
            pcall(picker.Hide, picker)
        end
    end
end

-- Every configuration key of the page: the static keys of all rows (visible or not) plus the keys the rows
-- report for function keys and get/set rows.
function Form:Keys()
    local keys, seen = {}, {}
    local function add(key)
        if type(key) == "string" and not seen[key] then seen[key] = true; keys[#keys + 1] = key end
    end
    for _, card in ipairs(self.cards) do
        for _, row in ipairs(card.rows) do
            local spec = row.spec
            if type(spec.key) == "string" then add(spec.key) end
            for _, key in ipairs(spec.keys or {}) do add(key) end
        end
    end
    return keys
end
