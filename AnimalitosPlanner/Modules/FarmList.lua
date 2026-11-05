-- "Farmable now" list (docs/03-funcional.md §5): legacy instances with at
-- least one missing mount whose boss is still lootable this reset, grouped
-- per instance and ordered by proximity.
local _, ns = ...

local FarmList = {}
ns.FarmList = FarmList

local function playerLocation()
    local mapID = C_Map.GetBestMapForUnit("player")
    local ancestors, continent = {}, nil
    local id, guard = mapID, 0
    while id and id > 0 and guard < 10 do
        ancestors[id] = true
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if info.mapType == Enum.UIMapType.Continent then continent = id end
        id, guard = info.parentMapID, guard + 1
    end
    return ancestors, continent
end

--- Builds the list. Returns:
---   entries  = array of { jid, inst, mounts = { [mountID] = { ready = {diff...}, locked = {diff...}, resetAt } },
---                         readyCount, near = 0|1|2 }
---   counts   = { [state] = number of (source, difficulty) pairs }
function FarmList:Build()
    local S = ns.Eligibility.STATES
    local byInstance, counts = {}, {}
    for _, src in ipairs(ns.Data.sources) do
        for _, d in ipairs(src.difficulties) do
            local state, reason, resetAt = ns.Eligibility:Evaluate(src, d)
            counts[state] = (counts[state] or 0) + 1
            if state == S.READY or state == S.LOCKED_OUT or state == S.VERIFY then
                local jid = src.journalInstanceID
                local e = byInstance[jid]
                if not e then
                    e = { jid = jid, inst = ns.Data.instances[jid], mounts = {}, readyCount = 0 }
                    byInstance[jid] = e
                end
                local m = e.mounts[src.mountID]
                if not m then
                    m = { ready = {}, locked = {}, verify = {}, source = src }
                    e.mounts[src.mountID] = m
                end
                if state == S.READY then
                    table.insert(m.ready, d)
                elseif state == S.LOCKED_OUT then
                    table.insert(m.locked, d)
                    m.resetAt = math.min(m.resetAt or resetAt, resetAt)
                else
                    table.insert(m.verify, { difficulty = d, reason = reason })
                end
            end
        end
    end

    local ancestors, continent = playerLocation()
    local entries = {}
    for _, e in pairs(byInstance) do
        for _, m in pairs(e.mounts) do
            if #m.ready > 0 then e.readyCount = e.readyCount + 1 end
        end
        local ent = e.inst.entrance
        e.near = (ent and ancestors[ent.uiMapID] and 2) or (ent and ent.continent == continent and 1) or 0
        entries[#entries + 1] = e
    end
    table.sort(entries, function(a, b)
        if (a.readyCount > 0) ~= (b.readyCount > 0) then return a.readyCount > 0 end
        if a.near ~= b.near then return a.near > b.near end
        if a.readyCount ~= b.readyCount then return a.readyCount > b.readyCount end
        if a.inst.tier ~= b.inst.tier then return a.inst.tier < b.inst.tier end
        return a.jid < b.jid
    end)
    self.entries, self.counts = entries, counts
    return entries, counts
end

function FarmList:InstanceName(jid)
    return (EJ_GetInstanceInfo(jid)) or ("#" .. jid)
end

function FarmList:DifficultyName(d)
    return (GetDifficultyInfo(d)) or tostring(d)
end
