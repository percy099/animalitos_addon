-- /aplan scan: developer tool that builds the raw instance/mount dataset
-- straight from the client:
--   1. Encounter Journal: every instance x difficulty, loot items that teach
--      a mount (C_MountJournal.GetMountFromItem), with encounter info.
--   2. Dungeon entrances: every zone/continent map, entrance coordinates by
--      journalInstanceID, plus the continent each map belongs to.
-- Output goes to AnimalitosPlannerDB.scan (written on /reload or logout) and is
-- consumed by the offline pipeline. Not meant for end users.
local _, ns = ...

local Scan = {}
ns.DevScan = Scan

local TICK = 0.05            -- seconds between work units
local MAX_UIMAP_ID = 3000    -- upper bound for the map sweep
local MAPS_PER_TICK = 40
local SETTLE = 0.3           -- seconds to wait after selecting before reading loot
local MAX_ATTEMPTS = 8       -- reads per instance-difficulty while items load
local DIFFICULTIES = {
    1, 2, 23,                -- dungeon: normal, heroic, mythic
    3, 4, 5, 6, 9,           -- legacy raid: 10N, 25N, 10H, 25H, 40-player
    14, 15, 16,              -- flex raid: normal, heroic, mythic
    7, 17,                   -- LFR (legacy, current)
}

local running = false
local queue = {}
local out

local function msg(text) ns:Print("|cff8dd3a8scan|r " .. text) end

local function pack(...)
    local t = { n = select("#", ...) }
    for i = 1, t.n do
        local v = select(i, ...)
        local tv = type(v)
        t[i] = (v == nil and "<nil>") or ((tv == "table" or tv == "function" or tv == "userdata") and "<" .. tv .. ">") or v
    end
    return t
end

