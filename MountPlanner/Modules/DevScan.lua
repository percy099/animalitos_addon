-- /mplan scan: developer tool that builds the raw instance/mount dataset
-- straight from the client:
--   1. Encounter Journal: every instance x difficulty, loot items that teach
--      a mount (C_MountJournal.GetMountFromItem), with encounter info.
--   2. Dungeon entrances: every zone/continent map, entrance coordinates by
--      journalInstanceID, plus the continent each map belongs to.
-- Output goes to MountPlannerDB.scan (written on /reload or logout) and is
-- consumed by the offline pipeline. Not meant for end users.
local _, ns = ...

local Scan = {}
ns.DevScan = Scan

local TICK = 0.05            -- seconds between work units
local MAX_UIMAP_ID = 3000    -- upper bound for the map sweep
local MAPS_PER_TICK = 40
local MAX_ATTEMPTS = 5       -- loot passes per instance-difficulty while items load
local RETRY_PAUSE_TICKS = 60 -- ~3 s between retry rounds
local DIFFICULTIES = {
    1, 2, 23,                -- dungeon: normal, heroic, mythic
    3, 4, 5, 6, 9,           -- legacy raid: 10N, 25N, 10H, 25H, 40-player
    14, 15, 16,              -- flex raid: normal, heroic, mythic
    7, 17,                   -- LFR (legacy, current)
}

local running = false
local queue, retries = {}, {}
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

-- One work unit: one instance x one difficulty.
local function scanLoot(job)
    EJ_SelectInstance(job.jid)
    if EJ_IsValidInstanceDifficulty and not EJ_IsValidInstanceDifficulty(job.difficulty) then
        return true
    end
    EJ_SetDifficulty(job.difficulty)
    resetLootFilters()

    local inst = out.instances[job.jid]
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
                mounts[#mounts + 1] = {
                    itemID = info.itemID,
                    mountID = mountID,
                    encounterID = info.encounterID,
                }
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
    if uncached > 0 and job.attempts < MAX_ATTEMPTS then
        return false -- retry in a later round, once item data has loaded
    end
    inst.difficulties[job.difficulty] = { numLoot = numLoot, mounts = mounts, uncached = uncached > 0 and uncached or nil }
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
    MountPlannerDB.scan = out

    local state = {
        prevTier = EJ_GetCurrentTier and EJ_GetCurrentTier(),
        prevDifficulty = EJ_GetDifficulty and EJ_GetDifficulty(),
    }

    queue, retries = {}, {}
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

    local index, mapCursor, phase, pause = 1, 1, "loot", 0
    local ticker
    ticker = C_Timer.NewTicker(TICK, function()
        if InCombatLockdown() then return end -- pause during combat
        if pause > 0 then pause = pause - 1 return end
        if phase == "loot" then
            local job = queue[index]
            if job then
                local ok, done = pcall(scanLoot, job)
                if not ok then
                    out.errors = out.errors or {}
                    out.errors[#out.errors + 1] = ("%d/%d: %s"):format(job.jid, job.difficulty, tostring(done))
                elseif not done then
                    retries[#retries + 1] = job
                end
                index = index + 1
                if index % 100 == 0 then msg(("%d/%d"):format(index, total)) end
            elseif #retries > 0 then
                queue, retries, index = retries, {}, 1
                total = #queue
                pause = RETRY_PAUSE_TICKS
                msg(("waiting for item data, then retrying %d combinations"):format(total))
            else
                phase = "maps"
                msg("loot done, sweeping maps...")
            end
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
