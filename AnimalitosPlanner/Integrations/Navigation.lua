-- Waypoints: Blizzard native user waypoint by default, TomTom optional
-- (docs/02-ux-ui.md §7). Only called from an explicit player action.
local _, ns = ...
local L = ns.L

local Navigation = {}
ns.Navigation = Navigation

local function tomtomAvailable()
    return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
end

function Navigation:IsTomTomAvailable()
    return tomtomAvailable()
end

function Navigation:Mode()
    local mode = ns.Storage.db.settings.navigation
    if mode == "tomtom" and not tomtomAvailable() then return "native" end
    return mode
end

--- Sets a waypoint to an instance entrance. Returns true on success.
function Navigation:GoToInstance(jid)
    local inst = ns.Data.instances[jid]
    local name = ns.FarmList:InstanceName(jid)
    local e = inst and inst.entrance
    if not e then
        ns:Print(L["NAV_NO_ENTRANCE"]:format(name))
        return false
    end
    local zone = C_Map.GetMapInfo(e.uiMapID)
    local where = ("%s %.1f, %.1f"):format(zone and zone.name or "?", e.x * 100, e.y * 100)

    if self:Mode() == "tomtom" then
        TomTom:AddWaypoint(e.uiMapID, e.x, e.y, { title = name, from = "AnimalitosPlanner" })
        ns:Print(L["NAV_SET_TOMTOM"]:format(name, where))
        self:WarnIfOtherContinent(e)
        return true
    end

    if not (C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(e.uiMapID)) then
        ns:Print(L["NAV_CANNOT"]:format(name, where))
        return false
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(e.uiMapID, e.x, e.y))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    ns:Print(L["NAV_SET_NATIVE"]:format(name, where))
    self:WarnIfOtherContinent(e)
    return true
end

--- Native and TomTom arrows only show on the target's continent. Say so and
--- open the world map on the destination so the pin is visible.
function Navigation:WarnIfOtherContinent(e)
    local here = ns.FarmList:PlayerContinent()
    if not e.continent or here == e.continent then return end
    local target = C_Map.GetMapInfo(e.continent)
    ns:Print(L["NAV_OTHER_CONTINENT"]:format(target and target.name or "?"))
    if not InCombatLockdown() and OpenWorldMap then
        OpenWorldMap(e.uiMapID)
    end
end

--- /aplan navdebug: why a waypoint might not be visible.
function Navigation:Debug()
    local function yn(v) return v and "|cff8dd3a8yes|r" or "|cffff5555no|r" end
    local mapID = C_Map.GetBestMapForUnit("player")
    local map = mapID and C_Map.GetMapInfo(mapID)
    local continent = ns.FarmList:PlayerContinent()
    local cont = continent and C_Map.GetMapInfo(continent)
    ns:Print(("navdebug — mode: %s · you: %s (%s) · continent: %s (%s)"):format(self:Mode(),
        map and map.name or "?", tostring(mapID), cont and cont.name or "?", tostring(continent)))
    print("  In-game navigation setting (showInGameNavigation): " .. yn(GetCVarBool("showInGameNavigation")))
    local has = C_Map.HasUserWaypoint()
    print("  User waypoint set: " .. yn(has))
    if has then
        local wp = C_Map.GetUserWaypoint()
        local wmap = wp and C_Map.GetMapInfo(wp.uiMapID)
        local x, y = 0, 0
        if wp and wp.position then x, y = wp.position:GetXY() end
        print(("  Waypoint: %s (%s) %.1f, %.1f"):format(wmap and wmap.name or "?", wp and tostring(wp.uiMapID) or "?", x * 100, y * 100))
    end
    print("  Super-tracking the waypoint: " .. yn(C_SuperTrack.IsSuperTrackingUserWaypoint()))
    if C_SuperTrack.GetHighestPrioritySuperTrackingType then
        print("  Highest-priority super-track type: " .. tostring(C_SuperTrack.GetHighestPrioritySuperTrackingType()))
    end
    if C_Navigation and C_Navigation.GetDistance then
        print("  Navigation distance (yards): " .. tostring(C_Navigation.GetDistance()))
    end
    if C_Navigation and C_Navigation.GetFrame then
        print("  Navigation frame available: " .. yn(C_Navigation.GetFrame() ~= nil))
    end