-- Phase 1: list unique instances from every Encounter Journal tier.
local function collectInstances()
    local seen, list = {}, {}
    for t = 1, EJ_GetNumTiers() do
        EJ_SelectTier(t)
        local tierName = EJ_GetTierInfo(t)
        for _, isRaid in ipairs({ false, true }) do
            local i = 1
            while true do
                local jid, name = EJ_GetInstanceByIndex(i, isRaid)
                if not jid then break end
                if not seen[jid] then
                    seen[jid] = true
                    list[#list + 1] = { jid = jid, name = name, isRaid = isRaid, tier = t, tierName = tierName }
                end
                i = i + 1
            end
        end
    end
    return list
end

local function resetLootFilters()
    if EJ_ResetLootFilter then EJ_ResetLootFilter() end
    if C_EncounterJournal.ResetSlotFilter then C_EncounterJournal.ResetSlotFilter() end
end

local function isCached(itemID)
    if C_Item and C_Item.IsItemDataCachedByID then
        return C_Item.IsItemDataCachedByID(itemID)
    end
    return GetItemInfo(itemID) ~= nil
end

-- One work unit = one instance x one difficulty, in two steps:
--   select: point the Encounter Journal at it (the loot list rebuilds asynchronously)
--   read:   after SETTLE seconds, read the loot; if items are still missing or
--           uncached, request them and read again later (up to MAX_ATTEMPTS).
local function selectJob(job)
    EJ_SelectInstance(job.jid)
    if EJ_IsValidInstanceDifficulty and not EJ_IsValidInstanceDifficulty(job.difficulty) then
        return false
    end
    EJ_SetDifficulty(job.difficulty)
    resetLootFilters()
    return true
end

local function readJob(job)
    local numLoot = EJ_GetNumLoot() or 0
    local mounts, uncached = {}, 0
    for i = 1, numLoot do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if not info or not info.itemID then
            uncached = uncached + 1
        elseif not isCached(info.itemID) then
            -- GetMountFromItem returns nil for items the client has not cached yet.
            uncached = uncached + 1
            C_Item.RequestLoadItemDataByID(info.itemID)
        else
            local mountID = C_MountJournal.GetMountFromItem(info.itemID)
            if mountID then
                mounts[#mounts + 1] = { itemID = info.itemID, mountID = mountID, encounterID = info.encounterID }
                if info.encounterID and not out.encounters[info.encounterID] then
                    local name, _, _, _, _, journalInstanceID, dungeonEncounterID, instanceID =
                        EJ_GetEncounterInfo(info.encounterID)
                    out.encounters[info.encounterID] = {
                        name = name,
                        journalInstanceID = journalInstanceID,
                        dungeonEncounterID = dungeonEncounterID,
                        instanceID = instanceID,
                        raw = pack(EJ_GetEncounterInfo(info.encounterID)),
                    }
                end
            end
        end
    end
    job.attempts = (job.attempts or 0) + 1
    if (uncached > 0 or numLoot == 0) and job.attempts < MAX_ATTEMPTS then
        return false
    end
    out.instances[job.jid].difficulties[job.difficulty] = {
        numLoot = numLoot,
        mounts = mounts,
        uncached = uncached > 0 and uncached or nil,
        attempts = job.attempts,
    }
    return true
end

-- Phase 2: sweep every uiMap, record dungeon entrances and continent parents.
local function continentOf(uiMapID)
    local id, guard = uiMapID, 0
    while id and id > 0 and guard < 10 do
        local info = C_Map.GetMapInfo(id)
        if not info then return nil end
        if info.mapType == Enum.UIMapType.Continent then return id end
        id, guard = info.parentMapID, guard + 1
    end
    return nil
end

local function scanMaps(fromID, toID)
    for uiMapID = fromID, toID do
        local info = C_Map.GetMapInfo(uiMapID)
        if info and info.mapType and info.mapType >= Enum.UIMapType.Continent then
            local entrances = C_EncounterJournal.GetDungeonEntrancesForMap(uiMapID)
            if entrances and #entrances > 0 then
                for _, e in ipairs(entrances) do
                    local x, y
                    if e.position and e.position.GetXY then x, y = e.position:GetXY() end
                    local list = out.entrances[e.journalInstanceID] or {}
                    out.entrances[e.journalInstanceID] = list
                    list[#list + 1] = {
                        uiMapID = uiMapID,
                        mapType = info.mapType,
                        x = x, y = y,
                        areaPoiID = e.areaPoiID,
                        continent = continentOf(uiMapID),
                    }
                end
                out.maps[uiMapID] = { name = info.name, mapType = info.mapType, parentMapID = info.parentMapID }
            end
        end
    end
end

local function finish(state)
    if state.prevTier then EJ_SelectTier(state.prevTier) end
    if state.prevDifficulty then EJ_SetDifficulty(state.prevDifficulty) end
    running = false
    local mounts, combos = 0, 0
    for _, inst in pairs(out.instances) do
        for _, d in pairs(inst.difficulties) do
            combos = combos + 1
            mounts = mounts + #d.mounts
        end
    end
    local entranceCount = 0
    for _ in pairs(out.entrances) do entranceCount = entranceCount + 1 end
    out.finishedAt = date("%Y-%m-%d %H:%M:%S")
    out.stats = { instanceDifficulties = combos, mountDrops = mounts, instancesWithEntrance = entranceCount }
    msg(("done: %d instance-difficulties, %d mount drops, %d instances with entrances. Type /reload to save.")
        :format(combos, mounts, entranceCount))
end

function Scan:Run()
    if running then msg("already running.") return end
    if InCombatLockdown() then msg("not available in combat.") return end
    if EncounterJournal and EncounterJournal:IsShown() then
        msg("close the Adventure Guide first.") return
    end

    running = true
    local version, build = GetBuildInfo()
    out = {
        client = version .. "." .. build,
        locale = GetLocale(),
        startedAt = date("%Y-%m-%d %H:%M:%S"),
        instances = {}, encounters = {}, entrances = {}, maps = {},
    }
    AnimalitosPlannerDB.scan = out

    local state = {
        prevTier = EJ_GetCurrentTier and EJ_GetCurrentTier(),
        prevDifficulty = EJ_GetDifficulty and EJ_GetDifficulty(),
    }

    queue = {}
    for _, inst in ipairs(collectInstances()) do
        out.instances[inst.jid] = {
            name = inst.name, isRaid = inst.isRaid, tier = inst.tier, tierName = inst.tierName,
            info = pack(EJ_GetInstanceInfo(inst.jid)),
            difficulties = {},
        }
        for _, d in ipairs(DIFFICULTIES) do
            queue[#queue + 1] = { jid = inst.jid, difficulty = d }
        end
    end
    local total = #queue
    msg(("scanning %d instance-difficulty combinations, then maps. Keep the Adventure Guide closed."):format(total))

    local index, mapCursor, phase = 1, 1, "loot"
    local ticker
    ticker = C_Timer.NewTicker(TICK, function()
        if InCombatLockdown() then return end -- pause during combat
        if phase == "loot" then
            local job = queue[index]
            if not job then
                phase = "maps"
                msg("loot done, sweeping maps...")
                return
            end
            local ok, result
            if not job.selectedAt then
                ok, result = pcall(selectJob, job)
                if ok and result then
                    job.selectedAt = GetTime()
                    return
                end
            elseif GetTime() - job.selectedAt >= SETTLE then
                ok, result = pcall(readJob, job)
                if ok and not result then
                    job.selectedAt = GetTime() -- wait and read again
                    return
                end
            else
                return
            end
            if not ok then
                out.errors = out.errors or {}
                out.errors[#out.errors + 1] = ("%d/%d: %s"):format(job.jid, job.difficulty, tostring(result))
            end
            index = index + 1
            if index % 50 == 0 then msg(("%d/%d"):format(index, total)) end
        elseif phase == "maps" then
            local to = math.min(mapCursor + MAPS_PER_TICK - 1, MAX_UIMAP_ID)
            local ok, err = pcall(scanMaps, mapCursor, to)
            if not ok then
                out.errors = out.errors or {}
                out.errors[#out.errors + 1] = "maps " .. mapCursor .. ": " .. tostring(err)
            end
            mapCursor = to + 1
            if mapCursor > MAX_UIMAP_ID then
                ticker:Cancel()
                finish(state)
            end
        end
    end)
end

-- Mount items (/aplan scan items) -------------------------------------------------
-- The journal has no mount -> item link, and the item tooltip is where the
-- game says what a vendor asks for (reputation, faction, class; red when not
-- met). (1) every item ID is checked with GetItemInfoInstant (no cache
-- needed) for the Mount subclass, (2) those items are loaded and
-- GetMountFromItem gives the mount. Result: AnimalitosPlannerDB.mountItems
-- = { client, scannedAt, uncached, items = { [mountID] = itemID } }, read by
-- the pipeline into the dataset.
local MAX_ITEM_ID = 300000
local ITEMS_PER_TICK = 6000
local MOUNT_CLASS = (Enum.ItemClass and Enum.ItemClass.Miscellaneous) or 15
local MOUNT_SUBCLASS = (Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Mount) or 5
local itemsRunning = false

function Scan:RunItems()
    if itemsRunning then msg("item scan already running.") return end
    itemsRunning = true
    local version, build = GetBuildInfo()
    local result = { client = version .. "." .. build, scannedAt = date("%Y-%m-%d %H:%M:%S"), items = {} }
    local items, cursor, phase, waitUntil, startedWait = {}, 1, "sweep", 0, 0
    msg("looking for mount items...")
    local ticker
    ticker = C_Timer.NewTicker(TICK, function()
        if phase == "sweep" then
            local to = math.min(cursor + ITEMS_PER_TICK - 1, MAX_ITEM_ID)
            for id = cursor, to do
                local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
                if classID == MOUNT_CLASS and subClassID == MOUNT_SUBCLASS then
                    items[#items + 1] = id
                    C_Item.RequestLoadItemDataByID(id)
                end
            end
            cursor = to + 1
            if cursor > MAX_ITEM_ID then
                msg(("%d mount items; loading them..."):format(#items))
                phase, waitUntil, startedWait = "wait", GetTime() + 3, GetTime()
            end
        elseif phase == "wait" then
            -- Items load asynchronously; GetMountFromItem is nil until then.
            -- Every 2 s: ask again for the missing ones; read when all are
            -- loaded or after 90 s.
            if GetTime() < waitUntil then return end
            local pending = 0
            for _, id in ipairs(items) do
                if not C_Item.IsItemDataCachedByID(id) then
                    pending = pending + 1
                    C_Item.RequestLoadItemDataByID(id)
                end
            end
            result.uncached = pending
            if pending == 0 or GetTime() - startedWait > 90 then
                phase = "read"
            else
                msg(("%d items still loading..."):format(pending))
                waitUntil = GetTime() + 2
            end
        elseif phase == "read" then
            ticker:Cancel()
            local n = 0
            for _, id in ipairs(items) do
                local mountID = C_MountJournal.GetMountFromItem(id)
                -- Lowest item ID wins when several items teach one mount.
                if mountID and not result.items[mountID] then
                    result.items[mountID] = id
                    n = n + 1
                end
            end
            AnimalitosPlannerDB.mountItems = result
            AnimalitosPlannerDB.vendorProbe = nil -- old diagnostic
            msg(("%d mount items (%d not loaded), %d mounts mapped. /reload, then run the pipeline."):format(
                #items, result.uncached or 0, n))
            itemsRunning = false
        end
    end)
end