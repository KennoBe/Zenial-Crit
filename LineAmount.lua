-- ZENIAL Crit: shows the damage amount of a protected combat log line (M3 of LOG-AMOUNTS-PLAN.md).
--
-- The line is an opaque secret string (a "|K" wrapper). It may only be handed to FontString:SetText.
-- It is never read, compared, measured or concatenated here outside a pcall. The amount is made
-- visible by fonts (Media/ZenialCrit*.ttf, metrics in the plan, M1) in which only the figures have a
-- glyph, and by a clip frame that cuts away everything that is not the amount.
--
-- Usage:
--   local R = NS.LineAmount.New(_G)              -- env needs CreateFrame, UIParent, GetLocale and the
--   R:Warm()                                     -- GlobalStrings; fontDir defaults to the addon's Media
--   local slot = R:NewSlot(parent)
--   slot:Place(region, "RIGHT", 6, -2)           -- the amount's left edge / foot line: BOTTOMLEFT of the
--                                                -- amount ink sits at that point of region (x, y offset)
--   if slot:SetLine(line, px, single) then ... end  -- false: show no amount for this hit
--   slot:Clear()
-- slot.frame is the clip frame; slot.text the visible FontString (its BOTTOMRIGHT is the trail
-- anchor), slot.blank the invisible measuring string. All are children placed by Place; the caller
-- only anchors things to the slot, never the slot's inner parts to something else.
--
-- Several amounts in a row ("291 + 317") are laid out without measuring any secret text, by chaining
-- anchors (as the reference does): slot:Trail() returns frame, point, dx for a first slot. Anchor the
-- "+" with plus:SetPoint("BOTTOMLEFT", frame, point, dx + gap, y). Then anchor the next slot to the
-- plus: next:Place(plus, "BOTTOMRIGHT", gap, y). A card background that has to follow the content
-- anchors its right edge to the last slot's Trail() the same way. A slot in push mode (see below) has
-- no trail: its end is unknown, it is only for a hit that stands alone (SetLine's third argument).
--
-- Push mode: a line with a second number in parentheses (Blocked, Overkill, Absorbed) is set in the
-- push font, whose "(" pushes everything behind it far away; the clip field then has a fixed width
-- (slot:Width() = ceil(9 * px)) instead of ending at the text.
--
-- Colour: the visible string is black, so that no figure the game did not colour stands out. The
-- amount itself is coloured by the game's own escape sequences in the line (amountHighlighting).
-- Everything touching a widget is protected by pcall; any failure hides the slot and SetLine returns
-- false.
local _, NS = ...
local LA = {}
NS.LineAmount = LA

local DEFAULT_DIR = "Interface\\AddOns\\ZenialCrit\\Media\\"
local FILES = {
    amount = "ZenialCritAmount.ttf", blank = "ZenialCritBlank.ttf", count = "ZenialCritCount.ttf",
    push = "ZenialCritPush.ttf", paren = "ZenialCritCountParen.ttf",
}
-- Metric contract with the fonts (M1), in em of the font size.
LA.AMOUNT_SHIFT, LA.PUSH_SHIFT, LA.PUSH_ADVANCE, LA.COUNT_BLOCK, LA.PUSH_FIELD = 0.6, 1.5, 16, 8, 9
local LINE_PAD, LINE_END = 2, 3          -- clip margin for the outline; a last figure ends this far inside its advance
local COUNT_PX, COUNT_FIELD, COUNT_NARROW, FRAME_MARKERS = 8, 100, 44, 5
local PAREN_MAX = 12                     -- pixels a number in parentheses may still take at COUNT_PX
local PUSH_TAIL = 16                     -- most spaces behind an amount in a real line
local MARKER = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8.blp:0|t"
local LOAD_TEXT = "ZENIAL Crit"
local RETRY = 5                          -- seconds before a failed self-test is asked again

function LA.Reach(px) return math.ceil(LA.AMOUNT_SHIFT * px) end
function LA.PushReach(px) return math.ceil(LA.PUSH_SHIFT * px) end
function LA.PushField(px) return math.ceil(LA.PUSH_FIELD * px) end
-- Spaces appended to the visible text so that the shifted last figure stays inside its own bounds.
function LA.Pad(px, push) return (push and LA.PushReach(px) or LA.Reach(px)) + LINE_PAD + LINE_END end

local function samePath(a, b)
    return type(a) == "string" and type(b) == "string" and (a:lower():gsub("/", "\\")) == (b:lower():gsub("/", "\\"))
end

local function wholePx(px)
    if type(px) ~= "number" or px ~= px or px < 1 or px > 200 then return nil end
    return math.floor(px + 0.5)
end

-- ---------------------------------------------------------------------------------------------
-- Synthetic public lines, built like Blizzard_CombatLogProcessor:GenerateMessage builds one.
-- ---------------------------------------------------------------------------------------------
local LINE_FORMAT = "%s %s %s %s %s. %s %11$s"     -- TEXT_MODE_A_STRING_1
local UNIT_FORMAT = "%s|Hunit:%s:%s|h%s|h"         -- TEXT_MODE_A_STRING_SOURCE_UNIT / DEST_UNIT
local ACTION_FORMAT = "|Haction:%s|h%s|h"

local ENGLISH = {
    your = "Your", melee = "Melee", hit = "hit", school = "Physical", crit = "(Critical)",
    blocked = "(%s Blocked)", absorbed = "(%s Absorbed)", overkill = "(%s Overkill)", separator = ",",
    first = "Hollow", last = "Mob", letters = "",
}
local LANGUAGES = {
    deDE = { first = "Große", last = "Ödnis", letters = "ÄÖÜäöüß" },
    esES = { first = "Dragón", last = "Añejo", letters = "ÁÉÍÓÚÜÑáéíóúüñ" },
    esMX = { first = "Dragón", last = "Añejo", letters = "ÁÉÍÓÚÜÑáéíóúüñ" },
}
local WORD_NAMES = {
    your = "UNIT_YOU_SOURCE_POSSESSIVE", melee = "ACTION_SWING", hit = "ACTION_SWING_DAMAGE",
    school = "STRING_SCHOOL_PHYSICAL", crit = "TEXT_MODE_A_STRING_RESULT_CRITICAL",
}
local RESULT_NAMES = {
    blocked = "TEXT_MODE_A_STRING_RESULT_BLOCK", absorbed = "TEXT_MODE_A_STRING_RESULT_ABSORB",
    overkill = "TEXT_MODE_A_STRING_RESULT_OVERKILLING",
}
local SEPARATORS = { ["."] = true, [","] = true, [""] = true }

local function MadeLine(words, name, amount, result, unmarked)
    local function icon(flag, index, kind)
        if unmarked then return "" end
        return ("|Hicon:%d:%s|h|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d.blp:0|t|h"):format(flag, kind, index)
    end
    local source = UNIT_FORMAT:format(icon(4, 3, "source"), "Player-1-00000001", "Sample", words.your)
    local spell = ACTION_FORMAT:format("SWING_DAMAGE", "|cffffffff" .. words.melee .. "|r")
    local action = ACTION_FORMAT:format("SWING_DAMAGE", words.hit)
    local dest = UNIT_FORMAT:format(icon(128, 8, "dest"), "Creature-0-1-2-3-4-0000000001", name, name)
    local value = "|cffffffff" .. amount .. "|r |cffffffff" .. words.school .. "|r"
    -- TEXT_MODE_A_STRING_1 with an empty eleventh argument (a positional %n$s is not available here).
    local text = source .. " " .. spell .. " " .. action .. " " .. dest .. " " .. value .. ". " .. (result or "") .. " "
    text = text:gsub(" [ ]+", " "):gsub(" ([.,])", "%1"):gsub("^([ .,]+)", "")
    -- The line the client hands over carries no trailing space.
    return (text:gsub("[ 	]+$", ""))
end
LA.MadeLine = function(words, ...) return MadeLine(words or ENGLISH, ...) end
LA.ENGLISH = ENGLISH

-- ---------------------------------------------------------------------------------------------
local Renderer, Slot = {}, {}
Renderer.__index, Slot.__index = Renderer, Slot

function LA.New(env, fontDir)
    local dir = type(fontDir) == "string" and fontDir or DEFAULT_DIR
    local R = setmetatable({ env = env, dir = dir, f = {}, counters = {}, rulers = {}, warm = {},
        good = {}, goodPush = {}, failed = {}, status = "untested", detail = "" }, Renderer)
    for key, file in pairs(FILES) do R.f[key] = dir .. file end
    return R
end

function Renderer:Plain(v)
    local check = self.env.issecretvalue
    if type(check) ~= "function" then return true end
    local ok, secret = pcall(check, v)
    return ok and not secret
end

function Renderer:Number(v) return type(v) == "number" and self:Plain(v) and v == v and v or nil end

-- Loads every font once into a hidden FontString (the client reads a font only when a text uses it).
function Renderer:Warm()
    local env = self.env
    for _, key in ipairs({ "amount", "blank", "count", "push", "paren" }) do
        local path = self.f[key]
        if not self.warm[path] then
            local ok, fs = pcall(function()
                local fs = env.UIParent:CreateFontString(nil, "BACKGROUND")
                fs:SetAlpha(0)
                fs:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 0, 0)
                fs:SetFont(path, 24, "")
                fs:SetText(LOAD_TEXT)
                return fs
            end)
            if ok then self.warm[path] = fs end
        end
    end
