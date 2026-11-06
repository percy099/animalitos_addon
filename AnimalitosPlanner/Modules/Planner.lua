-- Planner: a step-by-step route through every instance with a mount this
-- account is missing, in the spirit of SimpleArmory's planner.
--
-- The order is STATIC on purpose: it is computed once from the whole dataset
-- (fixed continent order per faction, then a fixed geographic walk inside
-- each continent from a fixed hub) and never from the player's position.
-- Steps that are done get ticked or hidden; the rest keep their place, so
-- following the route (e.g. going to Stormwind for portals) never reshuffles it.
local _, ns = ...

local Planner = {}
ns.Planner = Planner

-- Continent uiMapIDs in route order. Unknown continents go last (by ID).
local ORDER = {
    Alliance = { 13, 948, 12, 101, 113, 424, 572, 619, 905, 876, 875, 1550, 1978, 2274, 2537 },
    Horde    = { 12, 948, 13, 101, 113, 424, 572, 619, 905, 875, 876, 1550, 1978, 2274, 2537 },
}

-- Where the walk inside a continent starts: the capital for the first
-- continent, otherwise the usual arrival hub (portal / flight hub).
-- uiMapIDs; the point is the map's center. If the client cannot place it,
-- the walk starts from the westmost entrance (still deterministic).
local HUBS = {
    Alliance = { [13] = 84,  [12] = 71 },  -- Stormwind; Tanaris (Caverns of Time)
    Horde    = { [12] = 85,  [13] = 18 },  -- Orgrimmar; Tirisfal Glades
    any = {
        [101] = 100,   -- Hellfire Peninsula
        [113] = 125,   -- Dalaran (Northrend)
        [424] = 390,   -- Vale of Eternal Blossoms
        [572] = 588,   -- Ashran
        [619] = 627,   -- Dalaran (Broken Isles)
        [876] = 1161,  -- Boralus
        [875] = 1165,  -- Dazar'alor
        [1550] = 1670, -- Oribos
        [1978] = 2112, -- Valdrakken
        [2274] = 2339, -- Dornogal
    },
}
local CAPITAL = { Alliance = 84, Horde = 85 }

local function faction()
    local f = UnitFactionGroup("player")
    return (f == "Horde") and "Horde" or "Alliance"
end

-- Static route ----------------------------------------------------------------
local cachedRoute, cachedFaction

local function entrancePos(inst)
    local e = inst.entrance
    local _, x, y = ns.Navigation:WorldPos(e.uiMapID, e.x, e.y)
    return x, y
end

