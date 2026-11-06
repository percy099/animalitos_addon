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
local HOME_CONTINENT = { Alliance = 13, Horde = 12 }

-- Travel hints (hand-written; assumes the hearthstone is set to the
-- capital, like SimpleArmory). Values are the uiMapID the portal lands
-- in; names come from the client, so they are localized.
-- Zone portals: Cataclysm earthshrines in both capitals.
local ZONE_PORTALS = {
    [207] = 207, -- Deepholm (The Stonecore)
    [249] = 249, -- Uldum (Vortex Pinnacle, Throne of the Four Winds, Lost City)
    [198] = 198, -- Mount Hyjal
    [241] = 241, -- Twilight Highlands (Bastion of Twilight, Grim Batol)
    [244] = 244, -- Tol Barad (Baradin Hold)
    [204] = 203, -- Abyssal Depths (Throne of the Tides) -> Vashj'ir portal
}
-- Continent portals from the capital's portal room (verified in game for
-- Stormwind); a missing entry falls back to "Travel to ...".
local CONTINENT_PORTALS = {
    Alliance = {
        [12] = 71,     -- Caverns of Time (Tanaris)
        [948] = 207,   -- Deepholm
        [101] = 111,   -- Shattrath
        [113] = 125,   -- Dalaran (Northrend)
        [424] = 371,   -- Jade Forest
        [572] = 622,   -- Stormshield (Ashran)
        [619] = 630,   -- Azsuna
        [876] = 1161,  -- Boralus
        [1550] = 1670, -- Oribos
        [1978] = 2112, -- Valdrakken
        [2274] = 2339, -- Dornogal
        [2537] = 2393, -- Silvermoon City
    },
    Horde = {
        [948] = 207,   -- Deepholm
        [101] = 111,   -- Shattrath
        [113] = 125,   -- Dalaran (Northrend)
        [424] = 371,   -- Jade Forest
        [572] = 624,   -- Warspear (Ashran)
        [619] = 630,   -- Azsuna
        [875] = 862,   -- Zuldazar
        [1550] = 1670, -- Oribos
        [1978] = 2112, -- Valdrakken
        [2274] = 2339, -- Dornogal
        [2537] = 2393, -- Silvermoon City
    },
}

-- Mage teleports by destination continent: { landing uiMapID, spellID }.
-- Used when the player is a mage (spell known) or a mage is in the group
-- (assumed to have the matching portal). Zone entries win over continents.
local MAGE = {
    Alliance = {
        capital = { 84, 3561 },          -- Teleport: Stormwind
        zone = { [244] = { 244, 88342 } }, -- Tol Barad
        [12] = { 70, 49359 },            -- Theramore (Dustwallow Marsh)
        [101] = { 111, 33690 },          -- Shattrath
        [113] = { 125, 53140 },          -- Dalaran (Northrend)
        [424] = { 390, 132621 },         -- Vale of Eternal Blossoms
        [572] = { 622, 176248 },         -- Stormshield
        [619] = { 627, 224869 },         -- Dalaran (Broken Isles)
        [876] = { 1161, 281403 },        -- Boralus
        [1550] = { 1670, 344587 },       -- Oribos
        [1978] = { 2112, 395277 },       -- Valdrakken
        [2274] = { 2339, 446540 },       -- Dornogal
    },
    Horde = {
        capital = { 85, 3567 },          -- Teleport: Orgrimmar
        zone = { [244] = { 244, 88344 } }, -- Tol Barad
        [13] = { 51, 49358 },            -- Stonard (Swamp of Sorrows)
        [101] = { 111, 35715 },          -- Shattrath
        [113] = { 125, 53140 },          -- Dalaran (Northrend)
        [424] = { 390, 132627 },         -- Vale of Eternal Blossoms
        [572] = { 624, 176242 },         -- Warspear
        [619] = { 627, 224869 },         -- Dalaran (Broken Isles)
        [875] = { 1165, 281404 },        -- Dazar'alor
        [1550] = { 1670, 344587 },       -- Oribos
        [1978] = { 2112, 395277 },       -- Valdrakken
        [2274] = { 2339, 446540 },       -- Dornogal
    },
}

