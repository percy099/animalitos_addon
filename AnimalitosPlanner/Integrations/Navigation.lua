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

-- Mythic+ dungeon teleports ("Path of ..."): spells inside spellbook flyouts
-- whose description names the dungeon ("Teleport to the entrance to King's
-- Rest."). Read from the player's own spellbook, so localized and always
-- current. Descriptions can load late; the index is rebuilt until complete.
local dungeonTeleports, teleportsComplete

local function collectFlyoutSpells()
    local spells = {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and GetFlyoutInfo and GetFlyoutSlotInfo) then
        return spells
    end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local flyoutType = Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                if item and item.itemType == flyoutType and item.actionID then
                    local _, _, numSlots = GetFlyoutInfo(item.actionID)
                    for s = 1, numSlots or 0 do
                        local spellID, _, isKnown = GetFlyoutSlotInfo(item.actionID, s)
                        if spellID and isKnown then spells[#spells + 1] = spellID end
                    end
                end
            end
        end
    end
    return spells
end

--- Known mage portal to the same place as a teleport, found by name in the
--- spellbook flyouts ("Teleport: Silvermoon City" -> "Portal: Silvermoon
--- City": same text after ": " in every locale). For when the hardcoded
--- portal ID is wrong or new. Returns spellID or nil.
local portalByPlace
function Navigation:PortalLike(teleportID)
    local name = self:SpellName(teleportID)
    local place = name and name:match(":%s*(.+)$")
    if not place then return nil end
    if not portalByPlace or portalByPlace[place] == nil then
        portalByPlace = portalByPlace or {}
        local ok, spells = pcall(collectFlyoutSpells)
        for _, id in ipairs(ok and spells or {}) do
            local n = self:SpellName(id)
            local p = n and n:match(":%s*(.+)$")
            if p and p == place and id ~= teleportID and n ~= name then portalByPlace[p] = id end
        end
        if portalByPlace[place] == nil then portalByPlace[place] = false end
    end
    return portalByPlace[place] or nil
end
ns:On("SPELLS_CHANGED", function() portalByPlace = nil end)

--- Known dungeon-teleport spell whose description mentions the instance
--- name, as spellID, spellName; or nil.
function Navigation:DungeonTeleport(instanceName)
    if not instanceName or instanceName == "" then return nil end
    -- Rebuild when missing, or (at most every 10 s) while descriptions load.
    local now = GetTime()
    if not dungeonTeleports or (not teleportsComplete and now - (self.teleportsAt or 0) > 10) then
        self.teleportsAt = now
        dungeonTeleports, teleportsComplete = {}, true
        local ok, spells = pcall(collectFlyoutSpells)
        for _, id in ipairs(ok and spells or {}) do
            local desc = C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id)
            if desc and desc ~= "" then
                dungeonTeleports[#dungeonTeleports + 1] = { id = id, desc = desc:lower() }
            else
                teleportsComplete = false -- not loaded yet; ask and retry later
                if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(id) end
            end
        end
    end
    local key = instanceName:lower()
    for _, t in ipairs(dungeonTeleports) do
        if t.desc:find(key, 1, true) then return t.id, self:SpellName(t.id) end
    end
    return nil
end

--- True if the player has a travel item: in the toy box or in the bags.
function Navigation:HasTravelItem(itemID)
    if PlayerHasToy and PlayerHasToy(itemID) then return true end
    local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID))
        or (GetItemCount and GetItemCount(itemID)) or 0
    return count > 0
end

--- Localized item name, or nil while the item is not cached.
function Navigation:ItemName(itemID)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return name
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