end

-- How wide one pixel of the screen is in UIParent units (1 where the UI fits the screen exactly).
function Renderer:ScreenPixel()
    local env = self.env
    local okS, effective = pcall(function() return env.UIParent:GetEffectiveScale() end)
    local okP, _, high = pcall(function() return env.GetPhysicalScreenSize() end)
    effective, high = self:Number(effective), self:Number(high)
    if not (okS and okP and effective and high) or effective <= 0 or high <= 0 then return 1 end
    local pixel = 768 / high / effective
    if pixel < 0.2 or pixel > 4 then return 1 end
    return pixel
end

-- A hidden frame scaled so that one of its units is one screen pixel: the count fonts are laid out
-- as on a client that fits the screen exactly.
function Renderer:Holder()
    if not self.holder then
        self.holder = self.env.CreateFrame("Frame", nil, self.env.UIParent)
        self.holder:Hide()
    end
    local pixel = self:ScreenPixel()
    if self.holder.zenialPixel ~= pixel then
        self.holder:SetScale(pixel)
        self.holder.zenialPixel = pixel
    end
    return self.holder
end

local function isCount(self, path) return path == self.f.count or path == self.f.paren end

-- A hidden FontString set to a font at a size for widths; nil while the font does not stand.
function Renderer:Ruler(path, px)
    local ok, fs = pcall(function()
        local fs = self.rulers[path]
        if not fs then
            fs = (isCount(self, path) and self:Holder() or self.env.UIParent):CreateFontString(nil, "BACKGROUND")
            fs:SetWordWrap(false)
            self.rulers[path] = fs
        end
        local got, size = fs:GetFont()
        if not got or size ~= px then
            pcall(fs.SetFont, fs, path, px, "")
            got = fs:GetFont()
            if not got then
                pcall(fs.SetText, fs, LOAD_TEXT)
                pcall(fs.GetStringWidth, fs)
                got = fs:GetFont()
            end
        end
        return samePath(got, path) and fs or nil
    end)
    return ok and fs or nil
