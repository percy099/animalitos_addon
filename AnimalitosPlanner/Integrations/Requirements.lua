-- What a vendor asks for before selling a mount, and whether this character
-- has it, price included (gold, currencies, items: Wallet). Sources, all
-- from the client:
--   * the mount item's tooltip (item from ns.Data.mountItems, built by
--     /aplan scan items): reputation, faction, class, race and skill lines.
--     The client paints them red when not met.
--   * the journal text: "Renown: 25" (with "Faction: X") or
--     "Renown: X Rank 8", and "Achievement: Name". "Covenant" and
--     "World Event" cannot be checked: they stay unknown (never "met").
--   * Remix mounts are ignored: they cannot be obtained.
local _, ns = ...

local R = {}
ns.Requirements = R

local VENDOR_SOURCE = 3

local ICON_OK = "|A:common-icon-checkmark:12:12|a"
local ICON_NO = "|A:common-icon-redx:12:12|a"
local ICON_UNKNOWN = "|cff999999?|r"
R.ICON = { [true] = ICON_OK, [false] = ICON_NO }
R.ICON_UNKNOWN = ICON_UNKNOWN

local cache = {}      -- [mountID] = result (cleared by Invalidate)
local pending = {}    -- [itemID] = true while the client loads it
local vendorSet, vendorCount, building, dirty

-- Tooltip lines that are requirements: built from the client's own format
-- strings, so they match in any language.
local reqPatterns
local function toPattern(f)
    f = f:gsub("%%%d?%$?[sd]", "\1")
    f = f:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    f = f:gsub("\1", ".+")
    return "^" .. f .. "$"
