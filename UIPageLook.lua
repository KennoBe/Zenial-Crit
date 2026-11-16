local _, NS = ...
-- Appearance page: font, colour, size, texts and position per event kind.
local Page = {}
NS.UIPageLook = Page

local KIND_OPTIONS = {{"crit", "Crit"}, {"heal", "Heal crit"}, {"kill", "Kill"}, {"streak", "Kill streak"}, {"proc", "Proc"}}
Page.KindOptions = KIND_OPTIONS

-- Keys of one suffix over all kinds ("Font" -> critFont, healFont, ...): the page resets all of them.
function Page.KindKeys(suffix)
    local keys = {}
    for _, kind in ipairs(NS.Logic.Kinds) do keys[#keys + 1] = kind .. suffix end
    return keys
end

-- The event kind chosen at the top of the Appearance and Animations pages.
function Page.KindSegment(view, form)
    form:Card()
    form:Segment({full = true, options = KIND_OPTIONS,
        get = function() return view.kind end, set = function(value) view.kind = value end})
end

function Page.Build(view, form)
    local app, api = view.app, view.api
    local function key(suffix) return function() return view.kind .. suffix end end
    local function is(...)
        for _, kind in ipairs({...}) do if view.kind == kind then return true end end
        return false
    end

    Page.KindSegment(view, form)

    form:Card("Text")
    form:Select({key = key("Font"), keys = Page.KindKeys("Font"), label = "Font", translate = false, options = function()
        local list = {{"standard", "Standard"}, {"comic", "Comic"}, {"epic", "Epic"}, {"heavy", "Heavy"}}
        for _, name in ipairs(api:SharedFonts()) do list[#list + 1] = {"shared:" .. name, name} end
        return list
    end})
    form:Note({visible = function() return is("crit") end,
        text = "Normal damage numbers use the crit font after you log out and back in."})
    form:Color({key = key("Color"), keys = Page.KindKeys("Color"), label = "Color"})
    form:Toggle({key = key("Gradient"), keys = Page.KindKeys("Gradient"), label = "Color gradient", advanced = true})
    form:Color({key = key("Color2"), keys = Page.KindKeys("Color2"), label = "Second color", advanced = true,
        visible = function() return app.db[view.kind .. "Gradient"] == true end})
    form:Slider({key = key("Size"), keys = Page.KindKeys("Size"), label = "Size of this event",
        desc = "Is multiplied by the overall size.", min = .5, max = 2.5, step = .05, format = "%.2f"})
    -- Opacity is stored as 0.2 to 1 and shown in percent.
    form:Slider({label = "Opacity", advanced = true, keys = Page.KindKeys("Alpha"), min = 20, max = 100, step = 5, format = "%d %%",
        get = function() return math.floor((app.db[view.kind .. "Alpha"] or 1) * 100 + .5) end,
        set = function(value) app.db[view.kind .. "Alpha"] = value / 100 end})
    form:Texts({key = key("Texts"), keys = Page.KindKeys("Texts"), maxLines = 20, maxChars = 40,
        visible = function() return not is("proc") end,
        label = function()
            if is("streak") then return "Texts per step, one per line. Line 1 is the second kill." end
            return "Texts, one per line. One is picked at random."
        end})
    form:Note({visible = function() return is("proc") end, text = "You set the text of a proc on the Procs page."})

    form:Card("Position")
    local function overNameplate() return app.db.displayMode == "nameplate" and is("crit", "kill") end
    form:Note({text = function() return overNameplate() and "Appears over the nameplate." or "" end})
    form:Toggle({key = "separatePositions", label = "Own position per event", advanced = true,
        onChange = function(value)
            if view.anchor and view.anchor:IsShown() then view:CloseAnchor() end
            if not value then app.db.x, app.db.y = app.db.critX, app.db.critY end
        end})
    form:Buttons({{text = "Move position", visible = function() return not overNameplate() end,
        onClick = function() view:Anchor(app.db.separatePositions and view.kind or "shared") end}})
end
