-- Entry points of the standalone Crit window (/zcrit settings) and setup wizard (/zcrit config).
local _, ns = ...
local function slash(argument)
    local handler = _G.SlashCmdList and _G.SlashCmdList.ZENIALCRIT
    if type(handler) == "function" then handler(argument) end
end
ns.LauncherSpec = {
    openSettings = function() slash("settings") end,
    openWizard = function() slash("config") end,
}
