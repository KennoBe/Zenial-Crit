local _, NS = ...
-- Animations page: animation, duration and flash per event kind, plus the settings for all events.
local Page = {}
NS.UIPageMotion = Page

function Page.Build(view, form)
    local app = view.app
    local look = NS.UIPageLook
    local function key(suffix) return function() return view.kind .. suffix end end
    local function is(...)
        for _, kind in ipairs({...}) do if view.kind == kind then return true end end
        return false
    end

    look.KindSegment(view, form)

    form:Card("Animation")
    form:Select({key = key("Anim"), keys = look.KindKeys("Anim"), label = "Animation", options = {
        {"pop", "Pop"}, {"slam", "Slam"}, {"rise", "Rise"}, {"shake", "Shake"}, {"pulse", "Pulse"}, {"fade", "Fade"}}})
    form:Slider({key = key("Duration"), keys = look.KindKeys("Duration"), label = "Duration", min = .4, max = 3, step = .05, format = "%.2f s"})
    form:Toggle({key = key("Flash"), keys = {"killFlash", "streakFlash", "procFlash"}, label = "Screen flash", advanced = true,
        desc = "The screen briefly lights up in the event color.", visible = function() return is("kill", "streak", "proc") end})
    form:Toggle({key = "streakEscalate", label = "Grow with every step", visible = function() return is("streak") end})

    form:Card("All events")
    form:Slider({key = "intensity", label = "Movement", min = 1, max = 3, step = 1, format = "%d"})
    form:Slider({key = "maxEffects", label = "Texts at the same time", advanced = true, min = 1, max = 6, step = 1, format = "%d"})
    form:Slider({key = "stackSpacing", label = "Spacing of stacked texts", advanced = true, desc = "At 0 the texts overlap.",
        min = 0, max = 120, step = 2, format = "%d"})
    form:Slider({key = "critGap", label = "Pause between crit texts", advanced = true, min = 0, max = 3, step = .05, format = "%.2f s"})
    form:Toggle({key = "combine", label = "Count repeated crits in one text", advanced = true,
        desc = "Shows ×2, ×3 instead of new texts."})
end
