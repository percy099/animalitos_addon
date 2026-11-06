-- Adapter over instance difficulty: which one a step needs, whether it is
-- already set, and setting it from a button (solo or as group leader, and
-- only outside the instance: the game does not allow it inside).
-- Legacy raids pick size and mode apart: raid difficulty Normal/Heroic
-- (14/15) plus legacy size 10/25 (3/4).
local _, ns = ...

local D = {}
ns.Difficulty = D

local LEGACY = { [3] = { size = 3, heroic = false }, [4] = { size = 4, heroic = false },
                 [5] = { size = 3, heroic = true },  [6] = { size = 4, heroic = true } }
local DUNGEON = { [1] = true, [2] = true, [23] = true }
local FLEX = { [14] = true, [15] = true, [16] = true }

--- Long client name ("25 Player (Heroic)").
function D:Name(d)
    return (GetDifficultyInfo and GetDifficultyInfo(d)) or ns.FarmList:DifficultyName(d)
end

--- Difficulty that drops the most Ready mounts of a farm entry (ties: the
--- higher one, usually the one with the mount); nil when nothing is Ready
--- or the step has no difficulty to choose (world bosses).
function D:Pick(e)
    local votes = {}
    for _, m in pairs(e and e.mounts or {}) do
        for _, d in ipairs(m.ready) do
            if d ~= 0 then votes[d] = (votes[d] or 0) + 1 end
        end
    end
    local best
    for d, n in pairs(votes) do
        if not best or n > votes[best] or (n == votes[best] and d > best) then best = d end
    end
    return best
end

--- Is a Ready mount of the entry dropped on difficulty d?
function D:Drops(e, d)
    for _, m in pairs(e and e.mounts or {}) do
        for _, rd in ipairs(m.ready) do
            if rd == d then return true end
        end
    end
    return false
end

--- Inside this entry's instance: its current difficultyID; else nil.
function D:Inside(e)
    local _, instanceType, difficultyID, _, _, _, _, instanceMapID = GetInstanceInfo()
    if instanceType == "none" or not e or not e.inst or instanceMapID ~= e.inst.mapID then return nil end
    return difficultyID
end

--- Is the selected (outside) difficulty already d?
function D:IsSet(d)
    if DUNGEON[d] then return GetDungeonDifficultyID() == d end
    if FLEX[d] then return GetRaidDifficultyID() == d end
    local l = LEGACY[d]
    if l then
        local size = GetLegacyRaidDifficultyID and GetLegacyRaidDifficultyID()
        size = (size == 5 and 3) or (size == 6 and 4) or size -- some clients report the heroic id
        return size == l.size and GetRaidDifficultyID() == (l.heroic and 15 or 14)
    end
    return false
end

--- Why the button cannot be used now, or nil.
function D:Blocked()
    if InCombatLockdown() then return "combat" end
    if IsInInstance() then return "inside" end
    if IsInGroup() and not UnitIsGroupLeader("player") then return "leader" end
    return nil
end

--- Sets difficulty d (true if it was sent).
function D:Set(d)
    if self:Blocked() then return false end
    if DUNGEON[d] then
        SetDungeonDifficultyID(d)
    elseif FLEX[d] then
        SetRaidDifficultyID(d)
    elseif LEGACY[d] then
        SetRaidDifficultyID(LEGACY[d].heroic and 15 or 14)
        if SetLegacyRaidDifficultyID then SetLegacyRaidDifficultyID(LEGACY[d].size) end
    else
        return false
    end
    return true
end

--- Can this difficulty be set from a button at all (not LFR, not 40, ...)?
function D:Settable(d)
    return DUNGEON[d] or FLEX[d] or LEGACY[d] and true or false
end