end

-- Lines a text takes in the count font's field, framed by raid markers (3 = the text has exactly one
-- word with a figure) or alone in the narrow field. nil where the client does not tell. The text may
-- be secret: it is only concatenated inside the pcall and handed to SetText.
function Renderer:Count(text, framed, path)
    path = path or self.f.count
    local ok, lines = pcall(function()
        local holder = self:Holder()
        local fs = self.counters[path]
        if not fs then
            fs = holder:CreateFontString(nil, "BACKGROUND")
            self.counters[path] = fs
        end
        local got, size = fs:GetFont()
        if not got or size ~= COUNT_PX then
            pcall(fs.SetFont, fs, path, COUNT_PX, "")
            got = fs:GetFont()
            if not got then pcall(fs.SetText, fs, LOAD_TEXT) return nil end
        end
        if not samePath(got, path) then return nil end
        fs:SetWidth(framed and COUNT_FIELD or COUNT_NARROW)
        fs:SetWordWrap(true)
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
        if fs.SetMaxLines then fs:SetMaxLines(0) end
        local shown = text
        if framed then
            local mark = MARKER:rep(FRAME_MARKERS)
            shown = mark .. " " .. text .. " " .. mark
        end
        fs:SetText(shown)
        local count = fs:GetNumLines()
        pcall(fs.SetText, fs, "")
        return count
    end)
    if ok then return self:Number(lines) end
    return nil
end
function Renderer:Lines(text, path) return self:Count(text, true, path) end

local function Width(self, fs, text)
    local ok, width = pcall(function() fs:SetText(text); return fs:GetStringWidth() end)
    if ok then return self:Number(width) end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- Language: the words of the check lines.
-- ---------------------------------------------------------------------------------------------
function Renderer:Said(name)
    local text = self.env[name]
    if type(text) == "string" and self:Plain(text) then return text end
    return nil
end

