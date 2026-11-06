-- Adapter over the Dungeon Finder for world event bosses (Headless Horseman,
-- Coren Direbrew, Crown Chemical Co.). Their queue is listed by the client
-- only while the event is on; "done today" comes from the queue's rewards.
local _, ns = ...

local H = {}
ns.Holidays = H

--- Asks the server for Dungeon Finder data (answer: LFG_UPDATE_RANDOM_INFO).
function H:Request()
    if RequestLFDPlayerLockInfo then RequestLFDPlayerLockInfo() end
end

--- "active", "inactive", or nil when the client has no Dungeon Finder data
--- yet (unknown is never Ready).
function H:Status(lfgID)
    if self.test then return "active" end -- /aplan events test (session only)
    if not (GetNumRandomDungeons and GetLFGRandomDungeonInfo) then return nil end
    local n = GetNumRandomDungeons()
    if not n or n == 0 then return nil end
    for i = 1, n do
        if GetLFGRandomDungeonInfo(i) == lfgID then return "active" end
    end
    if IsLFGDungeonJoinable and IsLFGDungeonJoinable(lfgID) then return "active" end
    return "inactive"
end

--- True when this character already got today's reward from the queue.
function H:DoneToday(lfgID)
    if not GetLFGDungeonRewards then return nil end
    local done = GetLFGDungeonRewards(lfgID)
    return done and true or false
end

--- Localized queue name ("The Headless Horseman"), or nil.
function H:Name(lfgID)
    if not GetLFGDungeonInfo then return nil end
    local info = GetLFGDungeonInfo(lfgID)
    if type(info) == "table" then return info.name end
    return info
end

--- Opens the Dungeon Finder on that queue (the player presses Find Group).
function H:OpenQueue(lfgID)
    if InCombatLockdown() then return false end
    if not PVEFrame then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then pcall(load, "Blizzard_GroupFinder") end
    end
    if PVEFrame_ShowFrame and LFDParentFrame then
        PVEFrame_ShowFrame("GroupFinderFrame", LFDParentFrame)
    elseif ToggleLFDParentFrame then
        ToggleLFDParentFrame()
    end
    if LFDQueueFrame_SetType then pcall(LFDQueueFrame_SetType, lfgID) end
    return true
end

--- /aplan events: what the client reports (to validate in game).
function H:Debug()
    local n = GetNumRandomDungeons and GetNumRandomDungeons() or 0
    local list = {}
    for i = 1, n do
        local id, name = GetLFGRandomDungeonInfo(i)
        list[#list + 1] = ("%s(%s)"):format(tostring(name), tostring(id))
    end
    print(("  queues listed (%d): %s"):format(n, table.concat(list, ", ")))
    for _, h in ipairs(ns.Data.holidays or {}) do
        print(("  %s (%d): %s, done today %s"):format(tostring(self:Name(h.lfgDungeonID)), h.lfgDungeonID,
            tostring(self:Status(h.lfgDungeonID)), tostring(self:DoneToday(h.lfgDungeonID))))
    end
end
