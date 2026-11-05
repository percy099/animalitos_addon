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
    local ok = ns.MountJournal:ForEach(function(m)
        s.total = s.total + 1
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
        self.summary = nil
        return nil
    end
    s.visibleTotal = s.collectedVisible + s.missingVisible
    self.summary = s
    return s
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