-- The client's own wording for the supported locales; nil when not supported or not exactly as expected.
function Renderer:Words()
    local locale = self.env.GetLocale and self.env.GetLocale()
    local english = locale == "enUS" or locale == "enGB"
    local language = LANGUAGES[locale]
    if not (english or language) then return nil end
    if self:Said("TEXT_MODE_A_STRING_1") ~= LINE_FORMAT or self:Said("TEXT_MODE_A_STRING_VALUE_SCHOOL") ~= "%s %s"
        or self:Said("TEXT_MODE_A_STRING_SOURCE_UNIT") ~= UNIT_FORMAT
        or self:Said("TEXT_MODE_A_STRING_DEST_UNIT") ~= UNIT_FORMAT then
        return nil
    end
    if english then return ENGLISH, true end
    local separator = self:Said("LARGE_NUMBER_SEPERATOR")
    if not (separator and SEPARATORS[separator]) then return nil end
    local words = { separator = separator, first = language.first, last = language.last, letters = language.letters }
    for key, name in pairs(WORD_NAMES) do
        local text = self:Said(name)
        if not text or text == "" or text:find("[0-9|%%]") then return nil end
        words[key] = text
    end
    for key, name in pairs(RESULT_NAMES) do
        local text = self:Said(name)
        if not text then return nil end
        local rest, places = text:gsub("%%[sd]", "")
        if places ~= 1 or rest:find("[0-9|%%]") then return nil end
        words[key] = text
    end
    return words
end

-- ---------------------------------------------------------------------------------------------
-- Self-test: lines made up here (public), widths and line counts asked of the client.
-- ---------------------------------------------------------------------------------------------
local function more(n) return n ~= nil and n > 3 end
local function fmt(v) return type(v) == "number" and ("%.1f"):format(v) or "?" end

-- ok, "kerning"|"spacing"|nil, detail
function Renderer:Check(words, px, amount, blank)
    local count = self.f.count
    local target = words.first .. " " .. words.last
    local function Made(name, figures, result, unmarked) return MadeLine(words, name, figures, result, unmarked) end
    local function Result(kind, figures) return (words[kind]:gsub("%%[sd]", figures, 1)) end
    local thousand = "1" .. words.separator .. "234"
    local clean = self:Lines(Made(target, "412", words.crit))
    local bare = self:Lines(Made(target, "412", words.crit, true))
    local blocked = self:Lines(Made(target, "412", Result("blocked", "12")))
    local named = self:Lines(Made(target .. " 9-60", "412"))
    local both = self:Lines(Made(words.first .. " 60 " .. words.last, "412",
        Result("blocked", "12") .. " " .. Result("overkill", "140")))
    local thousands = self:Lines(Made(target, thousand))
    local bareBlocked = self:Lines(Made(target, "412", Result("blocked", "1"), true))
    local bareNamed = self:Lines(Made(words.last .. " 7", "412", nil, true))
    local one = self:Lines(Made(target, "9", Result("overkill", "1")))
    local long = self:Lines(Made(words.first .. " " .. words.first .. " " .. words.last .. " " .. words.last
        .. " " .. words.last, "412", words.crit, true))
    local alone = self:Count(Made(target, "412", words.crit, true), false)
    local single = self:Ruler(count, COUNT_PX)
    local narrowest = single and Width(self, single, "1 x")
    local joined = single and Width(self, single, "412 x")
    local grouped = single and Width(self, single, thousand .. " x")
    local unseen = (single and words.letters ~= "") and Width(self, single, words.letters) or 0
    if single then pcall(single.SetText, single, "") end
    local kerning = narrowest ~= nil and joined ~= nil and grouped ~= nil
        and COUNT_FIELD > 8 * COUNT_PX and narrowest > COUNT_NARROW + 2 and joined < COUNT_FIELD
        and math.abs(joined - narrowest) < 4 and math.abs(grouped - joined) < 4
        and clean == 3 and bare == 3 and long == 3 and thousands == 3 and (alone == 2 or alone == 3)
        and more(blocked) and more(named) and more(both) and more(bareBlocked) and more(bareNamed) and more(one)
    if kerning then
        kerning = more(self:Lines(Made(target, thousand, Result("blocked", "12"))))
    end
    local head = MadeLine(words, target, "0", nil, false):match("^(.-) |cffffffff0|r") or ""
    local _, targetSpaces = target:gsub(" ", "")
    local headSpaces = targetSpaces + 3
    local marker = Width(self, blank, MARKER)
    local letters = Width(self, blank, words.your .. words.melee .. ".()" .. words.letters)
    local inked = words.letters ~= "" and Width(self, amount, words.letters) or 0
    local spaces = Width(self, blank, "a b c d e f g")
    local limit = 6.6 * math.max(1, self:ScreenPixel())
    local headBlank, headAmount = Width(self, blank, head), Width(self, amount, head)
    local begins = Width(self, amount, head .. " x")
    local ends = Width(self, blank, Made(target, "412", words.crit))
    local figures = Width(self, amount, "412 x")
    local whole = Width(self, amount, head .. " |cffffffff412|r x")
    local spacing = marker and letters and inked and spaces and headBlank and headAmount and begins and ends
        and figures and whole and unseen
        and marker > 2 and figures > 2 and letters < 0.5 and inked < 0.5 and unseen < 0.5 and spaces < limit
        and math.abs(headBlank - (2 * marker + headSpaces * spaces / 6)) < 1.5
        and math.abs(headAmount - headBlank) < 0.5
        and math.abs((whole - begins) - figures) < 1.5
        -- 2.5: the outline makes a text two wider
        and ends - begins > -0.5 and ends - begins < LA.AMOUNT_SHIFT * px - 2.5
    pcall(amount.SetText, amount, "")
    pcall(blank.SetText, blank, "")
    local detail = ("px=%d lines=%s/%s/%s/%s/%s/%s/%s/%s/%s alone=%s kern=%s/%s/%s space=%s/%s/%s"):format(px,
        tostring(clean), tostring(bare), tostring(blocked), tostring(named), tostring(both), tostring(thousands),
        tostring(bareBlocked), tostring(bareNamed), tostring(one), tostring(alone),
        fmt(narrowest), fmt(joined), fmt(grouped), fmt(spaces), fmt(ends and begins and ends - begins),
        fmt(marker))
    if not kerning then return false, "kerning", detail end
    if not spacing then return false, "spacing", detail end
    return true, nil, detail
