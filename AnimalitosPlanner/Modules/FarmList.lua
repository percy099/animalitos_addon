-- "Farmable now" list (docs/03-funcional.md §5): legacy instances with at
-- least one missing mount whose boss is still lootable this reset, grouped
-- per instance and ordered by proximity.
local _, ns = ...

local FarmList = {}
ns.FarmList = FarmList

local function playerLocation()
    local mapID = C_Map.GetBestMapForUnit("player")
    local ancestors, continent = {}, nil
    local id, guard = mapID, 0
    while id and id > 0 and guard < 10 do
        ancestors[id] = true
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if info.mapType == Enum.UIMapType.Continent then continent = id end
        id, guard = info.parentMapID, guard + 1
    end
    return ancestors, continent
end

--- Continent uiMapID the player is on (nil inside instances without a map).
function FarmList:PlayerContinent()
    local _, continent = playerLocation()
    return continent
end

--- Builds the list. Returns:
---   entries  = array of { jid, inst, mounts = { [mountID] = { ready = {diff...}, locked = {diff...}, resetAt } },
---                         readyCount, near = 0|1|2 }
---   counts   = { [state] = number of unique mounts in that state }
-- Continents to search for each EJ world-boss pseudo-instance's pins.
local WORLD_BOSS_ROOTS = {
    [322] = { 424 },               -- Pandaria
    [557] = { 572 },               -- Draenor
    [822] = { 619 },               -- Broken Isles
    [1028] = { 875, 876, 12, 13 }, -- Azeroth (BfA: Zandalar, Kul Tiras, Darkshore, Arathi)
    [1192] = { 1550 },             -- Shadowlands
    [1205] = { 1978 },             -- Dragon Isles
    [1278] = { 2274 },             -- Khaz Algar
}

--- World bosses have no dungeon entrance: take the boss's map pin from the
--- Encounter Journal once per session (the dataset cannot know it).
function FarmList:ResolveWorldBosses()
    if self.worldBossesResolved then return end
    local missing = false
    for _, inst in pairs(ns.Data.instances) do
        if inst.worldBoss and not inst.entrance then
            inst.entrance = ns.Navigation:FindEncounterOnMaps(inst.encounter, WORLD_BOSS_ROOTS[inst.ejInstance] or {})
            if inst.entrance then
                if ns.Planner then ns.Planner:InvalidateRoute() end -- route now knows where it is
            else
                missing = true
            end
        end
    end
    -- Retry next time if the journal was not ready yet.
    self.worldBossesResolved = not missing or (self.resolveTries or 0) >= 3
    self.resolveTries = (self.resolveTries or 0) + 1
end