end

--- World coordinates of a point on a uiMap: continentID, x, y (yards), or nil.
--- Used by the planner to order stops geographically.
function Navigation:WorldPos(uiMapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D and uiMapID) then return nil end
    local ok, continentID, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(x or 0.5, y or 0.5))
    if not ok or not pos then return nil end
    local wx, wy = pos:GetXY()
    return continentID, wx, wy
end

--- Where the Encounter Journal pins an encounter (world bosses): searches the
--- zones under each root continent uiMapID. Returns { uiMapID, x, y, continent } or nil.
function Navigation:FindEncounterOnMaps(encounterID, roots)
    if not (C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap and C_Map.GetMapChildrenInfo) then
        return nil
    end
    for _, root in ipairs(roots) do
        local ok, children = pcall(C_Map.GetMapChildrenInfo, root, Enum.UIMapType.Zone, true)
        for _, child in ipairs(ok and children or {}) do
            local ok2, pins = pcall(C_EncounterJournal.GetEncountersOnMap, child.mapID)
            for _, pin in ipairs(ok2 and pins or {}) do
                if pin.encounterID == encounterID and pin.mapX then
                    return { uiMapID = child.mapID, x = pin.mapX, y = pin.mapY, continent = root }
                end
            end
        end
    end
    return nil
end

-- Continents whose zones are indexed by name (Mount Journal "Zone:" texts).
local ZONE_ROOTS = { 13, 12, 948, 101, 113, 424, 572, 619, 905, 875, 876, 1550, 1978, 2274, 2537 }
local zoneIndex

--- [lowercase zone name] = { uiMapID, continent } for every zone (and
--- sub-zone) under the known continents. Built once (client map data).
function Navigation:ZoneIndex()
    if zoneIndex then return zoneIndex end
    zoneIndex = {}
    if not C_Map.GetMapChildrenInfo then return zoneIndex end
    for _, root in ipairs(ZONE_ROOTS) do
        local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
        for _, child in ipairs(ok and children or {}) do
            local key = child.name and child.name:lower()
            local t = child.mapType
            if key and (t == Enum.UIMapType.Zone or t == Enum.UIMapType.Micro or t == Enum.UIMapType.Dungeon)
                and not zoneIndex[key] then
                zoneIndex[key] = { uiMapID = child.mapID, continent = root }
            end
        end
    end
    return zoneIndex
end

--- Opens the world map on a zone (player action only; not in combat).
function Navigation:OpenMap(uiMapID)
    if InCombatLockdown() or not uiMapID then return false end
    if OpenWorldMap then OpenWorldMap(uiMapID) return true end
    return false
end

--- True if the player knows the spell (mage teleports for the planner).
function Navigation:KnowsSpell(spellID)
    local fn = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown or IsPlayerSpell
    if not fn then return false end
    local ok, known = pcall(fn, spellID)
    return ok and known and true or false
end

--- Localized spell name, or nil.
function Navigation:SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    return GetSpellInfo and (GetSpellInfo(spellID)) or nil
end

--- Name of another mage in the player's group (party or raid), or nil.
function Navigation:GroupMage()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n == 0 then return nil end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, n do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local _, class = UnitClass(unit)
            if class == "MAGE" and UnitIsConnected(unit) then return (UnitName(unit)) end
        end
    end
    return nil
end

function Navigation:SetMode(mode)
    if mode == "tomtom" and not tomtomAvailable() then
        ns:Print(L["NAV_TOMTOM_MISSING"])
        return
    end
    ns.Storage.db.settings.navigation = mode
    ns:Print(L["NAV_MODE"]:format(mode))
end