end

-- The push mode's extra questions, on top of a passed Check. ok, detail
function Renderer:PushCheck(words, px, push, blank)
    local target = words.first .. " " .. words.last
    local function Made(name, figures, result, unmarked) return MadeLine(words, name, figures, result, unmarked) end
    local function Result(kind, figures) return (words[kind]:gsub("%%[sd]", figures, 1)) end
    local block, absorb, overkill = Result("blocked", "12"), Result("absorbed", "7"), Result("overkill", "140")
    local all = block .. " " .. absorb .. " " .. overkill .. " " .. words.crit
    local function behind(result)
        local _, n = (" " .. words.school .. ". " .. result):gsub(" ", "")
        return n
    end
    local tail = all
    while behind(tail) < PUSH_TAIL do tail = tail .. " (7 x)" end
    local sep = words.separator
    local thousand = "1" .. sep .. "234"
    local counted = true
    local function Takes(three, ...)
        local n = self:Lines(MadeLine(words, ...), self.f.paren)
        if three then counted = counted and n == 3 else counted = counted and more(n) end
    end
    Takes(true, target, "412")
    Takes(true, target, "412", words.crit)
    Takes(true, target, "412", block)
    Takes(true, target, "412", absorb .. " " .. words.crit)
    Takes(true, target, "128", overkill)
    Takes(true, target, "9", all)
    Takes(true, target, "9", tail)
    Takes(true, target, thousand, Result("overkill", "1" .. sep .. "050"))
    Takes(true, target, "412", block, true)
    Takes(false, target .. " 9-60", "412", overkill)
    Takes(false, words.last .. " 7", "412", block, true)
    Takes(false, target, "412", "7")
    Takes(false, words.first .. " 60 " .. words.last, "412", block)
    local alone = self:Count(MadeLine(words, target, "412", block, true), false, self.f.paren)
    counted = counted and (alone == 2 or alone == 3)
    local single = self:Ruler(self.f.paren, COUNT_PX)
    local figure = single and Width(self, single, "1 x")
    local collapsed = single and Width(self, single, "(150 x")
    local grouped = single and Width(self, single, "(1" .. sep .. "050 x")
    if single then pcall(single.SetText, single, "") end
    local pushed, unpushed = Width(self, push, "(9 x"), Width(self, blank, "(9")
    local head = MadeLine(words, target, "0"):match("^(.-) |cffffffff0|r") or ""
    local begins = Width(self, push, head .. " x")
    local headPush, headBlank = Width(self, push, head), Width(self, blank, head)
    local plain = Width(self, blank, MadeLine(words, target, "412"))
    local widest = Width(self, blank, MadeLine(words, target, "9", tail))
    local eight = Width(self, push, "00000000 x")
    local probe = MadeLine(words, target, "412", "(")
    local square, squareStarts = Width(self, push, probe), Width(self, blank, probe)
    local field, shift, dot = LA.PushField(px), LA.PUSH_SHIFT * px, 0.1 * px
    local ok = counted and figure and collapsed and grouped and pushed and unpushed and begins and headPush
        and headBlank and plain and widest and eight and square and squareStarts
        and figure > COUNT_NARROW + 2 and collapsed < PAREN_MAX and grouped < PAREN_MAX
        and pushed >= (LA.PUSH_ADVANCE - 0.5) * px and unpushed < 0.5
        and math.abs(headPush - headBlank) < 0.5
        and plain - begins > -0.5 and widest - begins > -0.5 and widest - begins < shift - 2.5
        and (eight - 1) + shift + 1 < field
        and square - dot - squareStarts >= field
    pcall(push.SetText, push, "")
    pcall(blank.SetText, blank, "")
    return ok and true or false, ("px=%d paren=%s/%s pushed=%s/%s field=%d"):format(px, fmt(collapsed), fmt(grouped),
        fmt(pushed), fmt(unpushed), field)