-- Rough minutes for the "time left" estimate (shown with "≈").
local MINUTES = { raid = 15, dungeon = 10, travel = 4 }

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
    local here = { continent = HOME_CONTINENT[fac], zone = CAPITAL[fac] }
    local travelMinutes = 0
    local mage = self:MageContext()
    summary.mage = mage
    for _, r in ipairs(runs) do
        if not (hideCompleted and r.done) then
            local ent = r.inst.entrance
            if ent then
                local texts = self:TravelTexts(fac, here, ent, mage)
                for _, text in ipairs(texts) do
                    steps[#steps + 1] = { kind = "travel", text = text }
                end
                if not r.done then travelMinutes = travelMinutes + #texts * MINUTES.travel end
                here.continent, here.zone = ent.continent, ent.uiMapID
            end
            steps[#steps + 1] = r
        end
    end

    -- Rough time left: pending runs plus the travel in front of them.
    local m = travelMinutes
    for _, r in ipairs(runs) do
        if not r.done then m = m + (r.inst.isRaid and MINUTES.raid or MINUTES.dungeon) end
    end
    summary.minutes = m
    return steps, summary
end

local function mapName(uiMapID)
    local info = uiMapID and C_Map.GetMapInfo(uiMapID)
    return info and info.name or "?"
end

--- Who can open mage teleports/portals right now: { self = bool, group = name|nil }.
function Planner:MageContext()
    local _, class = UnitClass("player")
    return { self = class == "MAGE", group = ns.Navigation:GroupMage() }
end

-- Text for a mage hop to dest = { uiMapID, spellID }, or nil if nobody can do it.
local function mageHop(mage, dest)
    if not (mage and dest) then return nil end
    if mage.self and ns.Navigation:KnowsSpell(dest[2]) then
        return ns.Navigation:SpellName(dest[2]) or ns.L["PLAN_TELEPORT"]:format(mapName(dest[1]))
    end
    if mage.group then return ns.L["PLAN_ASK_PORTAL"]:format(mage.group, mapName(dest[1])) end
    return nil
end

--- Travel step texts from `here` ({continent, zone}) to an entrance.
--- Mage teleports / group portals first, then hand-written capital portals;
--- anything unknown falls back to "Travel to ...".
function Planner:TravelTexts(fac, here, ent, mage)
    local L = ns.L
    local out = {}
    if ent.continent == here.continent and ent.uiMapID == here.zone then return out end

    local inCapital = here.zone == CAPITAL[fac]
    local capital = mapName(CAPITAL[fac])
    local zonePortal = ZONE_PORTALS[ent.uiMapID]
    local contPortal = CONTINENT_PORTALS[fac][ent.continent]
    local fly = L["PLAN_FLY"]:format(mapName(ent.uiMapID))

    -- A mage teleport straight into the zone (Tol Barad).
    local zoneDest = MAGE[fac].zone[ent.uiMapID]
    local hop = mageHop(mage, zoneDest)
    if hop then
        out[1] = hop
        return out
    end

    -- Same continent and no capital portal that helps: just fly.
    if ent.continent == here.continent and not (inCapital and zonePortal) then
        out[1] = fly
        return out
    end

    -- Another continent with a mage city (no zone portal is closer). Only
    -- when it lands in the instance's zone, at the capital portal's own
    -- destination, or there is no capital portal: Theramore + flying to
    -- Tanaris is worse than Stormwind + the Caverns of Time portal.
    local dest = MAGE[fac][ent.continent]
    local useful = dest and (dest[1] == ent.uiMapID or not contPortal or dest[1] == contPortal)
    if ent.continent ~= here.continent and not zonePortal and useful then
        hop = mageHop(mage, dest)
        if hop then
            out[1] = hop
            if dest[1] ~= ent.uiMapID then out[2] = fly end
            return out
        end
    end

    -- Back to the capital: mage teleport / portal, else the hearthstone.
    local home = mageHop(mage, MAGE[fac].capital) or L["PLAN_HEARTH"]:format(capital)

    local landing
    if zonePortal then
        landing = zonePortal
    elseif contPortal then
        landing = contPortal
    elseif ent.continent == HOME_CONTINENT[fac] then
        landing = CAPITAL[fac] -- the hearthstone itself is the "portal"
    end

    if not landing then
        out[1] = L["PLAN_TRAVEL_CONTINENT"]:format(mapName(ent.continent), mapName(ent.uiMapID))
        return out
    end

    if landing == CAPITAL[fac] then
        if not inCapital then out[#out + 1] = home end
    elseif inCapital then
        out[#out + 1] = L["PLAN_PORTAL"]:format(mapName(landing))
    else
        out[#out + 1] = L["PLAN_THEN"]:format(home, L["PLAN_PORTAL"]:format(mapName(landing)))
    end
    if landing ~= ent.uiMapID then out[#out + 1] = fly end
    return out
end
