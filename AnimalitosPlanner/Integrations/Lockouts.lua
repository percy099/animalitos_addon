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

    -- World bosses killed (looted) this week: Raid Info's "World Bosses".
    -- GetSavedWorldBossInfo(i) -> name, worldBossID, secondsUntilReset.
    local wb = { names = {}, ids = {} }
    if GetNumSavedWorldBosses and GetSavedWorldBossInfo then
        for i = 1, GetNumSavedWorldBosses() do
            local bossName, worldBossID, reset = GetSavedWorldBossInfo(i)
            if bossName and reset and reset > 0 then
                wb.names[bossName:lower()] = now + reset
                if worldBossID then wb.ids[worldBossID] = now + reset end
            end
        end
    end
    self.worldBosses = wb
    self.loaded = true
    self.updatedAt = now

    -- Signature of what matters (who is saved where, how far): returns true
    -- when it changed, so the window is redrawn only then. Other addons ask
    -- for raid info often and UPDATE_INSTANCE_INFO fires for each request.
    local sig = {}
    for mapID, diffs in pairs(byMap) do
        for d, r in pairs(diffs) do sig[#sig + 1] = ("%d:%d:%d"):format(mapID, d, r.encounterProgress or 0) end
    end
    for name in pairs(wb.names) do sig[#sig + 1] = name end
    table.sort(sig)
    local s = table.concat(sig, ",")
    local changed = s ~= self.signature
    self.signature = s
    return changed
end

function Lockouts:Get(instanceMapID, difficultyID)
    local m = self.byMap[instanceMapID]
    return m and m[difficultyID]
end

--- resetAt if any of the names / ids is a world boss killed this week, else nil.
function Lockouts:WorldBossKilled(names, ids)
    local wb = self.worldBosses
    if not wb then return nil end
    for _, n in ipairs(names) do
        local at = wb.names[n:lower()]
        if at then return at end
    end
    for _, id in ipairs(ids) do
        local at = wb.ids[id]
        if at then return at end
    end
    return nil
end

-- World-quest world bosses (Battle for Azeroth: Kraulok) -------------------
-- The boss is up when its epic world quest (named after it) is on the map;
-- completing it is the weekly kill. The quest ID is found by name on the
-- boss's map and remembered account-wide (AnimalitosPlannerDB.worldQuests),
-- because a completed world quest leaves the map.

local function questTitle(questID)
    local t = C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID and C_TaskQuest.GetQuestInfoByQuestID(questID)
    if not t and C_QuestLog.GetTitleForQuestID then t = C_QuestLog.GetTitleForQuestID(questID) end
    return t
end

local function questsOnMap(uiMapID)
    local fn = (C_TaskQuest and (C_TaskQuest.GetQuestsOnMap or C_TaskQuest.GetQuestsForPlayerByMapID))
    if not fn then return {} end
    local ok, list = pcall(fn, uiMapID)
    return ok and list or {}
end

--- Looks for the boss's world quest on uiMapID; returns its questID or nil.
local function findWorldQuest(names, uiMapID)
    local wanted = {}
    for _, n in ipairs(names) do wanted[n:lower()] = true end
    for _, info in ipairs(questsOnMap(uiMapID)) do
        local id = info.questID or info.questId
        local title = id and questTitle(id)
        if title and wanted[title:lower()] then return id end
    end
    return nil
end

--- State of a world-quest world boss: "done" (+ resetAt), "active",
--- "inactive" (not in this week's rotation) or nil (unknown: never seen).
function Lockouts:WorldQuestBoss(encounterID, names, uiMapID)
    local db = ns.Storage.db
    db.worldQuests = db.worldQuests or {}
    local questID = db.worldQuests[encounterID]
    if not questID and uiMapID then
        questID = findWorldQuest(names, uiMapID)
        if questID then db.worldQuests[encounterID] = questID end
    end
    if not questID then return nil end

    if C_QuestLog.IsQuestFlaggedCompleted(questID) then
        local _, weekly = self:GetResetTimes()
        return "done", weekly and (time() + weekly) or nil
    end
    local active
    if C_TaskQuest and C_TaskQuest.IsActive then
        active = C_TaskQuest.IsActive(questID)
    else
        active = uiMapID and findWorldQuest(names, uiMapID) == questID
    end
    return active and "active" or "inactive"
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
