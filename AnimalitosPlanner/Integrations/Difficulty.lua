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

-- Raid skips ------------------------------------------------------------------
-- Curated (overrides.json raidSkips -> ns.Data.skips[jid]): the boss a skip
-- jumps to and its quest per difficulty. A higher difficulty's quest also
-- unlocks the lower ones. Skips are warband-wide once unlocked, so a quest
-- done on any character counts when the client can tell.
local RANK = { [14] = 1, [15] = 2, [16] = 3 }

local function questDone(questID)
    local Q = C_QuestLog
    if Q.IsQuestFlaggedCompletedOnAccount and Q.IsQuestFlaggedCompletedOnAccount(questID) then return true end
    return Q.IsQuestFlaggedCompleted(questID) and true or false
end

local function skipBoss(s)
    return (EJ_GetEncounterInfo and EJ_GetEncounterInfo(s.encounter)) or s.boss
end

--- Skips of a raid for difficulty d: { { name, unlocked } }, or nil.
function D:Skips(jid, d)
    local list = ns.Data.skips and ns.Data.skips[jid]
    if not list then return nil end
    local need = RANK[d] or 1
    local out = {}
    for _, s in ipairs(list) do
        local unlocked = false
        for _, pair in ipairs(s.quests) do
            if (RANK[pair[1]] or 0) >= need and questDone(pair[2]) then
                unlocked = true
                break
            end
        end
        out[#out + 1] = { name = skipBoss(s), unlocked = unlocked }
    end
    return out
end

--- One line for the step: "Skip to Argus the Unmaker (check)", colored.
function D:SkipNote(jid, d)
    local skips = self:Skips(jid, d)
    if not skips then return nil end
    local parts = {}
    for _, s in ipairs(skips) do
        local icon = s.unlocked and "|A:common-icon-checkmark:11:11|a" or "|A:common-icon-redx:11:11|a"
        parts[#parts + 1] = ("%s%s|r %s"):format(s.unlocked and "|cff8dd3a8" or "|cffe0a040",
            ns.L["SKIP_TO"]:format(s.name), icon)
    end
    return table.concat(parts, "  ")
end

--- /aplan skips: each curated quest with its title in this client and
--- whether it is done (to confirm the IDs).
function D:DebugSkips()
    for jid, list in pairs(ns.Data.skips or {}) do
        print(("  %s:"):format(ns.FarmList:InstanceName(jid)))
        for _, s in ipairs(list) do
            for _, pair in ipairs(s.quests) do
                local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(pair[2])
                if not title and C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(pair[2]) end
                print(("    %s %s: %s (%s) done=%s"):format(skipBoss(s), ns.FarmList:DifficultyName(pair[1]),
                    tostring(pair[2]), tostring(title or "not loaded, run again"), tostring(questDone(pair[2]))))
            end
        end
    end
end