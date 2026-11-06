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

--- Seconds until the daily and weekly resets (nil when the client cannot tell).
function Lockouts:GetResetTimes()
    local daily = (C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset())
        or GetQuestResetTime()
    local weekly = C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    return daily, weekly
end

-- Clock display that matches the minimap clock: realm time unless the player
-- chose local time, and 12h (AM/PM) unless they chose 24h ("military") time.
-- os-style date() alone uses the Windows time zone, which can differ from both.
local WEEKDAYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" }

local function realmOffset()
    if GetCVar("timeMgrUseLocalTime") == "1" or not C_DateAndTime.GetCurrentCalendarTime then return 0 end
    local c = C_DateAndTime.GetCurrentCalendarTime()
    if not c then return 0 end
    local realmNow = time({ year = c.year, month = c.month, day = c.monthDay, hour = c.hour, min = c.minute, sec = 0 })
    -- Round to whole quarter hours: the calendar has no seconds.
    return math.floor((realmNow - time()) / 900 + 0.5) * 900
end

--- Returns weekday name and "16:00" / "4:00 PM" for an epoch time, as the minimap clock shows it.
function Lockouts:FormatClock(epoch)
    local t = epoch + realmOffset()
    local day = _G["WEEKDAY_" .. WEEKDAYS[tonumber(date("%w", t)) + 1]] or date("%A", t)
    local clock
    if GetCVar("timeMgrUseMilitaryTime") == "1" then
        clock = date("%H:%M", t)
    else
        local h = tonumber(date("%H", t))
        clock = ("%d:%s %s"):format((h % 12 == 0) and 12 or (h % 12), date("%M", t),
            h < 12 and (TIMEMANAGER_AM or "AM") or (TIMEMANAGER_PM or "PM"))
    end
    return day, clock
end

--- All records for an instance map (any difficulty).
function Lockouts:ForMap(instanceMapID)
    return self.byMap[instanceMapID] or {}
end
