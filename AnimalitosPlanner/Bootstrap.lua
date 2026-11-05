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

-- Lockouts: ask the server on login/zone-in and after a boss kill;
-- UPDATE_INSTANCE_INFO delivers the answer.
ns:On("PLAYER_ENTERING_WORLD", function()
    ns:Debounce("raidinfo", 1, function() ns.Lockouts:Request() end)
end)

ns:On("UPDATE_INSTANCE_INFO", function()
    ns.Lockouts:Refresh()
    ns.UI:Refresh()
end)

local function afterBossKill()
    ns:Debounce("raidinfo", 3, function() ns.Lockouts:Request() end)
end
ns:On("BOSS_KILL", afterBossKill)
ns:On("ENCOUNTER_END", afterBossKill)

-- "/aplan now": print the farmable-now list to chat (v0.3 test surface; the
-- real screen arrives in v0.4).
local MAX_READY_LINES, MAX_LOCKED_LINES = 15, 8

local function mountName(id)
    local m = ns.MountJournal:GetMount(id)
    return m and m.name or ("#" .. id)
end

local function diffList(list)
    local names = {}
    for _, d in ipairs(list) do names[#names + 1] = ns.FarmList:DifficultyName(d) end
    return table.concat(names, ", ")
end

local function printFarmList()
    local entries, counts = ns.FarmList:Build()
    local S = ns.Eligibility.STATES
    if not ns.Lockouts.loaded then ns:Print(L["NOW_LOCKOUTS_LOADING"]) end

    local printed = {}
    ns:Print(L["NOW_HEADER"]:format(counts[S.READY] or 0))

    for _, e in ipairs(entries) do
        if e.readyCount == 0 or #printed >= MAX_READY_LINES then break end
        printed[#printed + 1] = e.jid
        local parts = {}
        for id, m in pairs(e.mounts) do
            if #m.ready > 0 then
                parts[#parts + 1] = ("|cff8dd3a8%s|r (%s)"):format(mountName(id), diffList(m.ready))
            end
        end
        local zone = e.inst.entrance and C_Map.GetMapInfo(e.inst.entrance.uiMapID)
        local near = e.near == 2 and " |cffa88ad7*|r" or ""
        print(("  %d. |cffffd200%s|r [%s]%s — %s"):format(#printed, ns.FarmList:InstanceName(e.jid),
            zone and zone.name or "?", near, table.concat(parts, "; ")))
    end
    ns.FarmList.lastPrinted = printed

    local lockedShown = 0
    for _, e in ipairs(entries) do
        for id, m in pairs(e.mounts) do
            if #m.locked > 0 and #m.ready == 0 and lockedShown < MAX_LOCKED_LINES then
                lockedShown = lockedShown + 1
                if lockedShown == 1 then print("  " .. L["NOW_LOCKED_HEADER"]) end
                local left = m.resetAt and SecondsToTime(math.max(0, m.resetAt - time())) or "?"
                print(("    |cffe0a040%s|r — %s (%s): %s"):format(mountName(id), ns.FarmList:InstanceName(e.jid),
                    diffList(m.locked), L["NOW_RESETS_IN"]:format(left)))
            end
        end
    end

    print("  " .. L["NOW_FOOTER"]:format(counts[S.VERIFY] or 0, counts[S.COLLECTED] or 0,
        counts[S.UNAVAILABLE] or 0, counts[S.OUT_OF_SCOPE] or 0))
    if #printed > 0 then print("  " .. L["NOW_GO_HINT"]) end
end

ns:On("PLAYER_LEVEL_UP", function()
    ns.Storage:TouchCharacter()
end)

-- Slash commands
SLASH_ANIMALITOSPLANNER1 = "/aplan"
SLASH_ANIMALITOSPLANNER2 = "/animalitos"
SlashCmdList.ANIMALITOSPLANNER = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "" or cmd == "show" then
        ns.UI:Toggle()
    elseif cmd == "probe" then
        ns.Probe:Run()
    elseif cmd == "now" then
        printFarmList()
    elseif cmd:match("^go%s+%d+$") then
        local n = tonumber(cmd:match("%d+"))
        local list = ns.FarmList.lastPrinted
        if not list then printFarmList() list = ns.FarmList.lastPrinted end
        if list and list[n] then ns.Navigation:GoToInstance(list[n]) else ns:Print(L["NOW_BAD_INDEX"]) end
    elseif cmd:match("^maxtier%s+%d+$") then
        local tier = tonumber(cmd:match("%d+"))
        ns.Storage.db.settings.maxTier = tier
        ns:Print(L["MAXTIER_SET"]:format(tier, (EJ_GetTierInfo(tier)) or "?"))
    elseif cmd == "nav tomtom" or cmd == "nav native" then
        ns.Navigation:SetMode(cmd:match("nav (%a+)"))
    elseif cmd == "scan" then
        ns.DevScan:Run()
    elseif cmd == "reset" then
        ns.UI:ResetPosition()
    else
        ns:Print(L["HELP"])
    end
end

-- Addon compartment (minimap addon menu) entry declared in the TOC.
function AnimalitosPlanner_OnAddonCompartmentClick()
    ns.UI:Toggle()
end
