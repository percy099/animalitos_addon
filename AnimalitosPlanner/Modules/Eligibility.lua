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
    if not inst or inst.worldBoss or not inst.legacy then
        return S.OUT_OF_SCOPE, L["REASON_OUT_OF_SCOPE"]
    end
    if inst.tier > (ns.Storage.db.settings.maxTier or 10) then
        return S.OUT_OF_SCOPE, L["REASON_TOO_RECENT"]
    end

    if not ns.Lockouts.loaded then
        return S.VERIFY, L["REASON_LOCKOUTS_LOADING"]
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