function FarmList:Build()
    self:ResolveWorldBosses()
    local S = ns.Eligibility.STATES
    local byInstance, counts, mountStates = {}, {}, {}
    for _, src in ipairs(ns.Data.sources) do
        for _, d in ipairs(src.difficulties) do
            local state, reason, resetAt = ns.Eligibility:Evaluate(src, d)
            mountStates[state] = mountStates[state] or {}
            mountStates[state][src.mountID] = true
            if state == S.READY or state == S.LOCKED_OUT or state == S.VERIFY then
                local jid = src.journalInstanceID
                local e = byInstance[jid]
                if not e then
                    e = { jid = jid, inst = ns.Data.instances[jid], mounts = {}, readyCount = 0 }
                    byInstance[jid] = e
                end
                local m = e.mounts[src.mountID]
                if not m then
                    m = { ready = {}, locked = {}, verify = {}, source = src }
                    e.mounts[src.mountID] = m
                end
                if state == S.READY then
                    table.insert(m.ready, d)
                elseif state == S.LOCKED_OUT then
                    table.insert(m.locked, d)
                    m.resetAt = math.min(m.resetAt or resetAt, resetAt)
                else
                    table.insert(m.verify, { difficulty = d, reason = reason })
                end
            end
        end
    end

    local ancestors, continent = playerLocation()
    local entries = {}
    for _, e in pairs(byInstance) do
        for _, m in pairs(e.mounts) do
            if #m.ready > 0 then e.readyCount = e.readyCount + 1 end
        end
        e.hidden = FarmList:IsHidden(e.jid)
        local ent = e.inst.entrance
        e.near = (ent and ancestors[ent.uiMapID] and 2) or (ent and ent.continent == continent and 1) or 0
        entries[#entries + 1] = e
    end
    table.sort(entries, function(a, b)
        if (a.readyCount > 0) ~= (b.readyCount > 0) then return a.readyCount > 0 end
        if a.near ~= b.near then return a.near > b.near end
        if a.readyCount ~= b.readyCount then return a.readyCount > b.readyCount end
        if a.inst.tier ~= b.inst.tier then return a.inst.tier < b.inst.tier end
        return a.jid < b.jid
    end)
    -- counts = unique mounts per state (a mount can have several sources)
    for state, set in pairs(mountStates) do
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        counts[state] = n
    end
    self.entries, self.counts = entries, counts
    return entries, counts
end

--- Unique-mount totals for the UI (Home tiles, sidebar badge, farm list).
--- ready   = farmable now in a visible (not hidden) instance
--- locked  = locked out everywhere it is listed (never also ready)
--- verify  = needs verification (neither ready nor locked)
--- instances / hidden = instances with something ready, visible / hidden
function FarmList:Summarize(entries)
    local ready, locked, verify = {}, {}, {}
    local instances, hidden = 0, 0
    for _, e in ipairs(entries) do
        if e.readyCount > 0 then
            if e.hidden then
                hidden = hidden + 1
            else
                instances = instances + 1
                for id, m in pairs(e.mounts) do
                    if #m.ready > 0 then ready[id] = true end
                end
            end
        end
        for id, m in pairs(e.mounts) do
            if #m.ready == 0 then
                if #m.locked > 0 then
                    locked[id] = true
                elseif #m.verify > 0 then
                    verify[id] = true
                end
            end
        end
    end
    local function count(set, exclude1, exclude2)
        local n = 0
        for id in pairs(set) do
            if not (exclude1 and exclude1[id]) and not (exclude2 and exclude2[id]) then n = n + 1 end
        end
        return n
    end
    return {
        ready = count(ready),
        locked = count(locked, ready),
        verify = count(verify, ready, locked),
        instances = instances,
        hidden = hidden,
    }
end

-- Hide until reset (persists across reloads and characters; docs/03 §5).
local function hiddenTable()
    return ns.Storage.db.farmList.hidden
end

function FarmList:IsHidden(jid)
    local untilTime = hiddenTable()[jid]
    if not untilTime then return false end
    if untilTime > time() then return true end
    hiddenTable()[jid] = nil -- expired
    return false
end

function FarmList:Hide(jid, isRaid)
    local secs
    if isRaid then
        secs = C_DateAndTime.GetSecondsUntilWeeklyReset()
    else
        secs = (C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset())
            or GetQuestResetTime()
    end
    hiddenTable()[jid] = time() + (secs or 86400)
end

function FarmList:UnhideAll()
    wipe(hiddenTable())
end

-- World bosses use negative keys: -journalEncounterID (see build_dataset.py).
function FarmList:InstanceName(jid)
    if jid < 0 then return (EJ_GetEncounterInfo(-jid)) or ("#" .. jid) end
    return (EJ_GetInstanceInfo(jid)) or ("#" .. jid)
end

--- Encounter Journal tile artwork for an instance (texture fileID), or nil.
--- World bosses use their continent's journal art.
function FarmList:InstanceArt(jid)
    if jid < 0 then
        local inst = ns.Data.instances[jid]
        jid = inst and inst.ejInstance
        if not jid then return nil end
    end
    local _, _, _, buttonImage = EJ_GetInstanceInfo(jid)
    return buttonImage
end

--- Every boss name of an instance from the Encounter Journal (all bosses,
--- not only those with mounts).
function FarmList:EncounterNames(jid)
    local out = {}
    if jid < 0 or not EJ_GetEncounterInfoByIndex then return out end
    for i = 1, 40 do
        local name = EJ_GetEncounterInfoByIndex(i, jid)
        if not name then break end
        out[#out + 1] = name
    end
    return out
end

--- "Raid" / "Dungeon" / "World boss".
function FarmList:TypeName(inst)
    local L = ns.L
    if inst.worldBoss then return L["TYPE_WORLD_BOSS"] end
    return inst.isRaid and L["TYPE_RAID"] or L["TYPE_DUNGEON"]
end

--- Encounter Journal tiers (1 = Classic ... newest expansion).
function FarmList:NumTiers()
    return (EJ_GetNumTiers and EJ_GetNumTiers()) or 12
end

function FarmList:TierName(tier)
    return (EJ_GetTierInfo(tier)) or ("#" .. tier)
end

function FarmList:BossName(src)
    return (src and src.journalEncounterID and EJ_GetEncounterInfo(src.journalEncounterID)) or "?"
end

-- Compact, language-neutral difficulty labels for lists.
local SHORT = {
    [1] = "N", [2] = "H", [23] = "M",
    [3] = "10N", [4] = "25N", [5] = "10H", [6] = "25H", [9] = "40",
    [14] = "N", [15] = "H", [16] = "M", [7] = "LFR", [17] = "LFR",
}

function FarmList:DifficultyName(d)
    if d == 0 then return ns.L["DIFF_WEEKLY"] end -- world boss: one weekly kill
    return SHORT[d] or (GetDifficultyInfo(d)) or tostring(d)
end
