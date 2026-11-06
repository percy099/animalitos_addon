-- Account-wide collection summary. The Mount Journal is the source of truth;
-- nothing here is cached in SavedVariables.
local _, ns = ...

local Collection = {}
ns.Collection = Collection

Collection.summary = nil

function Collection:Scan()
    local s = {
        total = 0,
        collected = 0,          -- account-wide, including mounts hidden for this character
        collectedVisible = 0,   -- what Blizzard's Mount Journal counter shows
        collectedHidden = 0,
        missing = 0,
        missingVisible = 0,
        missingHidden = 0,
        missingBySource = {}, -- [sourceType] = count
        scannedAt = time(),
    }
    local list = {}
    local ok = ns.MountJournal:ForEach(function(m)
        s.total = s.total + 1
        if not m.shouldHideOnChar then list[#list + 1] = m end
        if m.isCollected then
            s.collected = s.collected + 1
            if m.shouldHideOnChar then
                s.collectedHidden = s.collectedHidden + 1
            else
                s.collectedVisible = s.collectedVisible + 1
            end
        else
            s.missing = s.missing + 1
            if m.shouldHideOnChar then
                s.missingHidden = s.missingHidden + 1
            else
                s.missingVisible = s.missingVisible + 1
                local st = m.sourceType or -1
                s.missingBySource[st] = (s.missingBySource[st] or 0) + 1
            end
        end
    end)
    if not ok then
        self.summary, self.list = nil, nil
        return nil
    end
    s.visibleTotal = s.collectedVisible + s.missingVisible
    table.sort(list, function(a, b) return a.name < b.name end)
    self.summary, self.list = s, list
    return s
end

--- Raid/dungeon mounts of our dataset grouped by expansion (Encounter
--- Journal tier). The journal has no expansion field, so this covers only
--- dataset sources, not the whole collection. Returns an array sorted by
--- tier: { tier, mounts = {mountID...} (sorted by name), set = {[mountID]=true},
---         collected, artJid } (artJid = an instance for the tile artwork).
function Collection:ByExpansion()
    local byTier, out = {}, {}
    for _, src in ipairs((ns.Data and ns.Data.sources) or {}) do
        local inst = ns.Data.instances[src.journalInstanceID]
        local tier = inst and inst.tier
        if tier then
            local t = byTier[tier]
            if not t then
                t = { tier = tier, mounts = {}, set = {}, collected = 0 }
                byTier[tier] = t
                out[#out + 1] = t
            end
            -- Prefer a raid for the artwork; it is the expansion's best-known picture.
            if not t.artJid or (inst.isRaid and not t.artIsRaid) then
                t.artJid, t.artIsRaid = src.journalInstanceID, inst.isRaid
            end
            if not t.set[src.mountID] then
                t.set[src.mountID] = true
                t.mounts[#t.mounts + 1] = src.mountID
                local m = ns.MountJournal:GetMount(src.mountID)
                if m and m.isCollected then t.collected = t.collected + 1 end
            end
        end
    end
    local function name(id)
        local m = ns.MountJournal:GetMount(id)
        return m and m.name or ""
    end
    for _, t in ipairs(out) do table.sort(t.mounts, function(a, b) return name(a) < name(b) end) end
    table.sort(out, function(a, b) return a.tier < b.tier end)
    return out
end

--- Mounts the journal shows for this character (same set as its counter),
--- sorted by name. Each item is a MountJournal:GetMount record. nil if the
--- journal is not ready yet.
function Collection:GetList()
    if not self.list then self:Scan() end
    return self.list
end

--- Missing-by-source as a list sorted by count (descending).
function Collection:GetMissingBySourceSorted()
    local out = {}
    if not self.summary then return out end
    for st, n in pairs(self.summary.missingBySource) do
        out[#out + 1] = { sourceType = st, count = n, label = ns.MountJournal:GetSourceTypeLabel(st >= 0 and st or nil) }
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end
