-- Bootstrap: wires modules to game events and registers slash commands.
-- Loaded last so every module table already exists.
local ADDON_NAME, ns = ...
local L = ns.L

ns:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    ns.Storage:Init()
    ns.Probe:Init()
end)

ns:On("PLAYER_LOGIN", function()
    ns.Storage:TouchCharacter()
    ns.Collection:Scan()
    ns:Print(L["LOADED"]:format(ns.VERSION))
end)

-- Journal data can arrive slightly after login; rescan once the world is ready.
ns:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    if isInitialLogin or isReloadingUi then
        ns:Debounce("scan", 2, function()
            ns.Collection:Scan()
            ns.UI:Refresh()
        end)
    end
end)

ns:On("NEW_MOUNT_ADDED", function()
    ns:Debounce("scan", 0.5, function()
        ns.Collection:Scan()
        ns.UI:Refresh()
        ns:Print(L["NEW_MOUNT"])
    end)
end)

ns:On("PLAYER_LEVEL_UP", function()
    ns.Storage:TouchCharacter()
end)

-- Slash commands
SLASH_MOUNTPLANNER1 = "/mplan"
SLASH_MOUNTPLANNER2 = "/mountplanner"
SlashCmdList.MOUNTPLANNER = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "" or cmd == "show" then
        ns.UI:Toggle()
    elseif cmd == "probe" then
        ns.Probe:Run()
    elseif cmd == "scan" then
        ns.DevScan:Run()
    elseif cmd == "reset" then
        ns.UI:ResetPosition()
    else
        ns:Print(L["HELP"])
    end
end

-- Addon compartment (minimap addon menu) entry declared in the TOC.
function MountPlanner_OnAddonCompartmentClick()
    ns.UI:Toggle()
end