--- Every dataset instance with an entrance, in route order (journalInstanceIDs),
--- followed by those without an entrance. Computed once per faction.
function Planner:Route()
    local fac = faction()
    if cachedRoute and cachedFaction == fac then return cachedRoute end

    local byContinent, noEntrance = {}, {}
    for jid, inst in pairs(ns.Data.instances) do
        local e = inst.entrance
        if e and e.continent then
            byContinent[e.continent] = byContinent[e.continent] or {}
            table.insert(byContinent[e.continent], jid)
        else
            noEntrance[#noEntrance + 1] = jid
        end
    end

    local continents, seen = {}, {}
    for _, c in ipairs(ORDER[fac]) do
        if byContinent[c] then continents[#continents + 1] = c; seen[c] = true end
    end
    local rest = {}
    for c in pairs(byContinent) do if not seen[c] then rest[#rest + 1] = c end end
    table.sort(rest)
    for _, c in ipairs(rest) do continents[#continents + 1] = c end

    local route = {}
    for _, c in ipairs(continents) do
        local jids = byContinent[c]
        table.sort(jids) -- deterministic input
        local pts = {}
        for _, jid in ipairs(jids) do
            local x, y = entrancePos(ns.Data.instances[jid])
            pts[jid] = x and { x, y } or nil
        end
        -- Start point: hub map center, else the westmost entrance.
        local hubMap = (HUBS[fac][c]) or HUBS.any[c]
        local cx, cy
        if hubMap then
            local _, hx, hy = ns.Navigation:WorldPos(hubMap, 0.5, 0.5)
            cx, cy = hx, hy
        end
        local left = {}
        for _, jid in ipairs(jids) do left[#left + 1] = jid end
        if not cx then
            -- No hub: begin at the highest world Y (westmost: WoW's Y grows westward).
            local best
            for _, jid in ipairs(left) do
                local p = pts[jid]
                if p and (not best or p[2] > pts[best][2]) then best = jid end
            end
            if best then cx, cy = pts[best][1], pts[best][2] end
        end
        -- Nearest neighbour walk (ties by jid). Points the client cannot
        -- place keep their jid order at the end of the continent.
        while #left > 0 do
            local bi, bd
            for i, jid in ipairs(left) do
                local p = pts[jid]
                local d = (p and cx) and ((p[1] - cx) ^ 2 + (p[2] - cy) ^ 2) or math.huge
                if not bd or d < bd then bi, bd = i, d end
            end
            local jid = table.remove(left, bi)
            route[#route + 1] = jid
            if pts[jid] then cx, cy = pts[jid][1], pts[jid][2] end
        end
    end
    table.sort(noEntrance)
    for _, jid in ipairs(noEntrance) do route[#route + 1] = jid end

    cachedRoute, cachedFaction = route, fac
    return route
end

-- Manual "done" marks (per character, until the next reset) ----------------------
local function doneTable()
    local key = ns:GetCharacterKey()
    local cd = ns.Storage.db.characterData
    cd[key] = cd[key] or {}
    cd[key].plannerDone = cd[key].plannerDone or {}
    return cd[key].plannerDone
end

function Planner:IsManuallyDone(jid)
    local untilTime = doneTable()[jid]
    if not untilTime then return false end
    if untilTime > time() then return true end
    doneTable()[jid] = nil
    return false
end

function Planner:SetManuallyDone(jid, isRaid, done)
    if not done then
        doneTable()[jid] = nil
        return
    end
    local secs
    if isRaid then
        secs = C_DateAndTime.GetSecondsUntilWeeklyReset()
    else
        secs = (C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset())
            or GetQuestResetTime()
    end
    doneTable()[jid] = time() + (secs or 86400)
end

--- which = "all" | "raids" | "dungeons"
function Planner:ResetMarks(which)
    local t = doneTable()
    for jid in pairs(t) do
        local inst = ns.Data.instances[jid]
        local isRaid = inst and inst.isRaid
        if which == "all" or (which == "raids" and isRaid) or (which == "dungeons" and not isRaid) then
            t[jid] = nil
        end
    end
end

-- Steps -------------------------------------------------------------------------
local function capitalName(fac)
    local info = C_Map.GetMapInfo(CAPITAL[fac])
    return info and info.name or fac
end

--- Builds the visible steps from FarmList entries (account-missing mounts).
--- Returns steps, summary:
---   step = { kind = "start", text } | { kind = "travel", text }
---        | { kind = "run", jid, inst, e, number, done, auto }
---   summary = { total, done, nextJid }
function Planner:Build(entries, hideCompleted)
    local byJid = {}
    for _, e in ipairs(entries or {}) do byJid[e.jid] = e end

    local runs = {}
    for _, jid in ipairs(self:Route()) do
        local e = byJid[jid]
        if e then
            local anyReady, anyLocked = false, false
            for _, m in pairs(e.mounts) do
                if #m.ready > 0 then anyReady = true end
                if #m.locked > 0 then anyLocked = true end
            end
            -- Auto-done: nothing left to loot this reset and something was killed.
            -- Unknown (verify only) is never treated as done.
            local auto = ns.Lockouts.loaded and anyLocked and not anyReady
            local manual = self:IsManuallyDone(jid)
            runs[#runs + 1] = { kind = "run", jid = jid, inst = e.inst, e = e,
                done = auto or manual, auto = auto }
        end
    end

    local summary = { total = #runs, done = 0 }
    for i, r in ipairs(runs) do
        r.number = i
        if r.done then summary.done = summary.done + 1
        elseif not summary.nextJid and r.inst.entrance then summary.nextJid = r.jid end
    end

    local fac = faction()
    local steps = { { kind = "start", text = capitalName(fac) } }
    -- The route starts in the capital: Stormwind (Eastern Kingdoms) or Orgrimmar (Kalimdor).
    local lastContinent, lastZone = (fac == "Horde") and 12 or 13, CAPITAL[fac]
    for _, r in ipairs(runs) do
        if not (hideCompleted and r.done) then
            local ent = r.inst.entrance
            if ent then
                if ent.continent ~= lastContinent then
                    local info = C_Map.GetMapInfo(ent.continent)
                    local zone = C_Map.GetMapInfo(ent.uiMapID)
                    steps[#steps + 1] = { kind = "travel", text = ns.L["PLAN_TRAVEL_CONTINENT"]:format(
                        info and info.name or "?", zone and zone.name or "?") }
                elseif ent.uiMapID ~= lastZone then
                    local zone = C_Map.GetMapInfo(ent.uiMapID)
                    steps[#steps + 1] = { kind = "travel", text = ns.L["PLAN_TRAVEL_ZONE"]:format(zone and zone.name or "?") }
                end
                lastContinent, lastZone = ent.continent, ent.uiMapID
            end
            steps[#steps + 1] = r
        end
    end
    return steps, summary
end
