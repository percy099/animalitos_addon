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
-- Continents where the player fixed the first stops (journalInstanceIDs,
-- in order); the walk goes on from the last one. Northrend: Eye of
-- Eternity, Icecrown Citadel, Ulduar, Utgarde Pinnacle. Pandaria: Salyis's
-- Warband, Siege of Orgrimmar, Oondasta, Nalak, Throne of Thunder (player's
-- orders).
local FIXED_ORDER = {
    [113] = { 756, 758, 759, 286 },
    [424] = { -725, 369, -826, -814, 362 },
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
        [12] = 75,     -- Caverns of Time (in Tanaris; the portal is named after it)
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
        [2537] = { 2393, 1259190 },      -- Silvermoon City (Midnight, both factions)
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
        [2537] = { 2393, 1259190 },      -- Silvermoon City (Midnight, both factions)
    },
}

-- Travel items any class can own (toy box or bags): one hop to a fixed
-- place, like a mage teleport but with a cooldown, so a mage teleport to
-- the same continent wins. { itemID, landing uiMapID per faction }.
local TRAVEL_ITEMS = {
    [619] = { item = 140192, Alliance = 627, Horde = 627 }, -- Dalaran Hearthstone -> Dalaran (Broken Isles)
    [572] = { item = 110560, Alliance = 582, Horde = 590 }, -- Garrison Hearthstone -> Lunarfall / Frostwall
}

-- Extra zone portals in one faction's capital (Orgrimmar: Caverns of Time,
-- confirmed by the player). Same shape as ZONE_PORTALS.
local FACTION_ZONE_PORTALS = {
    Horde = { [75] = 75, [74] = 75 }, -- Caverns of Time (Dragon Soul, Onyxia via Tanaris, ...) portal
}

-- Zones you cannot fly into: reached through a portal or a ride in another
-- zone (confirmed by the player and warcraft.wiki.gg), per faction.
-- via = uiMapID of the portal's zone; x/y = its position (nil = unknown);
-- text = locale key of the step (default: "Portal to <zone> ...").
local ZONE_ACCESS = {
    [504] = { -- Isle of Thunder: portal in the Vale's shrine (quest chain unlock; route of the player)
        Alliance = { via = 390, viaContinent = 424 },
        Horde    = { via = 390, viaContinent = 424 },
    },
    [1462] = { -- Mechagon Island: Horde rides with Captain Krooz from the Dazar'alor docks
        Horde = { via = 862, viaContinent = 875, text = "PLAN_KROOZ" },
    },
}

