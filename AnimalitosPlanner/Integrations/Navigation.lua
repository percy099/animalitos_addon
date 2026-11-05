-- Waypoints: Blizzard native user waypoint by default, TomTom optional
-- (docs/02-ux-ui.md §7). Only called from an explicit player action.
local _, ns = ...
local L = ns.L

local Navigation = {}
ns.Navigation = Navigation

local function tomtomAvailable()
    return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
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

function Navigation:SetMode(mode)
    if mode == "tomtom" and not tomtomAvailable() then
        ns:Print(L["NAV_TOMTOM_MISSING"])
        return
    end
    ns.Storage.db.settings.navigation = mode
    ns:Print(L["NAV_MODE"]:format(mode))
end
