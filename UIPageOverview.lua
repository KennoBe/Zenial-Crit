local _, NS = ...
-- Overview page: master switch, preset, display mode, size and setup.
local Page = {}
NS.UIPageOverview = Page

function Page.Build(view, form)
    local app, L = view.app, NS.Logic

    form:Card()
    form:Toggle({key = "enabled", label = "Effects on",
        desc = "Turns texts, sounds and chat messages on or off. The history keeps recording."})
    form:Select({label = "Preset", keys = L.PresetKeys,
        desc = "Sets animations, sizes and sounds in one step. Texts, positions and sound choices stay.",
        options = {{"minimal", "Minimal"}, {"standard", "Standard"}, {"action", "Action"}, {"custom", "Custom"}},
        get = function() return L.PresetOf(app.db) end,
        -- "Custom" only shows that no preset matches; picking it changes nothing.
        set = function(value) if value ~= "custom" then app:ApplyPreset(value) end end})

    form:Card("Display")
    form:Segment({key = "displayMode", label = "Crit and kill text",
        desc = "Kill streaks, procs and heal crits always use the fixed position.",
        options = {{"nameplate", "Over the nameplate"}, {"fixed", "Fixed position"}}})
    -- Over the nameplate the fixed size still counts for heal crits, streaks and procs.
    form:Slider({key = "nameplateScale", label = "Size over the nameplate", min = .6, max = 4.2, step = .05, format = "%.2f",
        visible = function() return app.db.displayMode == "nameplate" end})
    form:Slider({key = "scale", min = .6, max = 2.5, step = .05, format = "%.2f", label = function()
        return app.db.displayMode == "nameplate" and "Size at the fixed position" or "Size"
    end})
    form:Buttons({{text = "Move position", onClick = function() view:Anchor("shared") end,
        visible = function() return app.db.separatePositions ~= true end}})
    form:Note({text = function()
        return app.db.separatePositions == true and "Positions are moved per event on the Appearance page." or ""
    end})

    form:Card("Setup")
    form:Buttons({{text = "Run the setup wizard", onClick = function()
        -- Like /zcrit config: the settings window gives way to the assistant.
        if app.ui and app.ui.frame then app.ui.frame:Hide() end
        NS.Setup.Open()
    end}})
    form:Note({tone = "warning", text = function()
        return app.eventState and app.eventState.unitCombat == "failed" and "Crits cannot be recognized in this game version." or ""
    end})
    form:Note({tone = "warning", text = function()
        return app.eventState and app.eventState.partyKill == "failed" and "Kills cannot be recognized in this game version." or ""
    end})
end