-- Places a faction reaches by a chain, not a capital portal. zones = only
-- for these target zones (default: the whole continent); boat = locale key
-- of the last step (%s = target zone when ownZone); lands = where it ends.
local CONTINENT_ROUTES = {
    Alliance = {
        -- Kalimdor, fly to the Echo Isles (Durotar), boat to Zuldazar.
        [875] = { via = 1, viaContinent = 12, boat = "PLAN_BOAT_ZULDAZAR", lands = 862 },
        -- Argus (Antorus): Dalaran (Broken Isles), then the Vindicaar (route of the player).
        [905] = { via = 627, viaContinent = 619, boat = "PLAN_VINDICAAR", lands = 885 },
    },
    Horde = {
        -- Zuldazar, then the Banshee's Wail to the Kul Tiras zone you pick
        -- (after the war campaign unlocks it).
        [876] = { via = 862, viaContinent = 875, boat = "PLAN_BOAT_KULTIRAS", ownZone = true },
        -- Southern Eastern Kingdoms (Karazhan, Zul'Gurub): Shattrath, fly to
        -- the Dark Portal, through to the Blasted Lands (route of the player).
        [13] = { via = 100, viaContinent = 101, boat = "PLAN_DARK_PORTAL", lands = 17,
                 zones = { [17] = true, [42] = true, [50] = true, [51] = true, [210] = true, [224] = true } },
        [905] = { via = 627, viaContinent = 619, boat = "PLAN_VINDICAAR", lands = 885 },
    },
}

-- Rough minutes for the "time left" estimate (shown with "≈").
local MINUTES = { raid = 15, dungeon = 10, travel = 4, event = 10 }

local function faction()
    local f = UnitFactionGroup("player")
    return (f == "Horde") and "Horde" or "Alliance"
end

-- Static route ----------------------------------------------------------------
local cachedRoute, cachedFaction

--- Forget the route (a world boss position was found after it was computed).
function Planner:InvalidateRoute()
    cachedRoute = nil
end

local function entrancePos(inst)
    local e = inst.entrance
    local _, x, y = ns.Navigation:WorldPos(e.uiMapID, e.x, e.y)
    return x, y
end

--- Every dataset instance with an entrance, in route order (journalInstanceIDs),
--- followed by those without an entrance. Computed once per faction.
--- fac: whose route order (default: this character's faction; the group
--- route uses the leader's).
function Planner:Route(fac)
    fac = fac or faction()
    if cachedRoute and cachedFaction == fac then return cachedRoute end
    ns.FarmList:ResolveFactionEntrances() -- Horde Battle of Dazar'alor

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
        -- Stops the player put first, in their order.
        for _, fixed in ipairs(FIXED_ORDER[c] or {}) do
            for i, jid in ipairs(left) do
                if jid == fixed then
                    table.remove(left, i)
                    route[#route + 1] = jid
                    if pts[jid] then cx, cy = pts[jid][1], pts[jid][2] end
                    break
                end
            end
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
-- The group sync keeps the latest change: each mark / unmark has the server
-- time it was made (same clock for everyone), and Clear marks a time before
-- which every mark counts as cleared. Marks from before this had no time
-- (0): any later Clear removes them.
local function charData()
    local key = ns:GetCharacterKey()
    local cd = ns.Storage.db.characterData
    cd[key] = cd[key] or {}
    return cd[key]
end
local function doneTable()
    local c = charData()
    c.plannerDone = c.plannerDone or {}
    return c.plannerDone
end
local function stamps()
    local c = charData()
    c.plannerStamp = c.plannerStamp or {}
    return c.plannerStamp
end
local function serverNow() return GetServerTime and GetServerTime() or time() end
local STAMP_KEEP = 8 * 86400 -- longer than the weekly reset

function Planner:IsManuallyDone(jid)
    local untilTime = doneTable()[jid]
    if not untilTime then return false end
    if untilTime > time() then return true end
    doneTable()[jid] = nil
    return false
end

--- fromPeer: the mark came from another player (not shared back).
--- stamp: when it was made (server time); now when nil.
function Planner:SetManuallyDone(jid, isRaid, done, fromPeer, stamp)
    stamp = stamp or serverNow()
    stamps()[jid] = stamp
    -- In the group route anyone's Done / undo applies to everyone.
    if not fromPeer and ns.Comm then ns.Comm:ShareMark(jid, done, stamp) end
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

--- When I last pressed Clear marks (or a peer did, once synced); 0 = never.
function Planner:ClearedAt()
    return charData().plannerClearAt or 0
end

--- Every mark / unmark with its time, for the group sync:
--- { { key, stamp, done }, ... }. Old ones are dropped.
function Planner:MarkLog()
    local out, t, oldest = {}, stamps(), serverNow() - STAMP_KEEP
    for jid, stamp in pairs(t) do
        if stamp < oldest then
            t[jid] = nil
        elseif stamp > self:ClearedAt() then
            out[#out + 1] = { key = jid, stamp = stamp, done = self:IsManuallyDone(jid) }
        end
    end
    return out
end

--- A peer's Clear marks: if newer than mine, every mark older than it goes.
--- Returns true when something changed.
function Planner:ApplyClear(at)
    if not at or at <= self:ClearedAt() then return false end
    charData().plannerClearAt = at
    local t, st = doneTable(), stamps()
    for jid in pairs(t) do
        if (st[jid] or 0) < at then t[jid] = nil end
    end
    return true
end

--- A peer's mark / unmark: applied only if newer than my last change of
--- that step and than my last Clear. Returns true when applied.
function Planner:ApplyPeerMark(jid, done, stamp)
    if not stamp or stamp <= (stamps()[jid] or 0) or stamp <= self:ClearedAt() then return false end
    local inst = ns.Data.instances[jid]
    self:SetManuallyDone(jid, inst and inst.isRaid, done, true, stamp)
    return true
end

--- which = "all" | "raids" | "dungeons"
function Planner:ResetMarks(which)
    local t = doneTable()
    local now = serverNow()
    for jid in pairs(t) do
        local inst = ns.Data.instances[jid]
        local isRaid = inst and inst.isRaid
        if which == "all" or (which == "raids" and isRaid) or (which == "dungeons" and not isRaid) then
            t[jid] = nil
            stamps()[jid] = now
        end
    end
    -- Clear everything: the whole group clears too (latest change wins).
    if which == "all" then
        charData().plannerClearAt = now
        wipe(stamps())
        if ns.Comm then ns.Comm:ShareMarks() end
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
--- Kind of a dataset instance for the Planner filter.
local function kindOf(inst)
    if inst.worldBoss then return "worldBoss" end
    return inst.isRaid and "raid" or "dungeon"
end

--- Which kinds the Planner shows: { raid, dungeon, worldBoss } booleans,
--- saved in db.ui.plannerKinds. Default: raids and dungeons (world bosses
--- are many and opt-in; the old plannerWorldBosses switch carries over).
function Planner:Kinds()
    local ui = ns.Storage.db.ui
    if not ui.plannerKinds then
        ui.plannerKinds = { raid = true, dungeon = true, worldBoss = ui.plannerWorldBosses and true or false }
        ui.plannerWorldBosses = nil
    end
    return ui.plannerKinds
end

--- Turns one kind on or off; at least one of raid / dungeon / worldBoss
--- stays on. "favorites" (only instances with a favorite mount) is a
--- separate flag on top.
function Planner:SetKind(kind, on)
    local k = self:Kinds()
    if not on and kind ~= "favorites" then
        local others = 0
        for _, key in ipairs({ "raid", "dungeon", "worldBoss" }) do
            if k[key] and key ~= kind then others = others + 1 end
        end
        if others == 0 then return false end
    end
    k[kind] = on and true or false
    if ns.Comm then ns.Comm:ShareNeeds() end -- what this player shares changed
    return true
end

--- Which route the Planner shows: "full" (everything farmable) or "mine"
--- (only the mounts in My route). db.ui.plannerMode. The group route goes
--- on top of either (GroupOn): each player shares the route they picked.
function Planner:Mode()
    return ns.Storage.db.ui.plannerMode == "mine" and "mine" or "full"
end

function Planner:SetMode(mode)
    ns.Storage.db.ui.plannerMode = (mode == "mine") and "mine" or nil
    if ns.Comm then ns.Comm:ShareNeeds() end -- what this player shares changed
end

function Planner:GroupOn()
    local ui = ns.Storage.db.ui
    if ui.plannerMode == "group" then ui.plannerMode, ui.plannerGroup = nil, true end -- 0.28.1
    return ui.plannerGroup and true or false
end

function Planner:SetGroup(on)
    ns.Storage.db.ui.plannerGroup = on and true or nil
end

-- My route: the entry with only the picked mounts (so "done" and the mount
-- list only look at those); nil when none of its mounts is picked.
local function routeOnly(e)
    local mounts, any = {}, false
    for id, m in pairs(e.mounts) do
        if ns.Collection:InRoute(id) then mounts[id] = m any = true end
    end
    if not any then return nil end
    local copy = {}
    for k, v in pairs(e) do copy[k] = v end
    copy.mounts = mounts
    return copy
end

local function hasFavorite(e)
    for mountID in pairs(e.mounts) do
        if ns.Collection:IsFavorite(mountID) then return true end
    end
    return false
end

--- What this player brings to the group route: its entry after its own
--- route choice (My route) and Show filter, or nil. Each player filters for
--- themselves; the union is not filtered again, so everyone sees the same
--- steps.
function Planner:OwnStep(e, kinds)
    kinds = kinds or self:Kinds()
    if e and self:Mode() == "mine" then e = routeOnly(e) end
    if e and e.inst and kinds[kindOf(e.inst)] and (not kinds.favorites or hasFavorite(e)) then return e end
    return nil
end

-- Dataset sources by journal instance (lazy).
local srcByJid
local function sourcesOf(jid)
    if not srcByJid then
        srcByJid = {}
        for _, src in ipairs(ns.Data.sources) do
            local j = src.journalInstanceID
            srcByJid[j] = srcByJid[j] or {}
            table.insert(srcByJid[j], src)
        end
    end
    return srcByJid[jid] or {}
end

-- Group route -------------------------------------------------------------------
-- Everyone shares a status per instance (Comm:MyStatus): the mounts in their
-- route (pick), every mount they still miss there and their lockouts. The
-- group route is the union of everyone's picks, so every player sees the
-- same steps; each step lists every player with the addon.

-- Difficulties the others can still loot here (their ready mounts among the
-- step's), as votes { [d] = n }, or nil. The leader's "Set H" button uses
-- them even when the leader does not need the step.
local function peerDiffs(jid, peers, M)
    local votes, any = {}, false
    for _, p in ipairs(peers) do
        for _, id in ipairs(p.ready) do
            if M[id] then
                for _, src in ipairs(sourcesOf(jid)) do
                    if src.mountID == id then
                        for _, d in ipairs(src.difficulties or {}) do
                            if d ~= 0 then votes[d] = (votes[d] or 0) + 1 any = true end
                        end
                    end
                end
            end
        end
    end
    return any and votes or nil
end

local function stubMount(jid, id)
    local source
    for _, src in ipairs(sourcesOf(jid)) do
        if src.mountID == id then source = src break end
    end
    return { ready = {}, locked = {}, verify = {}, source = source, peer = true }
end

-- The step with everyone's picked mounts: mine as they are; one only the
-- others picked comes from my full entry if I miss it too (my real state),
-- else as a stand-in. nil when nobody picked anything here.
local function groupEntry(jid, own, full, peers)
    local picks = {}
    for _, p in ipairs(peers) do
        for _, id in ipairs(p.pick) do picks[id] = true end
    end
    if not own and not next(picks) then return nil end
    local inst = ns.Data.instances[jid]
    if not inst then return nil end
    local e = {}
    for k, v in pairs(own or full or {}) do e[k] = v end
    e.jid, e.inst, e.mounts = jid, inst, {}
    for id, m in pairs(own and own.mounts or {}) do e.mounts[id] = m end
    for id in pairs(picks) do
        if not e.mounts[id] then e.mounts[id] = (full and full.mounts[id]) or stubMount(jid, id) end
    end
    e.peerOnly = not own
    e.readyCount = e.readyCount or 0
    e.near = e.near or ns.FarmList:Near(inst) -- the mini's difficulty line at the entrance
    return e
end

local function anyIn(list, M)
    for _, id in ipairs(list or {}) do
        if M[id] then return true end
    end
    return false
end

local function countIn(s, M)
    local seen, n = {}, 0
    for _, list in ipairs({ s.ready, s.locked, s.other }) do
        for _, id in ipairs(list or {}) do
            if M[id] and not seen[id] then seen[id] = true n = n + 1 end
        end
    end
    return n
end

-- One line per player for a step: { name, me, needs, total, canLoot,
-- lockedHere, cd = {difficultyID...} }, me first.
local function groupRows(M, total, mine, peers)
    local rows = {}
    local function add(name, me, s)
        rows[#rows + 1] = { name = name, me = me, total = total, needs = countIn(s, M),
            canLoot = anyIn(s.ready, M), lockedHere = anyIn(s.locked, M), cd = s.cd or {} }
    end
    add(nil, true, mine)
    for _, p in ipairs(peers) do add(p.name, false, p) end
    return rows
end
--- travelRuns (optional): travel texts only up to that many pending runs
--- (the mini shows two; the rest of the route only needs its order).
function Planner:Build(entries, hideCompleted, kinds, travelRuns)
    kinds = kinds or self:Kinds()
    local mine = self:Mode() == "mine"
    local byJid, fullByJid = {}, {}
    for _, e in ipairs(entries or {}) do
        fullByJid[e.jid] = e
        -- Only the kinds the player picked (the route order stays the same).
        e = self:OwnStep(e, kinds)
        if e then byJid[e.jid] = e end
    end
    -- Group route: the union of everyone's routes, in the leader's order;
    -- the leader's done marks count for everyone.
    local group = ns.Comm and ns.Comm:GroupActive()
    local peerList = group and ns.Comm:PeerStatuses() or nil
    local myStatus = group and ns.Comm:MyStatus() or nil
    local leaderPeer = group and ns.Comm:LeaderPeer() or nil

    local runs = {}
    -- World event bosses first: no travel (Dungeon Finder queue), once a
    -- day. Key "ev<lfgID>" for the manual marks (daily reset).
    local S = ns.Eligibility.STATES
    for _, ev in ipairs(ns.FarmList:Holidays()) do
        local fav = not kinds.favorites
        for _, id in ipairs(ev.mounts) do fav = fav or ns.Collection:IsFavorite(id) end
        if mine then
            local picked = false
            for _, id in ipairs(ev.mounts) do picked = picked or ns.Collection:InRoute(id) end
            fav = fav and picked
        end
        if fav then
            local key = "ev" .. ev.h.lfgDungeonID
            local auto = ev.state == S.LOCKED_OUT
            local leader = ns.Comm and ns.Comm:GroupActive() and ns.Comm:LeaderDone(key)
            runs[#runs + 1] = { kind = "run", event = ev, jid = key, inst = { isRaid = false },
                done = auto or self:IsManuallyDone(key) or leader, auto = auto }
        end
    end
    for _, jid in ipairs(self:Route(group and ns.Comm:RouteFaction() or nil)) do
        local e = byJid[jid]
        local rows
        if group then
            -- Everyone's status here (a peer without an entry has every mount
            -- and no lockout). Their picks already passed their own filters.
            local peers = {}
            for _, p in ipairs(peerList) do
                local s = p.status[jid] or ns.Comm.EMPTY
                peers[#peers + 1] = { name = p.name, pick = s.pick, ready = s.ready, locked = s.locked,
                    other = s.other, cd = s.cd }
            end
            e = groupEntry(jid, e, fullByJid[jid], peers)
            if e then
                local M, total = {}, 0
                for id in pairs(e.mounts) do M[id] = true total = total + 1 end
                rows = groupRows(M, total, myStatus[jid] or ns.Comm.EMPTY, peers)
                e.groupDiffs = peerDiffs(jid, peers, M)
            end
        end
        if e then
            local anyReady, anyLocked = false, false
            if rows then
                for _, g in ipairs(rows) do
                    if g.canLoot then anyReady = true end
                    if g.lockedHere then anyLocked = true end
                end
            else
                for _, m in pairs(e.mounts) do
                    if #m.ready > 0 then anyReady = true end
                    if #m.locked > 0 then anyLocked = true end
                end
            end
            -- Auto-done: nobody can loot anything left this reset and something
            -- was killed. Unknown (verify only) is never treated as done.
            local auto = ns.Lockouts.loaded and anyLocked and not anyReady
            local manual = self:IsManuallyDone(jid)
            -- In a group the leader's marks decide (anyone's clicks reach it via MARK).
            -- Until the leader's list arrives: my own lockouts and marks.
            local leaderDone = leaderPeer and ns.Comm:LeaderDone(jid)
            local done
            if leaderDone ~= nil then done = leaderDone or manual
            else done = auto or manual end
            runs[#runs + 1] = { kind = "run", jid = jid, inst = e.inst, e = e,
                done = done, auto = auto, group = rows }
        end
    end
    -- The leader shares its done steps, so everyone's route advances with it.
    if group and UnitIsGroupLeader("player") then
        local keys = {}
        for _, r in ipairs(runs) do
            if r.done then keys[#keys + 1] = tostring(r.jid) end
        end
        ns.Comm:ShareDone(keys)
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
    local pending = 0
    for _, r in ipairs(runs) do
        if not (hideCompleted and r.done) then
            local ent = r.inst.entrance
            if ent then
                -- Past the runs the caller shows: keep the position, skip the texts.
                local skip = travelRuns and pending >= travelRuns
                local texts = skip and {} or self:TravelTexts(fac, here, ent, mage, r.jid)
                for _, text in ipairs(texts) do
                    steps[#steps + 1] = { kind = "travel", text = text, icon = self:TravelIcon(text) }
                end
                if not r.done then travelMinutes = travelMinutes + #texts * MINUTES.travel end
                here.continent, here.zone = ent.continent, ent.uiMapID
                here.x, here.y = ent.x, ent.y -- you come out at the entrance
                here.jid = r.jid
                here.fromInstance = true -- you start inside: walking out takes time
            end
            steps[#steps + 1] = r
            if not r.done then pending = pending + 1 end
        end
    end

    -- Rough time left (only whole when every travel text was built): pending runs plus the travel in front of them.
    local m = travelMinutes
    for _, r in ipairs(runs) do
        if not r.done then
            m = m + ((r.event and MINUTES.event) or (r.inst.isRaid and MINUTES.raid) or MINUTES.dungeon)
        end
    end
    summary.minutes = m
    return steps, summary
end

--- The next two pending runs with the travel in front of each, for the
--- mini window. Travel starts where the previous step ends (done or not:
--- you are where you just finished). Returns current, after, summary:
---   { run = step, travel = { text... } } or nil.
function Planner:Upcoming(entries)
    -- Same choice as the Planner's "Hide completed steps": with it on, travel
    -- skips finished steps (from the capital), so both windows say the same.
    local steps, summary = self:Build(entries, ns.Storage.db.ui.plannerHideDone and true or false, self:Kinds(), 2)
    local found, travel = {}, {}
    for _, s in ipairs(steps) do
        if s.kind == "travel" then
            travel[#travel + 1] = s.text
        elseif s.kind == "run" then
            if not s.done then
                found[#found + 1] = { run = s, travel = travel }
                if #found == 2 then break end
            end
            travel = {}
        end
    end
    -- The current step's travel starts where the player really is (the
    -- route order stays fixed; only the way to its next stop changes).
    -- Inside an instance or with no map: the planned travel stays.
    local cur = found[1]
    local here = self:PlayerHere()
    if cur and here and not cur.run.event and cur.run.inst.entrance then
        cur.travel = self:TravelTexts(faction(), here, cur.run.inst.entrance, self:MageContext(), cur.run.jid)
    end
    return found[1], found[2], summary
end

--- Where the player is, as the route's travel steps see it: { continent,
--- zone } with zone = the zone-level map (a city or subzone map counts as
--- its zone). Inside a dataset instance: its entrance (where you come out);
--- nil inside other instances or without a map.
function Planner:PlayerHere()
    if IsInInstance() then
        local instanceMapID = select(8, GetInstanceInfo())
        for jid, inst in pairs(ns.Data.instances) do
            local ent = inst.entrance
            if inst.mapID == instanceMapID and ent and ent.continent then
                return { continent = ent.continent, zone = ent.uiMapID, x = ent.x, y = ent.y, fromInstance = true,
                    jid = jid }
            end
        end
        return nil
    end
    local id = C_Map.GetBestMapForUnit("player")
    local zone, continent, guard = nil, nil, 0
    while id and id > 0 and guard < 10 do
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if not zone and info.mapType == Enum.UIMapType.Zone then zone = id end
        if info.mapType == Enum.UIMapType.Continent then continent = id break end
        id, guard = info.parentMapID, guard + 1
    end
    if not (zone and continent) then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(zone, "player")
    local x, y = pos and pos.x, pos and pos.y
    if x and (x <= 0 or y <= 0) then x, y = nil, nil end
    return { continent = continent, zone = zone, x = x, y = y }
end
local function mapName(uiMapID)
    local info = uiMapID and C_Map.GetMapInfo(uiMapID)
    return info and info.name or "?"
end

-- True if landing on `a` puts you in `b`: same map, or one is a sub-map of
-- the other (Caverns of Time inside Tanaris).
local function sameArea(a, b)
    if a == b then return true end
    if not a or not b then return false end
    local ia, ib = C_Map.GetMapInfo(a), C_Map.GetMapInfo(b)
    return (ib and ib.parentMapID == a) or (ia and ia.parentMapID == b) or false
end

--- Who can open mage teleports/portals right now: { self = bool, group = name|nil }.
function Planner:MageContext()
    local _, class = UnitClass("player")
    return { self = class == "MAGE", group = ns.Navigation:GroupMage() }
end

-- Text for a mage hop to dest = { uiMapID, spellID }, or nil if nobody can do it.
-- Travel icons -------------------------------------------------------------------
-- Travel steps are plain localized texts; the icon is picked from which
-- locale format the text matches (client textures only).
local ICON = {
    fly    = "Interface\\Minimap\\Tracking\\FlightMaster",
    portal = "Interface\\Icons\\Spell_Arcane_PortalDalaran",
    hearth = "Interface\\Icons\\INV_Misc_Rune_01",
    ride   = "Interface\\Icons\\Ability_Hunter_Pathfinding",
}

-- "Fly to %s" -> "^Fly to (.-)$" (placeholders first, then magic characters).
local patternCache = {}
local function formatPattern(fmt)
    local cached = patternCache[fmt]
    if cached then return cached end
    local p = fmt:gsub("%%[%.%d]*[sdf]", "\1")
    p = p:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = "^" .. p:gsub("\1", "(.-)") .. "$"
    patternCache[fmt] = p
    return p
end

local function spellIcon(nameOrID)
    return nameOrID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(nameOrID) or nil
end

-- Locale key -> icon kind ("spell" = the named spell's own icon), in match order.
local ICON_RULES = {
    { "PLAN_CAST", "spell" }, { "PLAN_USE_ITEM", "item" }, { "PLAN_FLY", "fly" },
    { "PLAN_HEARTH", "hearth" }, { "PLAN_PORTAL_AT", "portal" }, { "PLAN_PORTAL_IN", "portal" },
    { "PLAN_PORTAL", "portal" }, { "PLAN_ASK_PORTAL", "portal" }, { "PLAN_TELEPORT", "portal" },
    { "PLAN_DARK_PORTAL", "portal" }, { "PLAN_BOAT_ZULDAZAR", "ride" }, { "PLAN_BOAT_KULTIRAS", "ride" },
    { "PLAN_KROOZ", "ride" }, { "PLAN_VINDICAAR", "portal" }, { "PLAN_TRAVEL_CONTINENT", "ride" }, { "PLAN_TRAVEL_ZONE", "ride" },
}

--- Icon texture for a travel step text (remembered per text: the same
--- texts come back on every refresh; item icons are not, their names load late).
local iconCache = {}
ns:On("SPELLS_CHANGED", function() wipe(iconCache) end)
local travelIcon
function Planner:TravelIcon(text)
    if not text then return ICON.ride end
    local icon = iconCache[text]
    if icon then return icon end
    local cacheable
    icon, cacheable = travelIcon(self, text)
    if cacheable then iconCache[text] = icon end
    return icon
end

function travelIcon(self, text)
    local L = ns.L
    -- "A » B": the icon of the second hop (the portal you end up taking).
    local _, second = text:match(formatPattern(L["PLAN_THEN"]))
    if second then return travelIcon(self, second) end
    for _, rule in ipairs(ICON_RULES) do
        local arg = text:match(formatPattern(L[rule[1]]))
        if arg then
            if rule[2] == "spell" then
                local t = spellIcon(arg:match("^(.-) %(") or arg)
                return t or ICON.portal, t ~= nil -- not loaded yet: ask again later
            end
            if rule[2] == "item" then
                for _, ti in pairs(TRAVEL_ITEMS) do
                    if ns.Navigation:ItemName(ti.item) == arg and C_Item and C_Item.GetItemIconByID then
                        return C_Item.GetItemIconByID(ti.item)
                    end
                end
                return ICON.hearth
            end
            return ICON[rule[2]], true
        end
    end
    -- A bare spell name: a mage teleport ("Teleport: Theramore").
    local t = spellIcon(text)
    return t or ICON.portal, t ~= nil
end

-- Clickable travel ------------------------------------------------------------
-- Mage teleport -> the matching portal (cast instead when in a group).
-- Checked with KnowsSpell before use, so a wrong ID only means "teleport".
local PORTAL = {
    [3561] = 10059, [3567] = 11417, [88342] = 88345, [88344] = 88346,
    [49359] = 49360, [49358] = 49361, [33690] = 33691, [35715] = 35717,
    [53140] = 53142, [132621] = 132620, [132627] = 132626, [176248] = 176246,
    [176242] = 176244, [224869] = 224871, [281403] = 281400, [281404] = 281402,
    [344587] = 344597, [395277] = 395289, [446540] = 446534, [1259190] = 1259200,
}
local HEARTHSTONE = 6948

-- The known portal for a mage teleport: the hardcoded ID, else found by
-- name in the spellbook (a wrong or new ID). nil when not learned.
local function portalFor(teleportID)
    local portal = PORTAL[teleportID]
    if portal and ns.Navigation:KnowsSpell(portal) then return portal end
    return ns.Navigation:PortalLike(teleportID)
end

-- Spell ID of a mage teleport (or its portal: second return true) this
-- character knows, from its (localized) name, or nil. Alliance and Horde versions share a name ("Teleport:
-- Shattrath" is 33690 and 35715): only a known one counts.
local function mageSpellByName(name)
    local function check(id)
        if not ns.Navigation:KnowsSpell(id) then return nil end
        if ns.Navigation:SpellName(id) == name then return id end
        -- The portal shown in a group, found by name (see portalFor).
        local portal = ns.Navigation:PortalLike(id)
        if portal and ns.Navigation:SpellName(portal) == name then return portal, true end
        return nil
    end
    -- A portal name (shown in a group): that portal.
    for _, portal in pairs(PORTAL) do
        if ns.Navigation:SpellName(portal) == name and ns.Navigation:KnowsSpell(portal) then return portal, true end
    end
    for _, fac in pairs(MAGE) do
        for key, d in pairs(fac) do
            if key == "zone" then
                for _, z in pairs(d) do
                    local id, isPortal = check(z[2])
                    if id then return id, isPortal end
                end
            else
                local id, isPortal = check(d[2])
                if id then return id, isPortal end
            end
        end
    end
    return nil
end

local function itemAction(itemID)
    if PlayerHasToy and PlayerHasToy(itemID) then return { type = "toy", toy = itemID } end
    local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID) or 0
    if count > 0 then return { type = "item", item = "item:" .. itemID } end
    return nil
end

--- What clicking a travel step does, or nil (fly, ride, capital portals):
--- { type = "spell", spell } | { type = "toy", toy } | { type = "item", item },
--- plus name for the tooltip. Only what this character has. A mage in a
--- group gets the portal (the whole group can take it).
function Planner:TravelAction(text)
    local L = ns.L
    if not text then return nil end
    -- "A  »  B" (hearth / teleport home, then a capital portal): A is clickable.
    local first = text:match(formatPattern(L["PLAN_THEN"]))
    if first then text = first end
    local id, isPortal = mageSpellByName(text)
    if id then
        if isPortal then return { type = "spell", spell = id, name = text } end
        local portal = IsInGroup() and portalFor(id)
        if portal then
            return { type = "spell", spell = portal, name = ns.Navigation:SpellName(portal) }
        end
        return { type = "spell", spell = id, name = text }
    end
    local arg = text:match(formatPattern(L["PLAN_CAST"]))
    if arg then return { type = "spell", spell = arg, name = arg } end -- Mythic+ "Path of ..."
    arg = text:match(formatPattern(L["PLAN_USE_ITEM"]))
    if arg then
        for _, ti in pairs(TRAVEL_ITEMS) do
            if ns.Navigation:ItemName(ti.item) == arg then
                local a = itemAction(ti.item)
                if a then a.name = arg end
                return a
            end
        end
    end
    if text:match(formatPattern(L["PLAN_HEARTH"])) then
        local a = itemAction(HEARTHSTONE)
        if a then a.name = ns.Navigation:ItemName(HEARTHSTONE) end
        return a
    end
    return nil
end

local function mageHop(mage, dest)
    if not (mage and dest) then return nil end
    if mage.self and ns.Navigation:KnowsSpell(dest[2]) then
        -- In a group the click opens the portal (see TravelAction): say so.
        local portal = IsInGroup() and portalFor(dest[2])
        if portal then
            return ns.Navigation:SpellName(portal) or ns.L["PLAN_TELEPORT"]:format(mapName(dest[1]))
        end
        return ns.Navigation:SpellName(dest[2]) or ns.L["PLAN_TELEPORT"]:format(mapName(dest[1]))
    end
    if mage.group then return ns.L["PLAN_ASK_PORTAL"]:format(mage.group, mapName(dest[1])) end
    return nil
end

-- Hubs with a portal back to both capitals, by continent (the usual
-- arrival city). Used when the hearthstone is not set to the capital.
local HOME_PORTAL = {
    any = {
        [101] = 111,   -- Shattrath
        [113] = 125,   -- Dalaran (Northrend)
        [424] = 390,   -- Vale of Eternal Blossoms (Shrine)
        [619] = 627,   -- Dalaran (Broken Isles)
        [1550] = 1670, -- Oribos
        [1978] = 2112, -- Valdrakken
        [2274] = 2339, -- Dornogal
        [2537] = 2393, -- Silvermoon City
    },
    Alliance = { [572] = 622, [876] = 1161 }, -- Stormshield, Boralus
    Horde    = { [572] = 624, [875] = 1165 }, -- Warspear, Dazar'alor
}
local function homeHub(fac, continent)
    return (HOME_PORTAL[fac] and HOME_PORTAL[fac][continent]) or HOME_PORTAL.any[continent]
end

-- Is the hearthstone set to this map? GetBindLocation gives the place's
-- (localized) name.
local function boundTo(uiMapID)
    local bind = GetBindLocation and GetBindLocation()
    return bind and bind ~= "" and bind == mapName(uiMapID)
end

--- Back to the capital from `here`, as a list of travel texts: mage
--- teleport, hearthstone (only when set to the capital), the portal of the
--- continent's hub, the hearthstone to a hub with that portal, or plain
--- travel.
local function homeTexts(fac, here, mage)
    local L = ns.L
    local capital = mapName(CAPITAL[fac])
    local mageHome = mageHop(mage, MAGE[fac].capital)
    if mageHome then return { mageHome } end
    if boundTo(CAPITAL[fac]) then return { L["PLAN_HEARTH"]:format(capital) } end
    local portal = L["PLAN_PORTAL"]:format(capital)
    local hub = homeHub(fac, here.continent)
    if hub then
        if sameArea(hub, here.zone) then return { portal } end
        return { L["PLAN_FLY"]:format(mapName(hub)), portal }
    end
    for _, list in pairs(HOME_PORTAL) do
        for _, h in pairs(list) do
            if boundTo(h) then return { L["PLAN_HEARTH"]:format(mapName(h)), portal } end
        end
    end
    if here.continent == HOME_CONTINENT[fac] then return { L["PLAN_FLY"]:format(capital) } end
    return { L["PLAN_TRAVEL_ZONE"]:format(capital) }
end

-- Distances on the world map (yards), to compare a direct flight with a
-- mage hop. Points are a map's center unless x/y are given.
local posCache = {}
local function worldPos(uiMapID, x, y)
    if not (uiMapID and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local key = uiMapID .. ":" .. (x or 0.5) .. ":" .. (y or 0.5)
    local p = posCache[key]
    if p == nil then
        local cont, pos = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(x or 0.5, y or 0.5))
        p = (cont and pos) and { cont, pos.x, pos.y } or false
        posCache[key] = p
    end
    return p or nil
end
local function distance(a, b)
    if not (a and b) or a[1] ~= b[1] then return nil end
    return math.sqrt((a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end
-- What one teleport / portal costs, as flying distance (loading screen,
-- walking to the next portal).
local HOP_COST = 600
-- Walking out of the instance you just finished (Return to Karazhan's
-- tower top): a teleport from inside skips it.
local EXIT_COST = 1500

--- With a mage at hand, on the same continent: a teleport (or teleport home
--- plus a capital portal) that lands much closer to the entrance than a
--- direct flight. Returns the travel texts, or nil to fly.
local function returnPortalHere(fac, here)
    local z = here.zone
    if not z then return false end
    local hub = homeHub(fac, here.continent)
    if hub and sameArea(hub, z) then return true end
    for _, t in ipairs({ ZONE_PORTALS, FACTION_ZONE_PORTALS[fac] or {}, CONTINENT_PORTALS[fac] }) do
        for _, landing in pairs(t) do
            if sameArea(landing, z) then return true end
        end
    end
    return false
end

local function mageShortcut(fac, here, ent, mage)
    local target = worldPos(ent.uiMapID, ent.x, ent.y)
    -- From where you really are (an entrance, your position), not the
    -- zone center: Ulduar is at the far north of the Storm Peaks.
    local direct = distance(worldPos(here.zone, here.x, here.y), target)
    if not direct then return nil end
    if here.fromInstance then direct = direct + EXIT_COST end
    local L = ns.L
    local best, bestCost = nil, direct
    -- /aplan travel shows this comparison for the mini's next step.
    local log = { to = mapName(ent.uiMapID), direct = direct, options = {} }
    Planner.lastShortcut = log
    local function try(landing, hops, texts)
        local d = distance(worldPos(landing), target)
        if not d then return end
        local cost = d + hops * HOP_COST
        log.options[#log.options + 1] = { text = texts[1], cost = cost }
        if cost < bestCost then
            best, bestCost = texts, cost
            if not sameArea(landing, ent.uiMapID) then texts[#texts + 1] = L["PLAN_FLY"]:format(mapName(ent.uiMapID)) end
        end
    end
    -- One teleport (Dalaran, Stonard, Theramore, ...).
    for key, d in pairs(MAGE[fac]) do
        local list = key == "zone" and d or { d }
        for _, dest in pairs(list) do
            local hop = mageHop(mage, dest)
            if hop then try(dest[1], 1, { hop }) end
        end
    end
    -- Home to the capital: mage teleport, or for anyone the return portal
    -- of a portal zone / hub (Mount Hyjal's Nordrassil -> Orgrimmar). Then
    -- fly from the capital, or take one of its portals (Caverns of Time
    -- for Onyxia).
    local home = mageHop(mage, MAGE[fac].capital)
        or (returnPortalHere(fac, here) and L["PLAN_PORTAL"]:format(mapName(CAPITAL[fac])))
    if home then
        try(CAPITAL[fac], 1, { home })
        local seen = {}
        local function portals(t)
            for _, landing in pairs(t or {}) do
                if not seen[landing] then
                    seen[landing] = true
                    try(landing, 2, { L["PLAN_THEN"]:format(home, L["PLAN_PORTAL"]:format(mapName(landing))) })
                end
            end
        end
        portals(ZONE_PORTALS)
        portals(FACTION_ZONE_PORTALS[fac])
        portals(CONTINENT_PORTALS[fac])
    end
    -- Only when clearly better than flying (half the way or less; from
    -- inside an instance, any clear gain, since the exit is skipped).
    log.limit = direct * (here.fromInstance and 0.85 or 0.5)
    if best and bestCost < log.limit then return best end
    return nil
end

--- /aplan travel: the last fly-or-teleport comparison (distances in yards).
function Planner:DebugTravel()
    local log = self.lastShortcut
    if not log then
        print("  " .. ns.L["TRAVEL_NONE"])
        return
    end
    print(ns.L["TRAVEL_DIRECT"]:format(log.to, log.direct, log.limit or 0))
    for _, o in ipairs(log.options) do print(("    %s: %.0f"):format(o.text or "?", o.cost)) end
end

-- Separate continent maps joined by land: from these zones, fly across
-- (Silvermoon -> Eastern Plaguelands / Stratholme, and back).
-- [continent] = { [zone on the other continent] = true }.
local FLY_ACROSS = {
    [2537] = { [23] = true, [22] = true }, -- Quel'Thalas <-> Eastern / Western Plaguelands
}

-- Mage hops the player picked after an instance, where the distance rule
-- says fly: [journalInstanceID] = { [target zone] = MAGE key, continent =
-- MAGE key for any target on the same continent }. Karazhan -> Zul'Gurub:
-- portal to Stonard (Horde). Siege of Orgrimmar -> anywhere in Pandaria:
-- portal to the Vale (no walking out of the raid). "fly" = just fly, even
-- with a mage hop into the target zone (Salyis -> Siege: next door).
local MAGE_AFTER = {
    [-725] = { [390] = "fly" }, -- Salyis's Warband -> Vale of Eternal Blossoms
    [745] = { [50] = 13 }, -- Karazhan -> Northern Stranglethorn
    [860] = { [50] = 13 }, -- Return to Karazhan -> Northern Stranglethorn
    [369] = { continent = 424 }, -- Siege of Orgrimmar -> Vale of Eternal Blossoms
}

local function flyAcross(here, ent)
    local near = FLY_ACROSS[here.continent]
    if near and near[ent.uiMapID] then return true end
    near = FLY_ACROSS[ent.continent]
    return near and near[here.zone] or false
end

--- Travel step texts from `here` ({continent, zone}) to an entrance.
--- Mage teleports / group portals first, then hand-written capital portals;
--- anything unknown falls back to "Travel to ...".
function Planner:TravelTexts(fac, here, ent, mage, jid)
    local L = ns.L
    local after = here.fromInstance and here.jid and MAGE_AFTER[here.jid]
    local key = after and (after[ent.uiMapID] or (ent.continent == here.continent and after.continent))
    if key == "fly" then return { L["PLAN_FLY"]:format(mapName(ent.uiMapID)) } end
    local dest = key and MAGE[fac][key]
    local hop = dest and mageHop(mage, dest)
    if hop then
        if sameArea(dest[1], ent.uiMapID) then return { hop } end
        return { hop, L["PLAN_FLY"]:format(mapName(ent.uiMapID)) }
    end
    if ent.continent == here.continent and (ent.uiMapID == here.zone or sameArea(ent.uiMapID, here.zone)) then
        return {} -- already there (Dazar'alor is inside Zuldazar)
    end
    if flyAcross(here, ent) then return { L["PLAN_FLY"]:format(mapName(ent.uiMapID)) } end
    -- Coming from farther away to a zone next to another continent's city
    -- (Stratholme from Silvermoon): get to that city, then fly across.
    for c, near in pairs(FLY_ACROSS) do
        local city = CONTINENT_PORTALS[fac][c]
        if near[ent.uiMapID] and city and here.continent ~= c and here.continent ~= ent.continent then
            local out = self:TravelTexts(fac, here, { continent = c, uiMapID = city }, mage)
            out[#out + 1] = L["PLAN_FLY"]:format(mapName(ent.uiMapID))
            return out
        end
    end

    -- A known Mythic+ teleport goes straight to the entrance: best of all.
    -- Not in a group with a mage, though: the others cannot follow a
    -- personal teleport, and the mage's portal takes everyone.
    local groupPortal = IsInGroup() and mage and (mage.self or mage.group)
    if jid and jid > 0 and not groupPortal then
        local spellID, spellName = ns.Navigation:DungeonTeleport(ns.FarmList:InstanceName(jid))
        if spellID then return { L["PLAN_CAST"]:format(spellName or "?") } end
    end

    -- Leaving a portal-only zone: take its portal back first (a mage
    -- teleport or the hearthstone also work, so only when flying out).
    local from = ZONE_ACCESS[here.zone] and ZONE_ACCESS[here.zone][fac]
    if from and ent.uiMapID ~= here.zone then
        local rest = self:TravelTexts(fac, { continent = from.viaContinent, zone = from.via }, ent, mage)
        local first = rest[1]
        if first and first:find(L["PLAN_FLY"]:format(""), 1, true) == 1 then
            table.insert(rest, 1, L["PLAN_PORTAL"]:format(mapName(from.via)))
        end
        return rest
    end

    -- Entering a portal-only zone: go to the portal's zone, then take it.
    local access = ZONE_ACCESS[ent.uiMapID] and ZONE_ACCESS[ent.uiMapID][fac]
    if access then
        local out = self:TravelTexts(fac, here, { continent = access.viaContinent, uiMapID = access.via }, mage)
        if access.text then
            out[#out + 1] = L[access.text]:format(mapName(ent.uiMapID))
        elseif access.x then
            out[#out + 1] = L["PLAN_PORTAL_AT"]:format(mapName(ent.uiMapID), mapName(access.via), access.x, access.y)
        else
            out[#out + 1] = L["PLAN_PORTAL_IN"]:format(mapName(ent.uiMapID), mapName(access.via))
        end
        return out
    end

    -- A place reached by a chain (Alliance -> Zandalar by boat, Horde ->
    -- Kul Tiras, Horde -> Karazhan), unless a mage teleport goes there.
    local route = CONTINENT_ROUTES[fac] and CONTINENT_ROUTES[fac][ent.continent]
    if route and route.zones and not route.zones[ent.uiMapID] then route = nil end
    if route and ent.continent ~= here.continent and not mageHop(mage, MAGE[fac][ent.continent]) then
        local out = self:TravelTexts(fac, here, { continent = route.viaContinent, uiMapID = route.via }, mage)
        out[#out + 1] = L[route.boat]:format(mapName(ent.uiMapID))
        if route.lands and not sameArea(route.lands, ent.uiMapID) then
            out[#out + 1] = L["PLAN_FLY"]:format(mapName(ent.uiMapID))
        end
        return out
    end

    local out = {}

    local inCapital = here.zone == CAPITAL[fac]
    local capital = mapName(CAPITAL[fac])
    local zonePortal = ZONE_PORTALS[ent.uiMapID]
        or (FACTION_ZONE_PORTALS[fac] and FACTION_ZONE_PORTALS[fac][ent.uiMapID])
    local contPortal = CONTINENT_PORTALS[fac][ent.continent]
    local fly = L["PLAN_FLY"]:format(mapName(ent.uiMapID))

    -- A mage teleport straight into the instance's zone beats flying or any
    -- portal chain, even on the same continent (Caverns of Time -> Theramore
    -- for Onyxia). Mage teleports work from anywhere.
    local zoneDest = MAGE[fac].zone[ent.uiMapID]
    if not zoneDest then
        for key, d in pairs(MAGE[fac]) do
            if key ~= "zone" and sameArea(d[1], ent.uiMapID) then zoneDest = d break end
        end
    end
    local hop = mageHop(mage, zoneDest)
    if hop then
        out[1] = hop
        return out
    end

    -- Back to the capital: mage teleport / portal, the hearthstone if set
    -- there, else the nearest hub's portal (homeTexts).
    local mageHome = mageHop(mage, MAGE[fac].capital)
    local home = homeTexts(fac, here, mage)

    -- Same continent: fly, unless a capital zone portal is at hand (in the
    -- capital, or a free mage trip there: Dustwallow -> Stormwind -> Uldum),
    -- or a mage hop lands much closer (ICC -> Dalaran -> Howling Fjord).
    if ent.continent == here.continent and not ((inCapital or mageHome) and zonePortal) then
        local shortcut = mageShortcut(fac, here, ent, mage)
        if shortcut then return shortcut end
        out[1] = fly
        return out
    end

    -- Another continent with a mage city (no zone portal is closer). One
    -- teleport beats hearth + portal, unless the capital portal lands right
    -- in the instance's zone: Stormwind -> Caverns of Time beats Theramore +
    -- flying to Tanaris, but Dalaran beats Azsuna for the Broken Shore.
    local dest = MAGE[fac][ent.continent]
    local useful = dest and (sameArea(dest[1], ent.uiMapID) or not contPortal
        or not sameArea(contPortal, ent.uiMapID))
    if ent.continent ~= here.continent and not zonePortal and useful then
        hop = mageHop(mage, dest)
        if hop then
            out[1] = hop
            if not sameArea(dest[1], ent.uiMapID) then out[2] = fly end
            return out
        end
    end

    -- A travel item for that continent (Dalaran / Garrison Hearthstone),
    -- same rule as a mage teleport: skipped if the capital portal arrives.
    local ti = TRAVEL_ITEMS[ent.continent]
    local tiLanding = ti and ti[fac]
    if tiLanding and ent.continent ~= here.continent and not zonePortal
        and (sameArea(tiLanding, ent.uiMapID) or not contPortal or not sameArea(contPortal, ent.uiMapID))
        and ns.Navigation:HasTravelItem(ti.item) then
        local itemName = ns.Navigation:ItemName(ti.item)
        out[1] = itemName and L["PLAN_USE_ITEM"]:format(itemName) or L["PLAN_TELEPORT"]:format(mapName(tiLanding))
        if not sameArea(tiLanding, ent.uiMapID) then out[2] = fly end
        return out
    end

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

    -- Name the portal after the sub-zone it really opens to (Caverns of Time).
    local arrives = sameArea(landing, ent.uiMapID)
    local portal = L["PLAN_PORTAL"]:format(mapName(arrives and ent.uiMapID or landing))
    if landing == CAPITAL[fac] then
        if not inCapital then
            for _, h in ipairs(home) do out[#out + 1] = h end
        end
    elseif inCapital then
        out[#out + 1] = portal
    else
        -- The last hop home and the capital portal on one line.
        for i = 1, #home - 1 do out[#out + 1] = home[i] end
        out[#out + 1] = L["PLAN_THEN"]:format(home[#home], portal)
    end
    if not arrives then out[#out + 1] = fly end
    return out
end