end
local function isRequirementLine(text)
    if not reqPatterns then
        reqPatterns = {}
        for _, g in ipairs({ "ITEM_REQ_REPUTATION", "ITEM_REQ_SKILL", "ITEM_CLASSES_ALLOWED",
                             "ITEM_RACES_ALLOWED", "ITEM_REQ_HORDE", "ITEM_REQ_ALLIANCE" }) do
            if type(_G[g]) == "string" then reqPatterns[#reqPatterns + 1] = toPattern(_G[g]) end
        end
    end
    for _, p in ipairs(reqPatterns) do
        if text:find(p) then return true end
    end
    return false
end

local function isRed(c)
    return c and c.r and c.r > 0.9 and c.g < 0.25 and c.b < 0.25
end

-- Renown factions by lowercase name: { renownLevel }.
local function majorFaction(name)
    if not (C_MajorFactions and C_MajorFactions.GetMajorFactionIDs) then return nil end
    name = name:lower()
    for exp = 0, 20 do
        for _, id in ipairs(C_MajorFactions.GetMajorFactionIDs(exp) or {}) do
            local d = C_MajorFactions.GetMajorFactionData(id)
            if d and d.name and d.name:lower() == name then return d end
        end
    end
    return nil
end

-- Achievements by lowercase name (only the names vendors ask for), built
-- in the background the first time one is needed.
local achIndex, achBuilding
local wantedAch = {}
local function buildAchIndex()
    if achIndex or achBuilding or not next(wantedAch) or not GetCategoryList then return end
    achBuilding = true
    local found = {}
    ns.Collection.RunInBackground(function()
        for _, cat in ipairs(GetCategoryList() or {}) do
            for i = 1, GetCategoryNumAchievements(cat, true) or 0 do
                ns.Collection.Tick()
                local id, name, _, completed = GetAchievementInfo(cat, i)
                if id and name and wantedAch[name:lower()] then found[name:lower()] = completed and true or false end
            end
        end
    end, function()
        achIndex, achBuilding = found, false
        R:Invalidate()
        ns.UI:Refresh()
    end)
end

local priceCache = {} -- [mountID] = parts (the text does not change)
local function priceOf(mountID)
    local parts = priceCache[mountID]
    if parts == nil then
        local extra = ns.MountJournal:GetMountExtra(mountID)
        local text = extra and extra.sourceText
        if not text or text == "" then return {} end -- not loaded yet: try again later
        parts = ns.Wallet:ParseCost(text) or false
        priceCache[mountID] = parts
    end
    return parts or {}
end

local function renownText(rank, name, have)
    return ns.L["REQ_RENOWN"]:format(rank, name, have)
end

-- Requirements from the journal text.
local function fromJournal(mountID, reqs)
    local extra = ns.MountJournal:GetMountExtra(mountID)
    local text = extra and extra.sourceText
    if not text or text == "" then return false end
    local remix, faction = false, nil
    for line in ns.MountJournal:PlainSourceText(text):gmatch("[^\n]+") do
        local label, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
        label = label and label:lower()
        if label == "wow remix" then
            remix = true
        elseif label == "faction" then
            faction = value
        elseif label == "renown" and value ~= "" then
            local rank = tonumber(value)
            local name = faction
            if not rank then name, rank = value:match("^(.-)%s+[Rr]ank%s+(%d+)$") rank = tonumber(rank) end
            local d = name and rank and majorFaction(name)
            if d and d.renownLevel then
                reqs[#reqs + 1] = { text = renownText(rank, d.name, d.renownLevel), met = d.renownLevel >= rank }
            else
                reqs[#reqs + 1] = { text = line, met = nil }
            end
        elseif label == "achievement" and value ~= "" then
            wantedAch[value:lower()] = true
            local done = achIndex and achIndex[value:lower()]
            reqs[#reqs + 1] = { text = line, met = done }
        elseif label == "covenant" or label == "world event" then
            reqs[#reqs + 1] = { text = line, met = nil }
        end
    end
    return remix
end

--- Requirements of a mount sold by a vendor, or nil (not a vendor mount,
--- or no item known). result = { status, reqs = { {text, met} } } with
--- status "met", "none", "missing", "unknown", "remix" or "loading".
--- met: true / false / nil (cannot be checked).
function R:Get(mountID)
    if cache[mountID] then return cache[mountID] end
    local itemID = ns.Data.mountItems and ns.Data.mountItems[mountID]
    if not itemID then return nil end
    local m = ns.MountJournal:GetMount(mountID)
    if not m or m.sourceType ~= VENDOR_SOURCE then return nil end

    if not C_Item.IsItemDataCachedByID(itemID) then
        pending[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
        return { status = "loading", reqs = {} }
    end

    local reqs, remix = {}, false
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(itemID)
    for _, line in ipairs(data and data.lines or {}) do
        local t = line.leftText
        if t and t ~= "" then
            if t:find("Remix", 1, true) then remix = true end
            local red = isRed(line.leftColor)
            if red or isRequirementLine(t) then
                reqs[#reqs + 1] = { text = t, met = not red }
            end
        end
    end
    remix = fromJournal(mountID, reqs) or remix
    if next(wantedAch) and not achIndex then buildAchIndex() end

    -- The price (gold, currencies, items) against what this character has.
    -- Parsed once per mount; "have" is read again after each invalidation.
    local price = {}
    for _, p in ipairs(priceOf(mountID)) do
        local have = ns.Wallet:Have(p)
        local line
        if have == nil or p.kind == "unknown" then
            line, have = ns.Wallet:Format(p, p.need), nil
        elseif have >= p.need then
            line = ns.L["REQ_PRICE_OK"]:format(ns.Wallet:Format(p, p.need), ns.Wallet:Format(p, have))
        else
            line = ns.L["REQ_PRICE_MISSING"]:format(ns.Wallet:Format(p, p.need), ns.Wallet:Format(p, p.need - have))
        end
        if p.name then line = line .. "  |cff999999" .. p.name .. "|r" end
        local met = nil
        if have ~= nil then met = have >= p.need end
        reqs[#reqs + 1] = { text = line, met = met, price = true }
        price[#price + 1] = ns.Wallet:Format(p, p.need)
    end

    local status
    if remix then
        status = "remix"
    else
        local missing, unknown = false, false
        for _, r in ipairs(reqs) do
            if r.met == false then missing = true elseif r.met == nil then unknown = true end
        end
        status = missing and "missing" or unknown and "unknown" or (#reqs > 0 and "met") or "none"
    end
    local result = { status = status, reqs = reqs, price = #price > 0 and table.concat(price, " + ") or nil }
    cache[mountID] = result
    return result
end

--- Missing vendor mounts with nothing missing ("met" or "none"):
--- set, count; nil while it is being built in the background.
function R:VendorSet()
    if vendorSet then return vendorSet, vendorCount end
    if building then return nil end
    local list = ns.Collection:GetList()
    if not list then return nil end
    building, dirty = true, false
    local set, n = {}, 0
    ns.Collection.RunInBackground(function()
        for _, m in ipairs(list) do
            if not m.isCollected and m.sourceType == VENDOR_SOURCE then
                ns.Collection.Tick()
                local r = self:Get(m.mountID)
                if r and (r.status == "met" or r.status == "none") then
                    set[m.mountID] = r -- { status, reqs, price }
                    n = n + 1
                end
            end
        end
    end, function()
        building = false
        if dirty then -- something changed meanwhile: build again on the next refresh
            vendorSet, vendorCount = nil, nil
        else
            vendorSet, vendorCount = set, n
        end
        ns.UI:Refresh()
    end)
    return nil
end

--- Reputation, renown, achievements or the collection changed.
function R:Invalidate()
    wipe(cache)
    vendorSet, vendorCount = nil, nil
    if building then dirty = true end
end

local function changed()
    R:Invalidate()
end
ns:On("UPDATE_FACTION", changed)
ns:On("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", changed)
ns:On("NEW_MOUNT_ADDED", changed)
ns:On("PLAYER_MONEY", changed)
ns:On("CURRENCY_DISPLAY_UPDATE", changed)
ns:On("BAG_UPDATE_DELAYED", changed)
ns:On("ACHIEVEMENT_EARNED", function()
    achIndex = nil
    changed()
end)

-- A tooltip we asked for finished loading: read it again.
ns:On("ITEM_DATA_LOAD_RESULT", function(itemID)
    if not pending[itemID] then return end
    pending[itemID] = nil
    ns:Debounce("reqitems", 0.5, function()
        R:Invalidate()
        ns.UI:Refresh()
    end)
end)
