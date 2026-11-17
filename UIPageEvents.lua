local _, NS = ...
-- Events page: which events show text, play sound or write to the chat.
local Page = {}
NS.UIPageEvents = Page

local EVENTS = {
    {title = "Crit", graphics = "critGraphics", sound = "critSound", min = "critMinPercent", rule = "critSoundRule",
        allText = "All crits", record = "recordSoundEnabled", low = "lowCritEnabled", lowPercent = "lowCritPercent",
        warning = "No crit sound plays because the record sound is off."},
    {title = "Heal crit", graphics = "healGraphics", sound = "healSound", min = "healMinPercent", rule = "healSoundRule",
        allText = "All heal crits", record = "healRecordSoundEnabled", low = "healLowEnabled", lowPercent = "healLowPercent",
        warning = "No heal sound plays because the record sound is off.",
        graphicsDesc = "Heals on your target can come from other players."},
}

local SITUATION_OPTIONS = {{"all", "Everything"}, {"important", "Highlights only"}, {"off", "Off"}}

local function eventCard(view, form, spec)
    local db = function() return view.app.db end
    local function ruleAll() return db()[spec.rule] ~= "records" end
    form:Card(spec.title)
    form:Toggle({key = spec.graphics, label = "Show text", desc = spec.graphicsDesc})
    form:Toggle({key = spec.sound, label = "Play sound"})
    form:Slider({key = spec.min, label = "Only from this share of your record", advanced = true,
        desc = "Smaller crits show no text and play no normal sound. 0 shows all.",
        min = 0, max = 100, step = 5, format = "%d %%"})
    form:Select({key = spec.rule, label = "Sounds for", advanced = true,
        options = {{"all", spec.allText}, {"records", "Records only"}}})
    form:Toggle({key = spec.record, label = "Own sound for a new record", advanced = true})
    form:Toggle({key = spec.low, label = "Own sound for weak crits", advanced = true, visible = ruleAll})
    form:Slider({key = spec.lowPercent, label = "Weak up to this share of your record", advanced = true,
        min = 1, max = 100, step = 1, format = "%d %%",
        visible = function() return ruleAll() and db()[spec.low] == true end})
    form:Note({tone = "warning", text = spec.warning,
        visible = function() return not ruleAll() and db()[spec.record] ~= true end})
end

function Page.Build(view, form)
    local app = view.app
    for _, spec in ipairs(EVENTS) do eventCard(view, form, spec) end

    form:Card("Kill")
    form:Toggle({key = "killGraphics", label = "Show text"})
    form:Toggle({key = "killSound", label = "Play sound"})
    form:Note({text = "Your own kills and those of your pet count."})

    form:Card("Kill streak")
    form:Toggle({key = "streakGraphics", label = "Show text"})
    form:Toggle({key = "streakSound", label = "Play sound"})
    form:Slider({key = "streakWindow", label = "Time until the streak ends", desc = "Every kill starts this time again.",
        min = 2, max = 30, step = 1, format = "%d s"})
    form:Input({label = "Kills per step", anchor = "streakSteps", advanced = true, width = 260, keys = {"streakSteps"},
        desc = "Line 1 of the streak texts applies from the first number, line 2 from the second.",
        get = function() return NS.Logic.StreakStepsText(app.db) end,
        set = function(value)
            local steps = NS.Logic.ParseStreakSteps(value)
            if steps then app.db.streakSteps = steps end
        end})
    form:Select({key = "streakTargets", label = "Counts", advanced = true,
        options = {{"all", "All kills"}, {"players", "Player kills only"}}})
    form:Toggle({key = "streakHideKill", label = "Replace the kill text", advanced = true,
        desc = "The streak text appears instead of the normal kill text."})

    form:Card("Situations")
    form:Note({advanced = true, text = "Highlights are kills, kill streaks, procs and records."})
    for _, item in ipairs({{"situationWorld", "Open world"}, {"situationDungeon", "Dungeon"}, {"situationRaid", "Raid"},
        {"situationPvp", "Battleground and arena"}}) do
        form:Select({key = item[1], label = item[2], advanced = true, options = SITUATION_OPTIONS})
    end

    form:Card("Chat messages")
    form:Toggle({key = "chatEnabled", label = "Write events to your chat", advanced = true, desc = "Only you see these lines."})
    for _, item in ipairs({{"chatCrit", "Crits"}, {"chatRecord", "Crit records"}, {"chatLow", "Weak crits"},
        {"chatHeal", "Heal crits"}, {"chatHealRecord", "Heal records"}, {"chatHealLow", "Weak heal crits"}, {"chatKill", "Kills"}}) do
        form:Toggle({key = item[1], label = item[2], advanced = true, visible = function() return app.db.chatEnabled == true end})
    end
end