end

local function now(self)
    local get = self.env.GetTime
    return type(get) == "function" and get() or 0
end

-- ok(boolean), reason (nil | "size" | "locale" | "fonts" | "kerning" | "spacing"), detail. A yes is
-- kept per locale and size for the session, a no for RETRY seconds.
function Renderer:SelfTest(px)
    px = wholePx(px)
    if not px then return false, "size", "" end
    local locale = self.env.GetLocale and self.env.GetLocale() or "?"
    local key = tostring(locale) .. ":" .. px
    if self.good[key] then
        self.status = "ok"
        return true, nil, self.good[key]
    end
    local failed = self.failed[key]
    if failed and now(self) - failed.at < RETRY then
        self.status, self.detail = failed.reason, failed.detail
        return false, failed.reason, failed.detail
    end
    local function fail(reason, detail)
        self.failed[key] = { at = now(self), reason = reason, detail = detail or "" }
        self.status, self.detail = reason, detail or ""
        return false, reason, detail or ""
    end
    local words, english = self:Words()
    if not words then return fail("locale", "words") end
    local amount, blank = self:Ruler(self.f.amount, px), self:Ruler(self.f.blank, px)
    -- Asked first: gives the count font a text, which makes the client load it.
    self:Lines(MadeLine(ENGLISH, "Hollow Mob", "412", "(Critical)"))
    if not (amount and blank and self.counters[self.f.count] and self.counters[self.f.count]:GetFont()) then
        return fail("fonts", "amount=" .. (amount and "yes" or "no") .. " blank=" .. (blank and "yes" or "no"))
    end
    local ok, reason, detail = self:Check(words, px, amount, blank)
    if not ok then return fail(english and reason or "locale", detail) end
    self.good[key] = detail
    self.status, self.detail = "ok", detail
    return true, nil, detail
end

-- Whether the push mode can be had at px (a passed SelfTest and the push questions). ok, reason
function Renderer:PushTest(px)
    px = wholePx(px)
    if not (px and self:SelfTest(px)) then return false, "size" end
    local locale = self.env.GetLocale and self.env.GetLocale() or "?"
    local key = tostring(locale) .. ":" .. px
    if self.goodPush[key] then return true end
    local failed = self.failed["push:" .. key]
    if failed and now(self) - failed.at < RETRY then return false, "push" end
    local words = self:Words()
    local push, blank = self:Ruler(self.f.push, px), self:Ruler(self.f.blank, px)
    self:Lines(MadeLine(ENGLISH, "Hollow Mob", "412", "(12 Blocked)"), self.f.paren)
    local paren = self:Ruler(self.f.paren, COUNT_PX)
    if not (words and push and blank and paren and self.counters[self.f.paren]
        and self.counters[self.f.paren]:GetFont()) then
        self.failed["push:" .. key] = { at = now(self) }
        return false, "fonts"
    end
    local ok, detail = self:PushCheck(words, px, push, blank)
    if not ok then
        self.failed["push:" .. key] = { at = now(self) }
        self.detail = detail
        return false, "push"
    end
    self.goodPush[key] = detail
    return true
end

