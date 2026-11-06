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
    self:InvalidateAchievements() -- collected flags changed; rebuild on demand
    return s
end

-- Background work -----------------------------------------------------------
-- Walking every achievement in the game takes far too long for one frame
-- (the screen froze on first open). It runs as a coroutine, resumed with
-- C_Timer.After(0) and given a few milliseconds per frame (no OnUpdate).
local SLICE_MS = 6
local sliceStart = 0

--- Called inside long loops: gives the frame back when the slice is used up.
local function tick()
    if coroutine.running() and debugprofilestop() - sliceStart > SLICE_MS then
        coroutine.yield()
    end
end
Collection.Tick = tick

local function runInBackground(fn, onDone)
    local co = coroutine.create(fn)
    local function step()
        sliceStart = debugprofilestop()
        local ok, err = coroutine.resume(co)
        if not ok then
            geterrorhandler()(err)
            onDone(false)
        elseif coroutine.status(co) == "dead" then
            onDone(true)
        else
            C_Timer.After(0, step)
        end
    end
    step()
end

-- Needles to find an instance in criteria text: its name and its bosses'
-- names (Encounter Journal, so localized). A needle that belongs to two
-- instances is dropped; short ones (< 5 letters) too, to avoid false hits.
local function instanceNeedles()
    local owner = {}
    for jid, inst in pairs(ns.Data.instances) do
        if not inst.worldBoss then
            local names = ns.FarmList:EncounterNames(jid)
            names[#names + 1] = ns.FarmList:InstanceName(jid)
            for _, n in ipairs(names) do
                local key = n:lower()
                if #key >= 5 then
                    if owner[key] == nil then owner[key] = jid
                    elseif owner[key] ~= jid then owner[key] = false end
                end
            end
            tick()
        end
    end
    local list = {}
    for key, jid in pairs(owner) do
        if jid then list[#list + 1] = { key = key, jid = jid } end
    end
    table.sort(list, function(a, b) return #a.key > #b.key end) -- most specific first
    return list
end

-- Each missing criterion that names an instance (or one of its bosses) is
-- linked to it. A hint only; it never changes eligibility.
local function linkToInstances(achs)
    local needles = instanceNeedles()
    local out = {}
    for _, a in ipairs(achs) do
        if not a.mount.isCollected and not a.completed then
            local perJid = {}
            for _, c in ipairs(ns.Achievements:MissingCriteria(a.id)) do
                for _, nd in ipairs(needles) do
                    if c.search:find(nd.key, 1, true) then
                        perJid[nd.jid] = perJid[nd.jid] or {}
                        table.insert(perJid[nd.jid], c.text)
                        break
                    end
                end
                tick()
            end
            for jid, missing in pairs(perJid) do
                out[jid] = out[jid] or {}
                table.insert(out[jid], { ach = a, missing = missing })
            end
        end
    end
    return out
end

-- Builds both caches in the background, then refreshes the open window.
function Collection:BuildAchievements()
    if self.achBuilding or self.achievements then return end
    local list = self:GetList()
    if not list then return end -- journal not ready; the next call retries
    self.achBuilding = true
    local gen = self.achGen or 0
    local result, byInstance, uncached
    runInBackground(function()
        local byName, byID = {}, {}
        for _, m in ipairs(list) do
            byName[m.name:lower()] = m.mountID
            byID[m.mountID] = m
        end
        local found
        found, uncached = ns.Achievements:ScanMounts(byName, tick)
        result = {}
        for _, a in ipairs(found) do
            local m = byID[a.mountID]
            if m then -- visible for this character
                a.mount = m
                result[#result + 1] = a
            end
        end
        table.sort(result, function(a, b)
            if a.mount.isCollected ~= b.mount.isCollected then return not a.mount.isCollected end
            local pa, pb = a.done / a.total, b.done / b.total
            if pa ~= pb then return pa > pb end
            return a.name < b.name
        end)
        byInstance = linkToInstances(result)
    end, function(ok)
        self.achBuilding = false
        if not ok then return end
        if gen ~= (self.achGen or 0) then
            -- Something was earned while building: start over with fresh data.
            self:BuildAchievements()
            return
        end
        self.achievements, self.achByInstance = result, byInstance
        -- Reward items not cached yet: ask for them and rebuild once later.
        if #uncached > 0 and not self.achRetried then
            self.achRetried = true
            ns.Achievements:RequestItems(uncached)
            C_Timer.After(3, function()
                self.achievements, self.achByInstance = nil, nil
                self:BuildAchievements()
            end)
        end
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
    end)
end

--- Mount-reward achievements for mounts this character can see, joined with
--- the Mount Journal (Achievements:ScanMounts fields plus mount). Sorted:
--- not collected first, then by progress. nil while it is still being
--- built in the background (the window refreshes when it is ready).
function Collection:Achievements()
    if not self.achievements then self:BuildAchievements() end
    return self.achievements
end

function Collection:InvalidateAchievements()
    self.achievements, self.achByInstance = nil, nil
    self.achGen = (self.achGen or 0) + 1
end

--- [journalInstanceID] = { { ach = entry, missing = { criterion text... } } }
--- for mount achievements not collected yet. Empty while still building.
function Collection:AchievementsByInstance()
    if not self.achByInstance then self:BuildAchievements() end
    return self.achByInstance or {}
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
