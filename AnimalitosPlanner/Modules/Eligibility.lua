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

-- Legacy 10/25-player difficulties. In Cataclysm/MoP raids these sizes may
-- share one lockout; not validated yet, so a kill on a sibling size makes the
-- other size "verification required" instead of Ready.
local SIZE_SIBLINGS = { [3] = { 4 }, [4] = { 3 }, [5] = { 6 }, [6] = { 5 } }

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
            return S.VERIFY, L["REASON_SHARED_SIZE"], other.resetAt
        end
    end

    return S.READY, record and L["REASON_BOSS_ALIVE"]:format(boss or "?") or L["REASON_NOT_SAVED"]
end
