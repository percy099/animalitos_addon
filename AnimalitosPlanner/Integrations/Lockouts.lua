-- Adapter over the saved-instance APIs. Builds an index of the active
-- character's lockouts: [instanceMapID][difficultyID] = record.
--
-- Validated on 12.1.5 (probe 2026-11-05): GetSavedInstanceInfo returns 14
-- values; [3] = seconds until reset, [4] = difficultyID, [5] = locked,
-- [14] = instance map ID (same as EJ_GetInstanceInfo's mapID). Each encounter
-- from GetSavedInstanceEncounterInfo reports (name, fileDataID, isKilled, ...).
local _, ns = ...

local Lockouts = {}
ns.Lockouts = Lockouts

Lockouts.loaded = false   -- true after the first UPDATE_INSTANCE_INFO
Lockouts.byMap = {}

function Lockouts:Request()
    RequestRaidInfo()
end

function Lockouts:Refresh()
    local byMap, now = {}, time()
    for i = 1, GetNumSavedInstances() do
        local name, _, reset, difficultyID, locked, extended, _, isRaid, _, difficultyName,
              numEncounters, encounterProgress, _, instanceMapID = GetSavedInstanceInfo(i)
        -- Expired entries stay in the list with reset == 0 / locked == false.
        if instanceMapID and difficultyID and (locked or extended) and reset and reset > 0 then
            local record = {
                name = name,
                difficultyID = difficultyID,
                difficultyName = difficultyName,
                isRaid = isRaid,
                resetAt = now + reset,
                numEncounters = numEncounters,
                encounterProgress = encounterProgress,
                killed = {},   -- [encounterName] = true
            }
            for j = 1, numEncounters or 0 do
                local bossName, _, isKilled = GetSavedInstanceEncounterInfo(i, j)
                if bossName and isKilled then record.killed[bossName] = true end
            end
            byMap[instanceMapID] = byMap[instanceMapID] or {}
            byMap[instanceMapID][difficultyID] = record
        end
    end
    self.byMap = byMap
    self.loaded = true
    self.updatedAt = now
end

function Lockouts:Get(instanceMapID, difficultyID)
    local m = self.byMap[instanceMapID]
    return m and m[difficultyID]
end

--- All records for an instance map (any difficulty).
function Lockouts:ForMap(instanceMapID)
    return self.byMap[instanceMapID] or {}
end
