local _, NS = ...
-- Sounds page: event choice, sound, mix and channel, sound pause, and the library.
local Page = {}
NS.UIPageSounds = Page

local CHANNEL_KEYS = {
    crit = "critSoundChannel", heal = "healSoundChannel", kill = "killSoundChannel", record = "recordSoundChannel",
    healRecord = "healRecordSoundChannel", low = "lowSoundChannel", healLow = "healLowSoundChannel",
    streak = "streakSoundChannel", proc = "procSoundChannel", windfury = "windfurySoundChannel",
}
-- The setting that switches the event of a sound category on.
local ENABLE_KEYS = {
    crit = "critSound", heal = "healSound", kill = "killSound", streak = "streakSound", proc = "procSound", windfury = "procSound",
    record = "recordSoundEnabled", healRecord = "healRecordSoundEnabled", low = "lowCritEnabled", healLow = "healLowEnabled",
}
Page.ChannelKeys, Page.EnableKeys = CHANNEL_KEYS, ENABLE_KEYS

function Page.Build(view, form, page)
    local app, api = view.app, view.api
    local S = NS.Sounds
    local function keys() return S.CategoryKeys[view.soundCategory] end
    local function mixed() return app.db[keys().mode] == "mix" end

    -- Everything this page stores, for "Reset this page"; the own files stay.
    local resetKeys = {"soundCooldown"}
    for category, spec in pairs(S.CategoryKeys) do
        resetKeys[#resetKeys + 1] = spec.mode; resetKeys[#resetKeys + 1] = spec.ids; resetKeys[#resetKeys + 1] = CHANNEL_KEYS[category]
    end
    table.sort(resetKeys)

    form:Card("Sound")
    local options = {}
    for _, entry in ipairs(NS.UISounds.Categories) do options[#options + 1] = {entry[1], entry[2]} end
    form:Select({label = "Event", anchor = "soundEvent", options = options, keys = resetKeys,
        get = function() return view.soundCategory end, set = function(value) view.soundCategory = value end})
    form:Select({label = "Sound", anchor = "sound", translate = false, visible = function() return not mixed() end,
        options = function()
            local list, current = {}, app.db[keys().ids] and app.db[keys().ids][1]
            local found = false
            for _, item in ipairs(S.Catalog(app.db, api.env)) do
                list[#list + 1] = {item.id, item.name}
                if item.id == current then found = true end
            end
            if current and not found then
                -- An unavailable sound stays visible with its name.
                local name = S.Describe(app.db, current, api.env)
                list[#list + 1] = {current, name .. " (" .. NS.Locale.Text("missing") .. ")"}
            end
            return list
        end,
        get = function() return app.db[keys().ids] and app.db[keys().ids][1] end,
        set = function(value) app.db[keys().mode], app.db[keys().ids] = "single", {value} end})
    form:Note({text = function()
        local ids = app.db[keys().ids]
        if mixed() or not ids or ids[1] ~= "announcer" then return "" end
        return "Says the step of the kill streak. The words do not follow your own texts."
    end})
    form:Note({text = function()
        if not mixed() then return "" end
        local names = view:SoundSummary(view.soundCategory)
        if #names == 0 then return "No sound selected." end
        return "Mix: %s", table.concat(names, ", ")
    end})
    form:Buttons({{text = "Listen", onClick = function()
        local ok, reason = app:PreviewSound(view.soundCategory)
        view:SetSoundStatus(ok, reason)
    end}})
    form:Note({tone = "warning", text = function() return view.soundFeedback or "" end})
    form:Note({tone = "warning", text = function()
        return app.db[ENABLE_KEYS[view.soundCategory]] == false and "This sound is off on the Events page." or ""
    end})
    form:Toggle({label = "Random mix of several sounds", anchor = "mix", advanced = true, desc = "You pick the sounds in the library below.",
        get = function() return mixed() end,
        set = function(value)
            app.db[keys().mode] = value and "mix" or "single"
            if not value and #app.db[keys().ids] > 1 then app.db[keys().ids] = {app.db[keys().ids][1]} end
        end})
    form:Select({label = "Volume slider", anchor = "channel", advanced = true, translate = true,
        desc = "The game has no volume per sound. This picks which slider of the game applies.",
        options = {{"Master", "Master"}, {"SFX", "SFX"}, {"Dialog", "Dialog"}},
        default = function() return form.ctx.default(CHANNEL_KEYS[view.soundCategory]) end,
        get = function() return NS.Logic.SoundChannel(app.db, view.soundCategory) end,
        set = function(value) app.db[CHANNEL_KEYS[view.soundCategory]] = value end})

    form:Card("All sounds")
    form:Slider({key = "soundCooldown", label = "Pause between sounds", desc = "A more important event may interrupt the pause.",
        min = 0, max = 30, step = .25, format = "%.2f s"})

    form:Card("Library")
    form:Custom({advanced = true, anchor = "library", height = NS.UISounds.LibraryHeight,
        build = function(frame, width) NS.UISounds.BuildLibrary(view, frame, width) end,
        refresh = function(_, width) NS.UISounds.FitLibrary(view, width); view:RefreshSounds() end})
end
