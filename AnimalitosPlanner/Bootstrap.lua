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
    ns.MinimapButton:Init()
    ns:Print(L["LOADED"]:format(ns.VERSION))
end)

-- Journal data can arrive slightly after login; rescan once the world is ready.
ns:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    if isInitialLogin or isReloadingUi then
        ns:Debounce("scan", 2, function()
            ns.Collection:Scan()
            ns.PlannerMini:Restore() -- reopen if it was open last session
            ns.UI:Refresh()
        end)
        -- Mount achievements are built in the background a little later, so
        -- they are usually ready before the window is first opened.
        C_Timer.After(8, function() ns.Collection:BuildAchievements() end)
    end
end)

ns:On("ACHIEVEMENT_EARNED", function()
    ns:Debounce("achievements", 1, function()
        ns.Collection:InvalidateAchievements()
        ns.UI:Refresh()
    end)
end)

-- A world quest done (Kraulok's) changes a world boss to Locked.
ns:On("QUEST_TURNED_IN", function()
    ns:Debounce("quests", 1, function() ns.UI:Refresh() end)
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
    ns:Debounce("lfginfo", 3, function() ns.Holidays:Request() end)
end)

-- Dungeon Finder data (world event bosses: is the event on, done today?).
local function lfgChanged()
    ns:Debounce("lfgui", 1, function() ns.UI:Refresh() end)
end
ns:On("LFG_UPDATE_RANDOM_INFO", lfgChanged)
ns:On("LFG_LOCK_INFO_RECEIVED", lfgChanged)

ns:On("UPDATE_INSTANCE_INFO", function()
    ns.Lockouts:Refresh()
    ns.UI:Refresh()
end)

local function afterBossKill()
    ns:Debounce("raidinfo", 3, function() ns.Lockouts:Request() end)
end
ns:On("BOSS_KILL", afterBossKill)

-- Highlight the current zone in the list (never reorders saved edits).
ns:On("ZONE_CHANGED_NEW_AREA", function()
    ns:Debounce("zone", 1, function() ns.UI:Refresh() end)
end)
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
        if not e.hidden then
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

    -- Name the mounts that need verification (with the reason) so they can be checked.
    local verifyShown = 0
    for _, e in ipairs(entries) do
        for id, m in pairs(e.mounts) do
            if #m.verify > 0 and #m.ready == 0 and verifyShown < MAX_LOCKED_LINES then
                verifyShown = verifyShown + 1
                if verifyShown == 1 then print("  " .. L["NOW_VERIFY_HEADER"]) end
                local v = m.verify[1]
                print(("    |cff999999%s|r — %s (%s): %s"):format(mountName(id), ns.FarmList:InstanceName(e.jid),
                    ns.FarmList:DifficultyName(v.difficulty), v.reason))
            end
        end
    end

    print("  " .. L["NOW_FOOTER"]:format(counts[S.VERIFY] or 0, counts[S.COLLECTED] or 0,
        counts[S.UNAVAILABLE] or 0, counts[S.OUT_OF_SCOPE] or 0))
    if #printed > 0 then print("  " .. L["NOW_GO_HINT"]) end
end

-- "/aplan why <mountID | part of the name>": per-difficulty state and reason.
local function explainMount(query)
    local wanted = tonumber(query)
    local needle = not wanted and query:lower() or nil
    local found = 0
    for _, src in ipairs(ns.Data.sources) do
        local m = ns.MountJournal:GetMount(src.mountID)
        local name = m and m.name or ("#" .. src.mountID)
        if src.mountID == wanted or (needle and name:lower():find(needle, 1, true)) then
            found = found + 1
            local rec = ns.Data.instances[src.journalInstanceID]
            ns:Print(("%s (mountID %d) — %s, %s"):format(name, src.mountID,
                ns.FarmList:InstanceName(src.journalInstanceID), EJ_GetEncounterInfo(src.journalEncounterID) or "?"))
            for _, d in ipairs(src.difficulties) do
                local state, reason, resetAt = ns.Eligibility:Evaluate(src, d)
                local left = resetAt and (" — " .. L["NOW_RESETS_IN"]:format(SecondsToTime(math.max(0, resetAt - time())))) or ""
                print(("    %s: |cffffd200%s|r — %s%s"):format(ns.FarmList:DifficultyName(d), state, reason or "", left))
            end
            local saved = rec and rec.mapID and ns.Lockouts:ForMap(rec.mapID) or {}
            for d, r in pairs(saved) do
                local killed = {}
                for boss in pairs(r.killed) do killed[#killed + 1] = boss end
                print(("    saved: %s (%d) %d/%d — %s"):format(r.difficultyName or "?", d, r.encounterProgress or 0,
                    r.numEncounters or 0, table.concat(killed, ", ")))
            end
        end
    end
    if found == 0 then ns:Print(L["WHY_NOT_FOUND"]:format(query)) end
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
    elseif cmd == "curated" then
        ns:Print("curated sources:")
        ns.FarmList:DebugCurated()
    elseif cmd == "events" then
        ns:Print("world event bosses:")
        ns.Holidays:Debug()
    elseif cmd == "events test" then
        -- Shows every event as on (to see the UI outside the events); /reload ends it.
        ns.Holidays.test = not ns.Holidays.test or nil
        ns:Print("events test mode: " .. (ns.Holidays.test and "on" or "off"))
        ns.UI:Refresh()
    elseif cmd == "costs" then
        ns:Print("missing mounts with a price:")
        ns.Collection:DebugCosts()
    elseif cmd == "unknown" then
        ns:Print("mounts without a source type:")
        ns.MountJournal:DebugUnknownSources()
    elseif cmd == "mini" then
        ns.PlannerMini:Toggle()
    elseif cmd == "probe" then
        ns.Probe:Run()
    elseif cmd:match("^why%s+.+") then
        explainMount(strtrim(msg):match("^%S+%s+(.+)$"))
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
    elseif cmd == "navdebug" then
        ns.Navigation:Debug()
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