-- "ok", "untested" or the reason of the last failed self-test, for the settings status line.
function Renderer:Status() return self.status end

-- ---------------------------------------------------------------------------------------------
-- Calibration: where the figures of a line really stand, measured on a public line of the same
-- format at the size and scale of the slot's parent. The client's em is not the font size (Noto's
-- line box is taller than its em), and the padding spaces and the words behind the amount widen
-- the text box: the slot hangs the amount by these measurements, not by assumed constants.
-- ---------------------------------------------------------------------------------------------
local DIGIT_ADVANCE = 0.572   -- em; the fonts' figures are tabular (M1)

function Renderer:ProbeStrings(ratio)
    local env = self.env
    if not self.probe then
        local frame = env.CreateFrame("Frame", nil, env.UIParent)
        frame:Hide()
        local amount, blank = frame:CreateFontString(nil, "BACKGROUND"), frame:CreateFontString(nil, "BACKGROUND")
        amount:SetWordWrap(false)
        blank:SetWordWrap(false)
        self.probe = { frame = frame, amount = amount, blank = blank }
    end
    if self.probe.ratio ~= ratio then
        self.probe.frame:SetScale(ratio)
        self.probe.ratio = ratio
    end
    return self.probe
end

-- {shift, start, tail} in the parent's units, or nil (the slot then keeps the font-size constants).
-- shift: how far the figures are drawn right of their advance; start: how far the blank text ends
-- behind the amount's first advance; tail: how far the visible text box ends behind its last one.
function Renderer:Calibrate(parent, px, push)
    local env = self.env
    local okR, ratio = pcall(function() return parent:GetEffectiveScale() / env.UIParent:GetEffectiveScale() end)
    ratio = okR and self:Number(ratio) or nil
    if not ratio or ratio <= 0 then ratio = 1 end
    local key = ("%d:%s:%.3f"):format(px, push and "p" or "a", ratio)
    self.calibration = self.calibration or {}
    local known = self.calibration[key]
    if known ~= nil then return known or nil end
    local words = self:Words()
    local result = false
    local ok = pcall(function()
        if not words then return end
        local probe = self:ProbeStrings(ratio)
        local amount, blank = probe.amount, probe.blank
        amount:SetFont(push and self.f.push or self.f.amount, px, "OUTLINE")
        blank:SetFont(self.f.blank, px, "OUTLINE")
        local one, eleven = Width(self, amount, "0"), Width(self, amount, ("0"):rep(11))
        local line = MadeLine(words, words.first .. " " .. words.last, "412", nil, true)
        local head = line:match("^(.-) |cffffffff412|r")
        local begins = head and Width(self, amount, head .. " x")
        local ends = Width(self, blank, line)
        local whole = Width(self, amount, line .. string.rep(" ", LA.Pad(px, push)))
        pcall(amount.SetText, amount, "")
        pcall(blank.SetText, blank, "")
        if not (one and eleven and begins and ends and whole) then return end
        local digit = (eleven - one) / 10
        local em = digit / DIGIT_ADVANCE
        if em < .4 * px or em > 1.6 * px then return end
        local shift = (push and LA.PUSH_SHIFT or LA.AMOUNT_SHIFT) * em
        local start, tail = ends - begins, whole - begins - 3 * digit
        if start < -2 or start > shift or tail < 0 then return end
        result = { shift = shift, start = start, tail = tail, em = em }
    end)
    if not ok then result = false end
    self.calibration[key] = result
    return result or nil
end

-- ---------------------------------------------------------------------------------------------
-- Slot
-- ---------------------------------------------------------------------------------------------
function Renderer:NewSlot(parent)
    local env = self.env
    local slot = setmetatable({ R = self, active = false }, Slot)
    local ok = pcall(function()
        local frame = env.CreateFrame("Frame", nil, parent)
        frame:SetClipsChildren(true)
        frame:Hide()
        local text = frame:CreateFontString(nil, "OVERLAY")
        -- Black for what the game did not colour; the amount carries the game's colour escape.
        text:SetTextColor(0, 0, 0, 1)
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        text:SetWordWrap(false)
        text:Hide()
        local blank = parent:CreateFontString(nil, "BACKGROUND")
        blank:SetAlpha(0)
        blank:SetWordWrap(false)
        blank:Hide()
        slot.frame, slot.text, slot.blank = frame, text, blank
    end)
    slot.broken = not ok
    return slot
end

local function show(self, shown)
    pcall(function()
        self.frame:SetShown(shown)
        self.text:SetShown(shown)
        self.blank:SetShown(shown)
    end)
