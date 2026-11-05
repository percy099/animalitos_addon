-- /aplan probe: records API availability, return signatures and sample data
-- into AnimalitosPlannerDB.diagnostics so the team can validate the design
-- assumptions against the real client build (read the SavedVariables file
-- after /reload or logout).
local _, ns = ...

local Probe = {}
ns.Probe = Probe

-- APIs the design documents depend on (doc 04 + v1.1 validation backlog).
local API_PATHS = {
    -- Mount Journal
    "C_MountJournal.GetMountIDs",
    "C_MountJournal.GetMountInfoByID",
    "C_MountJournal.GetMountInfoExtraByID",
    "C_MountJournal.GetMountFromItem",
    "C_MountJournal.GetMountFromSpell",
    "C_MountJournal.GetNumMounts",
    -- Encounter Journal
    "EJ_GetNumTiers", "EJ_GetTierInfo", "EJ_SelectTier", "EJ_GetCurrentTier",
    "EJ_GetInstanceByIndex", "EJ_SelectInstance", "EJ_GetInstanceInfo",
    "EJ_GetEncounterInfoByIndex", "EJ_GetEncounterInfo", "EJ_SetDifficulty", "EJ_GetDifficulty",
    "EJ_IsValidInstanceDifficulty", "EJ_GetNumLoot", "EJ_ResetLootFilter",
    "C_EncounterJournal.ResetSlotFilter", "C_Map.GetMapChildrenInfo",
    "C_EncounterJournal.GetLootInfoByIndex",
    "C_EncounterJournal.GetDungeonEntrancesForMap",
    "C_EncounterJournal.GetInstanceForGameMap",
    -- Map / navigation
    "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetPlayerMapPosition",
    "C_Map.CanSetUserWaypointOnMap", "C_Map.SetUserWaypoint", "C_Map.HasUserWaypoint",
    "C_Map.GetUserWaypoint", "C_Map.ClearUserWaypoint",
    "C_SuperTrack.SetSuperTrackedUserWaypoint", "C_SuperTrack.IsSuperTrackingUserWaypoint",
    "UiMapPoint.CreateFromCoordinates",
    -- Requirements
    "C_QuestLog.IsQuestFlaggedCompleted",
    "C_QuestLog.IsQuestFlaggedCompletedOnAccount",
    "C_Reputation.GetFactionDataByID",
    "C_Reputation.IsAccountWideReputation",
    "C_MajorFactions.GetMajorFactionData",
    "C_MajorFactions.GetMajorFactionIDs",
    "GetAchievementInfo",
    -- Lockouts
    "RequestRaidInfo", "GetNumSavedInstances", "GetSavedInstanceInfo",
    "GetSavedInstanceEncounterInfo", "GetNumSavedWorldBosses", "GetSavedWorldBossInfo",
    "GetDifficultyInfo",
}

local function resolve(path)
    local node = _G
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

-- Pack any return list into a SavedVariables-safe table, keeping arity.
local function pack(...)
    local n = select("#", ...)
    local t = { n = n }
    for i = 1, n do
        local v = select(i, ...)
        local tv = type(v)
        if v == nil then
            t[i] = "<nil>"
        elseif tv == "table" or tv == "function" or tv == "userdata" then
            t[i] = "<" .. tv .. ">"
        else
            t[i] = v
        end
    end
    return t
end

