local _, NS = ...
-- Profiles page: active profile, copy, delete and reset of a whole profile.
local Page = {}
NS.UIPageProfiles = Page

local KEEP = {customSounds = true, customSoundNextID = true, schema = true}

function Page.Build(view, form)
    local app = view.app
    view.profileName, view.profileError = "", nil
    local nameRow

    local function names() return NS.Profiles.Names(app.root) end
    local function setError(message) view.profileError = message end

    form:Card("Profile")
    form:Select({label = "Profile of this character", anchor = "profile", translate = false,
        options = function()
            local list = {}
            for _, name in ipairs(names()) do list[#list + 1] = {name, name} end
            return list
        end,
        get = function() return app.profile end,
        set = function(name)
            setError(nil)
            local ok, err = app:SetProfile(name)
            -- The profile is active for this session even when the assignment could not be saved.
            if ok and err then setError(err) end
        end})
    nameRow = form:Input({label = "New profile", anchor = "newProfile", maxLetters = NS.Profiles.MaxNameLength,
        get = function() return view.profileName end, set = function(value) view.profileName = value or "" end})
    form:Buttons({{text = "Create as a copy", onClick = function()
        -- The field may still hold focus: read what is typed, not what was last committed.
        view.profileName = nameRow.control:GetText() or view.profileName
        local created, err = app:CreateProfile(view.profileName)
        if not created then setError(err); view:Refresh(); return end
        setError(nil)
        view.profileName = ""
        local ok, assignError = app:SetProfile(created)
        if ok and assignError then setError(assignError); view:Refresh() end
    end}})
    form:Note({tone = "warning", text = function() return view.profileError or "" end})
    local deleteRow = form:Buttons({{text = "Delete this profile", variant = "danger",
        onClick = function()
            local name = app.profile
            view:Confirm({title = "Delete this profile",
                text = string.format(NS.Locale.Text('Delete the profile "%s"?'), name),
                accept = "Delete", variant = "danger", onAccept = function()
                    local ok, err = app:DeleteProfile(name)
                    if ok then setError(nil) else setError(err) end
                    view:Refresh()
                end})
        end}})
    deleteRow.spec.advanced = true
    deleteRow.spec.visible = function() return #names() > 1 end

    form:Card("Reset")
    form:Buttons({{text = "Reset all settings of this profile", variant = "danger", onClick = function()
        local name = app.profile
        view:Confirm({title = "Reset", text = string.format(NS.Locale.Text('Reset all settings of the profile "%s"?'), name),
            accept = "Reset", variant = "danger", onAccept = function()
                local keys = {}
                for key in pairs(NS.Logic.Defaults()) do
                    if not KEEP[key] then keys[#keys + 1] = key end
                end
                table.sort(keys)
                app:ResetKeys(keys)
            end})
    end}})
    form:Note({text = "Your own sound files and the history stay."})
end
