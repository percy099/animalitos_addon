-- Source-level eligibility for the active character (docs/03-funcional.md §3).
-- Each (source, difficulty) pair gets exactly one state. Unknown never
-- becomes Ready.
local _, ns = ...
local L = ns.L

local Eligibility = {}
ns.Eligibility = Eligibility

local S = {
    READY = "ready",
    LOCKED_OUT = "lockedOut",
    UNLOCK = "unlockRequired",
    UNAVAILABLE = "unavailable",
    VERIFY = "verificationRequired",
    COLLECTED = "collected",
    OUT_OF_SCOPE = "outOfScope",
}
Eligibility.STATES = S

-- Legacy 10/25-player raid difficulties (3 = 10N, 4 = 25N, 5 = 10H, 6 = 25H)
-- form ONE lockout: a boss killed in any of them is locked in all four.
-- Validated 2026-11-05: Ultraxion killed in Dragon Soul 25H stayed dead when
-- re-entering on 25 Normal; 10/25 sharing confirmed by the team.
-- Flex difficulties (14/15/16) and dungeons (1/2/23) keep separate lockouts.
local SHARED_LEGACY = { 3, 4, 5, 6 }
local SIZE_SIBLINGS = {}
for _, d in ipairs(SHARED_LEGACY) do
    SIZE_SIBLINGS[d] = {}
    for _, other in ipairs(SHARED_LEGACY) do
        if other ~= d then table.insert(SIZE_SIBLINGS[d], other) end
    end
end

local encounterNameCache = {}
local function encounterName(journalEncounterID)
    if not journalEncounterID then return nil end
    local cached = encounterNameCache[journalEncounterID]
    if cached == nil then
        cached = EJ_GetEncounterInfo(journalEncounterID) or false
        encounterNameCache[journalEncounterID] = cached
    end
    return cached or nil
end

--- Evaluate one source for one difficulty.
--- Returns state, reason (localized text), resetAt (epoch seconds or nil).
function Eligibility:Evaluate(src, difficultyID)
    local mount = ns.MountJournal:GetMount(src.mountID)
    if not mount then
        return S.VERIFY, L["REASON_NOT_IN_JOURNAL"]
    end
    if mount.isCollected then
        return S.COLLECTED, L["REASON_COLLECTED"]
    end
    if mount.shouldHideOnChar then
        return S.UNAVAILABLE, L["REASON_HIDDEN"]
    end

    local inst = ns.Data.instances[src.journalInstanceID]
    if not inst or not inst.legacy then
        return S.OUT_OF_SCOPE, L["REASON_OUT_OF_SCOPE"]
    end
    if inst.tier > (ns.Storage.db.settings.maxTier or 10) then
        return S.OUT_OF_SCOPE, L["REASON_TOO_RECENT"]
    end

    if not ns.Lockouts.loaded then
        return S.VERIFY, L["REASON_LOCKOUTS_LOADING"]
    end

    if inst.worldBoss then
        return self:EvaluateWorldBoss(src, inst)
    end

    -- Boss not in the Encounter Journal (Nightbane, Infinite Corruptor):
    -- its kill cannot be read, so it is never Ready.
    if src.hiddenBoss then
        return S.VERIFY, L["REASON_HIDDEN_BOSS_" .. src.hiddenBoss:gsub("^BOSS_", "")]
    end

    local boss = encounterName(src.journalEncounterID)
    local record = inst.mapID and ns.Lockouts:Get(inst.mapID, difficultyID)
    if record then
        if not boss then
            return S.VERIFY, L["REASON_BOSS_UNKNOWN"]
        end
        if record.killed[boss] then
            return S.LOCKED_OUT, L["REASON_KILLED"]:format(boss), record.resetAt
        end
    end

    for _, sibling in ipairs(SIZE_SIBLINGS[difficultyID] or {}) do
        local other = inst.mapID and ns.Lockouts:Get(inst.mapID, sibling)
        if other and boss and other.killed[boss] then
            return S.LOCKED_OUT, L["REASON_SHARED_SIZE"]:format(boss), other.resetAt
        end
    end

    return S.READY, record and L["REASON_BOSS_ALIVE"]:format(boss or "?") or L["REASON_NOT_SAVED"]
end

-- Names a world boss may be saved under: the encounter ("Salyis's Warband")
-- and each of its creatures ("Galleon").
local wbNamesCache = {}
local function worldBossNames(encounterID)
    local names = wbNamesCache[encounterID]
    if names then return names end
    names = {}
    local n = EJ_GetEncounterInfo(encounterID)
    if n then names[#names + 1] = n end
    if EJ_GetCreatureInfo then
        for i = 1, 9 do
            local _, creature = EJ_GetCreatureInfo(i, encounterID)
            if not creature then break end
            names[#names + 1] = creature
        end
    end
    if #names > 0 then wbNamesCache[encounterID] = names end
    return names
end

--- World boss: one weekly kill. Only "savedWorldBoss" models (validated to
--- show up in GetSavedWorldBossInfo) can be Ready; others need verification.
function Eligibility:EvaluateWorldBoss(src, inst)
    local boss = encounterName(src.journalEncounterID) or "?"
    local names = worldBossNames(src.journalEncounterID)
    local ids = { src.journalEncounterID }
    if src.dungeonEncounterID then ids[2] = src.dungeonEncounterID end
    -- Listed under Raid Info > World Bosses: killed, whatever the model.
    local resetAt = ns.Lockouts:WorldBossKilled(names, ids)
    if resetAt then
        return S.LOCKED_OUT, L["REASON_KILLED"]:format(boss), resetAt
    end

    if inst.lockoutModel == "worldQuest" then
        -- Rotating boss marked by its world quest (Kraulok).
        local state, at = ns.Lockouts:WorldQuestBoss(src.journalEncounterID, names,
            inst.entrance and inst.entrance.uiMapID)
        if state == "done" then
            return S.LOCKED_OUT, L["REASON_WQ_DONE"]:format(boss), at
        elseif state == "active" then
            return S.READY, L["REASON_WQ_ACTIVE"]:format(boss)
        elseif state == "inactive" then
            return S.UNAVAILABLE, L["REASON_WQ_ROTATION"]
        end
        return S.VERIFY, L["REASON_WQ_UNKNOWN"]
    end

    if inst.lockoutModel ~= "savedWorldBoss" then
        return S.VERIFY, L["REASON_WB_UNKNOWN"]
    end
    return S.READY, L["REASON_WB_ALIVE"]:format(boss)
end