local function section(d, name, fn)
    local ok, err = pcall(fn)
    if not ok then
        d.errors[#d.errors + 1] = name .. ": " .. tostring(err)
    end
end

local function probeEnvironment(d)
    local version, build, date, toc = GetBuildInfo()
    d.client = { version = version, build = build, date = date, toc = toc }
    d.locale = GetLocale()
    d.region = GetCurrentRegionName and GetCurrentRegionName() or GetCurrentRegion()
    d.character = {
        key = ns:GetCharacterKey(),
        level = UnitLevel("player"),
        faction = UnitFactionGroup("player"),
        class = select(2, UnitClass("player")),
    }
    d.addonVersion = ns.VERSION
    d.unknownEvents = CopyTable(ns.unknownEvents)
end

local function probeApis(d)
    d.apis = {}
    for _, path in ipairs(API_PATHS) do
        d.apis[path] = type(resolve(path))
    end
end

local function probeMountJournal(d)
    local mj = {}
    d.mountJournal = mj
    local ids = C_MountJournal.GetMountIDs()
    mj.count = ids and #ids or 0
    mj.samples = {}
    -- Up to 4 samples per bucket: collected / missing+visible / missing+hidden,
    -- with full return lists (validates signatures and sourceText formats).
    local buckets = { collected = 0, missingVisible = 0, missingHidden = 0 }
    for i = 1, mj.count do
        local id = ids[i]
        local info = pack(C_MountJournal.GetMountInfoByID(id))
        local bucket = (info[11] == true and "collected")
            or (info[10] == true and "missingHidden")
            or "missingVisible"
        if buckets[bucket] < 4 then
            buckets[bucket] = buckets[bucket] + 1
            mj.samples[#mj.samples + 1] = {
                bucket = bucket,
                mountID = id,
                info = info,
                extra = pack(C_MountJournal.GetMountInfoExtraByID(id)),
            }
        end
        if buckets.collected >= 4 and buckets.missingVisible >= 4 and buckets.missingHidden >= 4 then break end
    end
    -- sourceType histogram (all mounts), with the localized label used by the UI.
    mj.sourceTypes = {}
    for i = 1, mj.count do
        local st = select(6, C_MountJournal.GetMountInfoByID(ids[i]))
        local k = tostring(st)
        mj.sourceTypes[k] = mj.sourceTypes[k] or { count = 0, label = ns.MountJournal:GetSourceTypeLabel(st) }
        mj.sourceTypes[k].count = mj.sourceTypes[k].count + 1
    end
    mj.summary = ns.Collection.summary and CopyTable(ns.Collection.summary) or nil
end

local function probeEncounterJournal(d)
    local ej = { tiers = {} }
    d.encounterJournal = ej
    local previousTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
    for t = 1, EJ_GetNumTiers() do
        EJ_SelectTier(t)
        local tier = { name = EJ_GetTierInfo(t), dungeons = {}, raids = {} }
        for _, isRaid in ipairs({ false, true }) do
            local list = isRaid and tier.raids or tier.dungeons
            local i = 1
            while true do
                local instanceID, name = EJ_GetInstanceByIndex(i, isRaid)
                if not instanceID then break end
                list[#list + 1] = { journalInstanceID = instanceID, name = name }
                i = i + 1
            end
        end
        ej.tiers[t] = tier
    end
    if previousTier then EJ_SelectTier(previousTier) end
end

local function entrancesFor(mapID)
    local out = {}
    local list = C_EncounterJournal.GetDungeonEntrancesForMap(mapID)
    for _, e in ipairs(list or {}) do
        local x, y
        if e.position and e.position.GetXY then x, y = e.position:GetXY() end
        out[#out + 1] = {
            name = e.name,
            journalInstanceID = e.journalInstanceID,
            areaPoiID = e.areaPoiID,
            x = x, y = y,
        }
    end
    return out
end

local function probeMap(d)
    local m = {}
    d.map = m
    local mapID = C_Map.GetBestMapForUnit("player")
    m.mapID = mapID
    if not mapID then return end
    local info = C_Map.GetMapInfo(mapID)
    m.name = info and info.name
    m.mapType = info and info.mapType
    m.parentMapID = info and info.parentMapID
    m.canSetUserWaypoint = C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID)
    m.hasUserWaypoint = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then m.playerX, m.playerY = pos:GetXY() end
    if C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
        m.entrances = entrancesFor(mapID)
        if m.parentMapID and m.parentMapID > 0 then
            m.parentEntrances = entrancesFor(m.parentMapID)
        end
    end
end

local function probeTomTom(d)
    d.tomtom = {
        loaded = C_AddOns.IsAddOnLoaded("TomTom") and true or false,
        version = C_AddOns.GetAddOnMetadata("TomTom", "Version"),
        addWaypoint = type(TomTom) == "table" and type(TomTom.AddWaypoint) or "nil",
        removeWaypoint = type(TomTom) == "table" and type(TomTom.RemoveWaypoint) or "nil",
    }
end

-- Saved instances arrive asynchronously after RequestRaidInfo().
local waitingForRaidInfo = false

local function captureSavedInstances()
    local d = AnimalitosPlannerDB.diagnostics
    if not d then return end
    local out = { count = GetNumSavedInstances(), instances = {} }
    for i = 1, out.count do
        local entry = { info = pack(GetSavedInstanceInfo(i)), encounters = {} }
        local numEncounters = entry.info[11]
        if type(numEncounters) == "number" then
            for j = 1, numEncounters do
                entry.encounters[j] = pack(GetSavedInstanceEncounterInfo(i, j))
            end
        end
        out.instances[i] = entry
    end
    out.worldBosses = {}
    if GetNumSavedWorldBosses then
        for i = 1, GetNumSavedWorldBosses() do
            out.worldBosses[i] = pack(GetSavedWorldBossInfo(i))
        end
    end
    d.savedInstances = out
end

function Probe:Init()
    ns:On("UPDATE_INSTANCE_INFO", function()
        if not waitingForRaidInfo then return end
        waitingForRaidInfo = false
        section(AnimalitosPlannerDB.diagnostics, "savedInstances", captureSavedInstances)
        ns:Print(ns.L["PROBE_DONE"])
    end)
end

function Probe:Run()
    local d = { errors = {}, ranAt = date("%Y-%m-%d %H:%M:%S") }
    AnimalitosPlannerDB.diagnostics = d
    section(d, "environment", function() probeEnvironment(d) end)
    section(d, "apis", function() probeApis(d) end)
    section(d, "mountJournal", function() probeMountJournal(d) end)
    section(d, "encounterJournal", function() probeEncounterJournal(d) end)
    section(d, "map", function() probeMap(d) end)
    section(d, "tomtom", function() probeTomTom(d) end)

    waitingForRaidInfo = true
    ns:Print(ns.L["PROBE_WAITING_RAID"])
    RequestRaidInfo()
    -- Fallback if the event never fires.
    C_Timer.After(5, function()
        if waitingForRaidInfo then
            waitingForRaidInfo = false
            section(d, "savedInstances", captureSavedInstances)
            ns:Print(ns.L["PROBE_DONE"])
        end
    end)
end