end

function Slot:Clear()
    self.active, self.push, self.reach, self.span = false, false, nil, nil
    if self.broken then return end
    pcall(function() self.text:SetText("") end)
    pcall(function() self.blank:SetText("") end)
    show(self, false)
end

-- Anchors the amount: its near edge at `point` of `region`, x/y offsets as for SetPoint.
function Slot:Place(region, point, x, y)
    self.anchor = { region, point, x or 0, y or 0 }
    if self.active then self:Layout() end
end

function Slot:Layout()
    local a = self.anchor
    if not a or self.broken then return false end
    local reach = self.reach or 0
    local fit = self.fit
    local ok = pcall(function()
        local frame, text, blank = self.frame, self.text, self.blank
        blank:ClearAllPoints()
        text:ClearAllPoints()
        frame:ClearAllPoints()
        -- Measured: the first figure's ink stands exactly at the anchor.
        local x = fit and a[3] + fit.start - fit.shift or a[3] - reach + 2
        blank:SetPoint("BOTTOMRIGHT", a[1], a[2], x, a[4])
        text:SetPoint("BOTTOMLEFT", blank, "BOTTOMLEFT", 0, 0)
        frame:SetPoint("TOPLEFT", blank, "TOPRIGHT", 0, LINE_PAD)
        if self.push then
            frame:SetPoint("BOTTOMRIGHT", blank, "BOTTOMRIGHT", self.span, -LINE_PAD)
        elseif fit then
            frame:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", fit.shift - fit.tail + LINE_PAD, -LINE_PAD)
        else
            frame:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", reach + LINE_PAD, -LINE_PAD)
        end
    end)
    return ok
end

-- Sets a line. px: the font size on the screen; single: the hit's only amount (allows push mode for
-- a line with a second number in parentheses). true when an amount is shown, false (slot hidden) else.
function Slot:SetLine(line, px, single)
    if self.broken then return false end
    local done, result = pcall(self.Apply, self, line, px, single)
    if done and result then return true end
    self:Clear()
    return false
end

function Slot:Apply(line, px, single)
    local R = self.R
    px = wholePx(px)
    if not px or not line then return false end
    if not R:SelfTest(px) then return false end
    local mode
    local framed = R:Lines(line, R.f.count)
    if framed == 3 then
        local alone = R:Count(line, false, R.f.count)
        if alone == 2 or alone == 3 then mode = "amount" end
    elseif framed and framed > 3 and single and R:PushTest(px) then
        if R:Lines(line, R.f.paren) == 3 then
            local alone = R:Count(line, false, R.f.paren)
            if alone == 2 or alone == 3 then mode = "push" end
        end
    end
    if not mode then return false end
    local push = mode == "push"
    local path = push and R.f.push or R.f.amount
    local reach = push and LA.PushReach(px) or LA.Reach(px)
    self.text:SetFont(path, px, "OUTLINE")
    self.blank:SetFont(R.f.blank, px, "OUTLINE")
    if not (samePath((self.text:GetFont()), path) and samePath((self.blank:GetFont()), R.f.blank)) then return false end
    self.push, self.reach = push, reach
    self.span = push and LA.PushField(px) or nil
    local hasParent, parent = pcall(function() return self.frame:GetParent() end)
    self.fit = hasParent and parent and R:Calibrate(parent, px, push) or nil
    -- The secret line is joined with padding spaces only inside this pcall.
    local joined, padded = pcall(function() return line .. string.rep(" ", LA.Pad(px, push)) end)
    if not joined then return false end
    self.blank:SetText(line)
    self.text:SetText(padded)
    self.active = true
    self:Layout()
    show(self, self.anchor ~= nil)
    return true
end

function Slot:Mode() return self.active and (self.push and "push" or "amount") or nil end
function Slot:Active() return self.active end

-- Fixed, public width of the amount's field: only in push mode (ceil(9 * px)). nil otherwise: the end
-- of an amount is not known, chain by Trail instead.
function Slot:Width() return self.active and self.push and self.span or nil end

-- frame, point, dx for anchoring something behind the amount's last figure (see header). nil for a
-- slot that is not showing an amount or is in push mode.
function Slot:Trail()
    if not self.active or self.push then return nil end
    -- Measured: the last figure's ink ends here.
    if self.fit then return self.text, "BOTTOMRIGHT", self.fit.shift - self.fit.tail end
    return self.text, "BOTTOMRIGHT", self.reach - LINE_END
end
